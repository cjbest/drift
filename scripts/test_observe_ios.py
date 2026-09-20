#!/usr/bin/env python3
"""False-green and evidence-handling checks; no Xcode, ffprobe, or API calls."""
import contextlib
import html
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock


SPEC = importlib.util.spec_from_file_location("observe_ios", Path(__file__).with_name("observe-ios.py"))
observer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(observer)
ROUTE = "JankAuditUITests/testRepeatedBlankComposeAndReturnRecording"


def answer(verdict="clear", findings=None):
    return {"verdict": verdict, "findings": findings or [],
            "reason": "Observed the available recording.", "limitations": []}


def finding(**changes):
    value = {"start": 1.0, "end": 2.0, "observation": "Text moves after settling.",
             "expected": "Text should retain its position.",
             "severity": "noticeable", "confidence": "high"}
    value.update(changes)
    return value


def response(value, status="completed"):
    return {"status": status, "steps": [{"type": "model_output", "content": [
        {"type": "text", "text": json.dumps(value)}]}]}


def result(value):
    return {"video": "video-1", "start": 0.0, "end": 5.0, "request": 1,
            "usage": {}, "seconds": 0.1, "answer": value}


class ObserverTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="drift-observer-test-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.attachments = self.root / "attachments"
        self.attachments.mkdir()
        self.network = self.enterContext(mock.patch.object(
            observer.urllib.request, "build_opener",
            side_effect=AssertionError("Unexpected network request in unit test")))
        self.enterContext(mock.patch.dict(os.environ, {"GEMINI_API_KEY": "unit-test-key"}))

    def manifest_entry(self, filename, failed=False, route=ROUTE):
        return {"testIdentifier": route + "()", "attachments": [
            {"exportedFileName": filename, "isAssociatedWithFailure": failed}]}

    def test_expected_test_with_screenshots_only_is_incomplete(self):
        videos, gaps = observer.exported_videos(
            [self.manifest_entry("settled.png")], self.attachments, [ROUTE])
        self.assertEqual(videos, [])
        self.assertIn("No video retained", gaps[0])
        self.assertEqual(observer.exit_status([], gaps), 2)

    def test_omitted_expected_route_prevents_clear_despite_other_clear_results(self):
        (self.attachments / "passing.mp4").write_bytes(b"synthetic test placeholder")
        missing = "JankAuditUITests/testNewlinesKeepShortPageSteadyRecording"
        videos, gaps = observer.exported_videos(
            [self.manifest_entry("passing.mp4")], self.attachments, [ROUTE, missing])
        self.assertEqual(len(videos), 1)
        self.assertTrue(any(missing in gap for gap in gaps))
        self.assertEqual(observer.exit_status([result(answer())], gaps), 2)

    def test_successful_recording_is_selected_and_duplicate_attachment_is_not_rebilled(self):
        video = self.attachments / "passing.mp4"
        video.write_bytes(b"synthetic test placeholder")
        entry = self.manifest_entry(video.name, failed=False)
        entry["attachments"] *= 2
        videos, gaps = observer.exported_videos(
            [entry], self.attachments, ["DriftUITests/" + ROUTE])
        self.assertEqual(gaps, [])
        self.assertEqual([item["path"] for item in videos], [str(video.resolve())])

    def test_manifest_cannot_read_video_outside_export_directory(self):
        outside = self.root / "outside.mp4"
        outside.write_bytes(b"not an exported recording")
        for name in ("../outside.mp4", str(outside)):
            with self.subTest(name=name), self.assertRaises(ValueError):
                observer.exported_videos([self.manifest_entry(name)], self.attachments)
        (self.attachments / "linked.mp4").symlink_to(outside)
        with self.assertRaises(ValueError):
            observer.exported_videos([self.manifest_entry("linked.mp4")], self.attachments)

    def test_incomplete_and_malformed_model_responses_are_rejected(self):
        malformed = response(answer())
        malformed["steps"][0]["content"][0]["text"] = "not JSON"
        cases = [response(answer(), status="in_progress"), malformed,
                 response(answer("pass")), response({"verdict": "clear", "findings": []})]
        for value in cases:
            with self.subTest(value=value), self.assertRaises(ValueError):
                observer.validate_answer(value, 0, 5)

    def test_verdict_cannot_disagree_with_findings(self):
        for value in (answer("flag"), answer("clear", [finding()])):
            with self.subTest(verdict=value["verdict"]), self.assertRaises(ValueError):
                observer.validate_answer(response(value), 0, 5)

    def test_invalid_timestamps_are_rejected_before_report_links_are_created(self):
        cases = [(-1, 2), (1, 6), (3, 2), (float("nan"), 2),
                 (1, float("inf")), (True, 2), ("1", 2)]
        for start, end in cases:
            with self.subTest(start=start, end=end), self.assertRaises(ValueError):
                observer.validate_answer(response(answer("flag", [finding(start=start, end=end)])), 0, 5)
        accepted = observer.validate_answer(response(answer("flag", [finding(start=0, end=5)])), 0, 5)
        self.assertEqual(accepted["findings"][0]["end"], 5)

    def test_missing_video_produces_incomplete_report_without_external_work(self):
        out = self.root / "missing-report"
        with mock.patch.object(observer, "run_json") as probe, contextlib.redirect_stdout(io.StringIO()):
            code = observer.main(["--video", str(self.root / "missing.mp4"), "--output", str(out)])
        self.assertEqual(code, 2)
        probe.assert_not_called()
        self.network.assert_not_called()
        report = json.loads((out / "report.json").read_text())
        self.assertEqual(report["exit_code"], 2)
        self.assertTrue(report["coverage_gaps"])
        self.assertIn("Review incomplete", (out / "report.html").read_text())

    def test_total_duration_budget_stops_api_requests(self):
        videos = [self.root / "first.mp4", self.root / "second.mp4"]
        for video in videos:
            video.write_bytes(b"synthetic test placeholder")
        probe_result = {"format": {"duration": "4"}, "streams": [{"codec_type": "video"}]}
        out = self.root / "budget-report"
        with mock.patch.object(observer, "run_json", return_value=probe_result), \
                mock.patch.object(observer, "review") as review, contextlib.redirect_stdout(io.StringIO()):
            code = observer.main(["--video", *map(str, videos), "--output", str(out), "--max-seconds", "6"])
        self.assertEqual(code, 2)
        review.assert_not_called()
        self.network.assert_not_called()
        report = json.loads((out / "report.json").read_text())
        self.assertTrue(any("review budget" in gap for gap in report["coverage_gaps"]))

    def test_report_escapes_model_text_without_losing_evidence(self):
        payload = '<img src=x onerror="alert(1)"> & <script>bad()</script>'
        video = {"id": "video-1", "path": str(self.root / "video.mp4"), "test": ROUTE, "context": "Compose"}
        value = answer("flag", [finding(observation=payload, expected=payload)])
        value.update(reason=payload, limitations=[payload])
        report = observer.write_report(self.root, [video], [result(value)], [], 1, 1)
        page = (self.root / "report.html").read_text()
        self.assertEqual(report["exit_code"], 1)
        self.assertIn(html.escape(payload), page)
        self.assertNotIn(payload, page)
        self.assertEqual(json.loads((self.root / "report.json").read_text())["windows"][0]["answer"]["reason"], payload)

    def test_no_results_and_inconclusive_results_never_report_clear(self):
        for results in ([], [result(answer("inconclusive"))],
                        [result(answer()), result(answer("inconclusive"))]):
            with self.subTest(results=results):
                report = observer.write_report(self.root, [], results, [], 1, 0)
                self.assertEqual(report["exit_code"], 2)
                self.assertEqual(report["status"], "Review incomplete")


if __name__ == "__main__":
    unittest.main()

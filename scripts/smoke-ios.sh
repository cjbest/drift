#!/bin/bash
# Record a small synthetic smoke suite in the separate Drift Preview app.
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RECORD_ONLY=0
usage() {
  cat <<'HELP'
Usage: SIMULATOR_ID=<dedicated iOS simulator UUID> scripts/smoke-ios.sh [--record-only]

Builds Drift Preview, records three existing synthetic UI-test routes (including
passing tests), and reviews their videos with scripts/observe-ios.py.

Environment:
  SIMULATOR_ID    Required; an available, dedicated iOS simulator. No device is created.
  OUTPUT_DIR      New output directory; defaults to output/jank-audits/smoke-<UTC time>.
  GEMINI_API_KEY  Required for review; omitted with --record-only.

--record-only    Keep recordings without sending them for model review.
--help          Show this help.

The simulator must already have a usable software keyboard. No simulator
preferences are changed. Existing output is never overwritten. Functional test
failures retain Xcode's exit status; otherwise review exits 0 (clear), 1 (findings),
or 2 (incomplete/setup). A clear review is bounded evidence, not release sign-off.
HELP
}
for arg in "$@"; do
  case "$arg" in
    --record-only) RECORD_ONLY=1 ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown argument: %s\n' "$arg" >&2; usage >&2; exit 2 ;;
  esac
done
fail() { printf '%s\n' "$*" >&2; exit 2; }
[ -n "${SIMULATOR_ID:-}" ] || fail 'Set SIMULATOR_ID to a dedicated iOS simulator UUID.'
if [ "$RECORD_ONLY" -eq 0 ] && [ -z "${GEMINI_API_KEY:-}" ]; then
  fail 'Set GEMINI_API_KEY, or use --record-only.'
fi
for tool in python3 xcrun xcodebuild xcodegen; do
  command -v "$tool" >/dev/null || fail "Required tool missing: $tool"
done
if [ "$RECORD_ONLY" -eq 0 ]; then
  command -v ffprobe >/dev/null || fail 'Video review requires ffprobe (brew install ffmpeg).'
fi
xcrun simctl list devices available --json | python3 -c '
import json, sys
device_id = sys.argv[1]
matches = [(runtime, d) for runtime, devices in json.load(sys.stdin)["devices"].items()
           for d in devices if d["udid"] == device_id and d.get("isAvailable", True)]
if len(matches) != 1 or ".iOS-" not in matches[0][0]:
    sys.exit("SIMULATOR_ID must name an available iOS simulator.")
print("Simulator: " + matches[0][1]["name"])
' "$SIMULATOR_ID" || fail 'Simulator validation failed.'
OUTPUT_DIR="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "${OUTPUT_DIR:-$REPO_DIR/output/jank-audits/smoke-$(date -u +%Y%m%dT%H%M%SZ)}")"
python3 -c 'import os,sys; os.makedirs(sys.argv[1], exist_ok=False)' "$OUTPUT_DIR" \
  || fail 'Output directory already exists or cannot be created; choose a new OUTPUT_DIR.'
BUILD_DIR="$OUTPUT_DIR/derived-data"
RESULT="$OUTPUT_DIR/smoke.xcresult"
printf 'Evidence: %s\nBuilding Drift Preview; details in build.log.\n' "$OUTPUT_DIR"
if ! xcodegen generate --spec "$REPO_DIR/drift-ios/project.yml" >"$OUTPUT_DIR/project.log" 2>&1; then
  fail "Project generation failed; see $OUTPUT_DIR/project.log"
fi
if ! xcodebuild -quiet -project "$REPO_DIR/drift-ios/Drift.xcodeproj" -scheme Drift \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -derivedDataPath "$BUILD_DIR" \
  -parallel-testing-enabled NO build-for-testing CODE_SIGNING_ALLOWED=NO \
  PRODUCT_BUNDLE_IDENTIFIER=com.drift.notes.preview APP_DISPLAY_NAME='Drift Preview' \
  >"$OUTPUT_DIR/build.log" 2>&1; then
  fail "Build failed; see $OUTPUT_DIR/build.log"
fi
XCTESTRUN="$(python3 - "$BUILD_DIR/Build/Products" <<'PY'
import plistlib, sys
from pathlib import Path
products = Path(sys.argv[1])
sources = list(products.glob("*.xctestrun"))
if len(sources) != 1:
    sys.exit("Expected exactly one generated xctestrun file.")
source = sources[0]
data = plistlib.loads(source.read_bytes())
if "TestConfigurations" in data:
    targets = [t for c in data["TestConfigurations"] for t in c.get("TestTargets", [])]
else:
    targets = [t for t in data.values() if isinstance(t, dict)]
ui_targets = [t for t in targets if t.get("BlueprintName") == "DriftUITests"]
if len(ui_targets) != 1 or not ui_targets[0].get("IsUITestBundle"):
    sys.exit("Expected exactly one DriftUITests UI test target.")
target = ui_targets[0]
app_path = Path(target.get("UITargetAppPath", "").replace("__TESTROOT__", str(products)))
info_path = app_path / "Info.plist"
if not info_path.is_file():
    sys.exit("Could not verify the UI test app's identity.")
info = plistlib.loads(info_path.read_bytes())
if info.get("CFBundleIdentifier") != "com.drift.notes.preview":
    sys.exit("Refusing to test an app other than the separate Drift Preview identity.")
target.update(PreferredScreenCaptureFormat="screenRecording",
              SystemAttachmentLifetime="keepAlways", UserAttachmentLifetime="keepAlways")
destination = source.with_name("Drift-observer-recordings.xctestrun")
with destination.open("xb") as output:
    plistlib.dump(data, output)
print(destination)
PY
)" || fail 'Could not prepare retained Preview recordings.'
printf 'Recording compose, writing/reopen, and search/navigation; details in tests.log.\n'
TEST_STATUS=0
xcodebuild -quiet test-without-building -xctestrun "$XCTESTRUN" \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -parallel-testing-enabled NO \
  -resultBundlePath "$RESULT" \
  -only-testing:DriftUITests/JankAuditUITests/testRepeatedBlankComposeAndReturnRecording \
  -only-testing:DriftUITests/JankAuditUITests/testNewlinesKeepShortPageSteadyRecording \
  -only-testing:DriftUITests/JankAuditUITests/testSearchCancelledBackAndKeyboardDismissalRecording \
  >"$OUTPUT_DIR/tests.log" 2>&1 || TEST_STATUS=$?
printf 'Functional test exit status: %s\nResult: %s\n' "$TEST_STATUS" "$RESULT"
REVIEW_STATUS=0
if [ "$RECORD_ONLY" -eq 0 ]; then
  python3 "$REPO_DIR/scripts/observe-ios.py" --xcresult "$RESULT" --output "$OUTPUT_DIR/observer" \
    --expect-test JankAuditUITests/testRepeatedBlankComposeAndReturnRecording \
    --expect-test JankAuditUITests/testNewlinesKeepShortPageSteadyRecording \
    --expect-test JankAuditUITests/testSearchCancelledBackAndKeyboardDismissalRecording \
    || REVIEW_STATUS=$?
fi
if [ "$TEST_STATUS" -ne 0 ]; then exit "$TEST_STATUS"; fi
exit "$REVIEW_STATUS"

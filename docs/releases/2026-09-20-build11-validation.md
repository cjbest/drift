# Drift iOS build 11 validation — September 20, 2026

Version: **0.2 (11)**. Bundle identifier: `best.christopher.drift`.
Production source: `efbc99c3e3fc9d52f81489f890d39a1fa71d4a54`.

Distribution status: Apple accepted the upload at **10:05:01 PDT**. At
**10:09:22 PDT**, the API verified build 11 as **IN_BETA_TESTING**, beta review
**APPROVED**, membership in **Public Beta**, matching testing notes, and
`autoNotifyEnabled = true`. Processing state was **VALID** and export compliance
reported no non-exempt encryption. The existing public invitation remains
<https://testflight.apple.com/join/YfEQ1TSH>.

App Store Connect build ID: `98dbc816-0acb-4139-90ab-d63434176b2c`.
Distribution was completed using the repository's App Store Connect API client
after Xcode's successful signed upload.

## Changes

- Keyboard color and page motion stay coordinated when composing; native Back
  and cancelled edge gestures remain available.
- Notebook rows are prepared before return, including after Search.
- Long-note focus, first keystrokes, and keyboard dismissal preserve the page
  and caret position. Formatting work is limited to affected paragraphs.
- Returning after deleting all text omits the transient empty row. Reversible
  presentation is separate from coordinated, conflict-safe file cleanup.
- Empty notebook and no-results messages have explicit responsive text widths.
  A TestFlight build 10 report reproduced as a 44-point text column on the
  candidate before this last fix; the same native regression passes afterward.
- The repository now contains the Jank Audit procedure, focused regressions,
  and five short design/build principles with a pruning rule.

## Validation

The earlier nine-fix candidate passed **29 focused hosted/layout tests** and
**two physical iPhone replay tests**, each containing three repeated routes.
The phone routes covered blank compose/type/delete/Back and editing in the
middle of a long note. Independent source-frame reviews and fixture-persistence
checks passed. The owner used the normal Release build and reported that it
felt good. Release packaging changes the build number; the later empty-state
fix is separately covered below.

The TestFlight feedback correction passed **two native layout tests**: three
empty-notebook/search cycles and 18 width, text-size, and content-state
combinations. The baseline screenshot reproduces the reported narrow column;
the corrected empty-notebook screenshot was inspected independently.

Additional release simulator checks passed three iPhone light routes covering
repeated type/delete/Back, a 1,001-note catalogue, and saved content across
backgrounding and relaunch. The iPad dark/larger-text run passed Search,
long-note editing, Read Mode, menu hydration, and three compose/return cycles.
Two navigation-helper assumptions were corrected; both focused reruns passed
on build 11 with the empty-state fix. All seven selected iPad cases have passing
results. A fresh native onboarding view at maximum text size was also visually checked;
this was not a new full-app onboarding session.

## Coverage and evidence

Physical evidence uses iPhone 16 Pro on iOS 26.6.2. The final physical jank replay
was dark appearance. Additional simulator evidence uses iOS 26.2. The new
empty-state regression covers widths of 320, 430, and 768 points and default
through maximum accessibility text size; it does not claim a physical iPad run.

The integrated Reduce Motion setup failed before the app route. Earlier actual
Reduce Motion evidence exists for the same editor implementation, with its
surrounding-source differences recorded. Physical iPad, the full appearance
and accessibility cross-product, fresh iCloud-provider/offline testing, and
native frame-pacing/latency measurements remain outside this release's verified
scope. No Mac build is changed or released.

Raw recordings, screenshots, result bundles, signing checks, and source hashes
remain local under `output/jank-audits/2026-09-19-fixes/` and
`output/jank-audits/2026-09-20-release/`. Raw evidence is intentionally ignored by
Git. Tests use disposable notes; the owner's live notebook is not a QA fixture.

## Distribution artifact

The export verified version/build/bundle identity, the personal team's Apple
Distribution signature, and `get-task-allow = false`. Test bundles and Debug
session overrides are excluded; the same dormant fixture environment hooks
present in build 10 remain. Production source hashes were unchanged across
archive/export.

- Personal signing team: `F486BUQ5G3`.
- Archive: `/tmp/drift-build11-final-release.xcarchive`.
- Export: `/tmp/drift-build11-testflight-export/Drift.ipa`.
- Exported IPA SHA-256: `6c4fe1ee3ab99f3f9539404d200855c0090e005b2d89832b9cd2195ffbacbebd`.
- Upload log: `/tmp/drift-build11-upload.log`.
- Artifact checks: `output/jank-audits/2026-09-20-release/artifact-check.json`.

A synthetic reuse test involving rapid size/trait/content changes can compress
the onboarding button. Fresh native onboarding rendered correctly; the synthetic
observation was not established as a real app route or a new regression. It is
retained in the local empty-state report rather than reported as a clean pass.

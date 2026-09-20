# Drift iOS build 12 hotfix validation — September 20, 2026

Version: **0.2 (12)**. Bundle identifier: `best.christopher.drift`.
Production source: `5d12bbe7002907ef11e267d6d6f02e920b6fb95b`.

Distribution status: Apple accepted the upload at **11:00:32 PDT**;
at **11:03:59 PDT**, the API verified **VALID**, **IN_BETA_TESTING**, beta review
**APPROVED**, membership in **Public Beta**, matching testing notes, and
`autoNotifyEnabled = true`. Export compliance reports no non-exempt encryption.
The existing public invitation remains active:
<https://testflight.apple.com/join/YfEQ1TSH>.

App Store Connect build ID: `0bd71e07-5db8-4192-bc36-9aef1165a53a`.
Distribution was completed using the repository's App Store Connect API client
after Xcode's signed upload. The specific group membership, build state,
review approval, and saved testing notes were verified separately.

## Change

Fixes the note jumping upward when Return creates an empty final line, including
after the title, ordinary body lines, and blank lines. TextKit 1 was asking to
reveal a rectangle that included the notebook's extra blank paper: the measured
first-Return request was 909 points tall and moved the page 451 points upward.
The fix removes only that excess from the native reveal request. Normal scrolling
when the caret reaches the keyboard and the extra reading space remain intact.

This is a 19-line production change. New hosted and UI regressions cover the
missing newline sequence, and the release Jank Audit explicitly includes it.
No Mac build is changed or released.

## Validation completed before release preparation

- Reproduced the reported jump in the supplied physical iPhone recording,
  a separate simulator preview, and a failing hosted native regression.
- All six focused editor/focus tests passed. Two extended tests also passed
  after adding middle-body Return and actual scrolling at the keyboard edge.
- Three repeated short/wrapped/short-title traces held scroll offset at exactly
  zero and title position at exactly 129 points across 294 displayed-frame
  samples. Each sequence includes title/body/blank Return, deleting and retyping
  Return, immediate typing, and splitting a populated body paragraph.
- Three iPhone UI checks passed: three complete software-keyboard newline and
  save/reopen sequences, long-note editing and persistence, and short-note
  scrolling with the Back control retreating and returning.
- The normal app was installed over the existing app on the owner's iPhone 16
  Pro running iOS 26.6.2. After trying it, the owner reported **“Much improved”**
  and authorized this hotfix. This is user-reported physical validation;
  the fixed physical interaction was not separately recorded by the agent.

## Additional release coverage

- Four dark iPhone simulator routes passed: deep Search and keyboard return,
  normal compose/return, real system Reduce Motion compose/return, and an
  attempted edge-back with editing, keyboard dismissal, and saved-note reopening.
  Key routes include three repetitions. Reduce Motion and appearance were restored.
- Six focused hosted tests and the three-cycle newline UI route passed on the
  iPad mini (A17 Pro) simulator. The UI route used dark appearance, accessibility
  extra-large text, and a visible software keyboard; the hosted layout tests
  used the standard large text category. Original settings were restored.
- The preceding build 11 release audit, completed the same morning, supplies
  unchanged-route evidence for 1,001-note loading, background/relaunch,
  menu hydration, Read Mode, and empty-note removal. Its scope and limitations
  remain in [the build 11 record](2026-09-20-build11-validation.md); those results
  are not relabeled as new build 12 runs.

No new material jank was observed in the inspected scope. iPad source-frame
review covers all three newline sequences, and the dark iPhone review covers
309 source frames across selected keyboard and navigation transitions. The
short edge gesture did not visibly begin navigation, so this run establishes
state preservation after the gesture but does not verify cancelled-Back motion.

Recording review uses whole-clip overviews and source frames rather than
normal-speed playback. The tests and recordings establish bounded functional
and visual continuity evidence, not physical frame pacing or input latency.
Physical iPad, fresh iCloud-provider/offline testing, and the full appearance
and accessibility cross-product remain outside this hotfix's verified scope.

## Distribution artifact

- Archive: `/tmp/drift-build12-release.xcarchive`.
- Personal signing team: `F486BUQ5G3`.
- Source hashes matched before and after archive/export.
- Local export: `/tmp/drift-build12-testflight-export/Drift.ipa`.
- Local export SHA-256: `b43273f930a4c6d26180493b23e3e667e4ed8e982b480af015f734c0591fa1a7`.
- Distribution signature verified; `get-task-allow = false`; no test bundles or
  Markdown fixtures are included. The dormant fixture environment hooks are
  unchanged from build 11. Build/version/bundle and iPhone/iPad family match.
- Uploader dry run passed. Support and privacy pages returned HTTP 200.
- Upload log: `/tmp/drift-build12-upload.log`.

The local export is a packaging validation artifact; the upload helper exports
from the same signed archive for upload. Raw recordings, screenshots, native
traces, result summaries, source hashes, and artifact checks remain local under
`output/title-return-audit/` and the hotfix Jank Audit folders. Synthetic notes
were used for scripted tests; the owner's notebook was not a QA fixture.

Additional local reports:

- `output/jank-audits/2026-09-20-hotfix12/iphone-neighbors/REPORT.md`
- `output/jank-audits/2026-09-20-hotfix-ipad/report.md`

# Selection and scrolling release validation — September 26, 2026

Release scope: Mac 0.2.3 and iPhone/iPad 0.2 build 13. Public distribution remains
an Apple Silicon Mac download and the existing iOS Public Beta in TestFlight.

## Source and signing

- Mac source: `fea6482af7dc41cec44de22831dd5272d3334ceb`.
- iOS archive source: `12fd808ba665e7ba4b1f6001bcfb1e8e841fea6a`. The later
  commit changes only Mac behavior, its tests, and documentation.
- Personal Apple team: `F486BUQ5G3`; Developer ID on Mac and Apple Distribution
  on iOS. Normal production bundle identities and notebook locations are retained.
- iOS archive executable SHA-256:
  `5ee225d327d67e01b5b65083724f556ae96c1543cd7e04dd594673eb3211076e`.
  Signature, provisioning, device families, minimum OS, and matching dSYM checked.

## Mac

[Mac 0.2.3 is published](https://github.com/cjbest/drift/releases/tag/v0.2.3)
at tag `v0.2.3`, which resolves to the tested Mac source commit above. The
hosted DMG and checksum file were downloaded without credentials. The digest,
signature, stapled ticket, installer Gatekeeper assessment, and mounted-app
Gatekeeper assessment all passed independently. The mounted app reports 0.2.3,
`com.drift.app`, arm64, macOS 14.0 minimum, and personal team `F486BUQ5G3`.
The read-only verification volume was detached after the checks. This does
not replace the unavailable fresh-account installation scenario noted below.

The final artifact was signed and notarized under submission
`8b12e9aa-e3e4-4a64-b3fe-f8ac5a7be001` (`Accepted`), stapled, and validated.
Both the installer and its mounted app passed Gatekeeper as Notarized Developer ID.
Final stapled installer SHA-256:
`d63bb8a7337178dd0408dbf2e5705faa5f0d0613f6ed971e05de96d87d3cbdea`.

A native walkthrough discovered that immediate typing or paste after New Note
could enter the previous document while its save was pending. The earlier
candidate was rejected. The final source assigns the editor to the new document
synchronously and retains background drafts for Retry, Close, and Quit.

The deterministic regressions failed in Chromium and WebKit before the fix and
passed afterward. They cover immediate writing, repeated new notes, failed
background saves, Retry, and closing/quitting with an offscreen unsaved draft.
The final full browser suite passed 200/200 across Chromium and WebKit, with no
retries, skips, or failures. Native filesystem tests passed 39/39; editor/session
tests passed 9/9. The frontend type check and production build passed.

The signed native Preview replay passed on the final source: a dirty previous
note followed by one New Note and immediate paste produced the intended new
file, preserving only the prior note's own edit. Three rapid New Note/paste
cycles produced three distinct exact files without waiting for editor readiness.
All five inspected fixture files matched their expected bytes. Native checklist
toggle/Undo, link editing/restoration, repeated quick-open/Escape, retained
long-note position, and 21,480-character whole-note copying after three scroll
and reversal cycles passed. A new window saved its exact text when closed
immediately after paste. Native Window → Zoom retained the distant Find passage;
a separate accessibility-tool Zoom action was inconclusive and is not counted
as application validation. The final ordinary Quit/relaunch check remained
unavailable after repeated native-automation timeouts; it is not reported as
passed. Automated close/quit failure-and-recovery checks and the native
immediate window-close save check did pass.

## iPhone and iPad

Build `98d7f54d-dcc1-461f-b605-d200e5f4eece` (0.2 build 13) was uploaded,
processed as `VALID`, and approved for beta testing. Exact membership in Public
Beta (`f9e45cce-770d-4518-b8fb-60a3eb0e51b5`) and external state `IN_BETA_TESTING`
were verified; testing notes are set and automatic tester notification is enabled.
The [existing invitation](https://testflight.apple.com/join/YfEQ1TSH) remains active.

Hosted suite: 118/118 passed with no skipped tests. Recorded iPhone smoke:
3/3 passed; independent source-frame review covered 808 frames across 11 windows
without finding a new release-material issue. Dark review covered 1,976 encoded
frames in bounded transitions; final accessibility/Reduce Motion/iPad review
covered another 445. All corresponding whole-clip overviews were inspected.
The two open visual findings are recorded below. The additional dark iPhone batch
passed 7/7, including long-press selection and keyboard end-scroll. Increased-text
writing passed 2/2; an actual Reduce Motion toggle plus three compose/back cycles
passed 1/1; iPad landscape/dark/accessibility-text routes passed 3/3. In total,
16 distinct release UI routes passed with zero skips in their passing batches.
Settings navigation failed at accessibility-extra-large text; one retry at
standard large text passed the Reduce Motion route. This was a test setup
failure, not a product failure; the original Settings navigation was not repaired.

The keyboard scroll-limit regression was checked with short and long notes:
maximum scroll offsets were unchanged across keyboard visibility. Prior native
drag traces confirmed that keyboard movement changes the viewport, not document
length. Standard UIKit selection and spelling menus remain in use.

## Open findings and coverage limits

A partial keyboard-dismissal snap was also reproduced before the scroll-limit
fix. It remains an open finding, disclosed before the requested release.
Same-touch gesture reversal on a physical device is unverified.

A dark-mode type/delete/Back recording showed a transient Untitled row in one
of three cycles. It was visible from roughly 20.477–20.828 seconds, then removed
with upward list movement through 21.088 seconds. The notebook settled correctly
and no data-loss symptom was observed. This is a noticeable open polish issue,
not a claimed fix. Its save/cleanup implementation is unchanged in this release;
without a prior-build replay, regression attribution remains unknown. It was
judged non-blocking for this selection and scrolling release.

Fresh-account or second-Mac installation, macOS 14 and iOS 17 specifically, and physical
iCloud synchronization, offline reconnection, and concurrent provider edits
were unavailable. Browser notebook APIs are mocked. Source-frame review does
not establish perceived whole-clip smoothness, display frame rate, or physical
input latency. Simulator evidence is not physical iPhone/iPad evidence. The condition matrix
is bounded rather than a full combination of every route and setting; iPad
Reduce Motion and automatic appearance scheduling were not exercised. Both
dedicated simulators and modified settings were restored after testing.

QA used disposable iOS data and synthetic notes in the separate Mac Preview
copied notebook. The user's main Mac application remained running during checks;
its installed binary and notebook configuration were preserved. Private copied
notebook recordings and raw fixture content are kept locally, outside public
release assets.

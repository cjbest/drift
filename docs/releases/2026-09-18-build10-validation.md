# Drift iOS build 10 validation — September 18, 2026

Version: **0.2 (10)**. Bundle identifier: `best.christopher.drift`.
Production source: `c0b6feea53f0392b0d3be670320feb18d069c8da`.

Distribution status: Apple accepted the build 10 upload at **23:20:11 PDT**.
After processing, version **0.2 (10)** was added to the existing **Public Beta**
group with **Automatically notify testers** enabled and its test notes saved.
The group's build list was verified as **Testing**, expiring in 90 days, at
approximately **23:23 PDT**. Build 9 was a development sideload; build 8 is the
preceding distributed TestFlight build.

App Store Connect build ID: `9493e6b3-e725-43da-92aa-773b3901edb3`.
The public invitation remains <https://testflight.apple.com/join/YfEQ1TSH>.

## Changes since TestFlight build 8

- Returning launches restore a durable local list index before waiting for
  iCloud. Directory-slash and `/var` aliases share cache identities; legacy
  caches remain readable. The index survives purged or failed full-text caches,
  and an older text snapshot cannot replace newer list membership or metadata.
- On Launch applies on cold launch and after at least five minutes fully in the
  background: Notes List (default), Open Last, or New Note. Brief returns retain
  the editor and reading position; inactive-only interruptions do not reset the
  session.
- Long-pressing the Home Screen icon offers **New Note** on cold and warm
  launches. The request overrides the launch preference, reaches only its
  intended scene, and survives first-use folder selection. Navigation first
  preserves the current editor's local recovery journal. An empty composer is
  reused without creating a blank file.
- Notebook Options and its On Launch submenu remain open while previews arrive.
  Reopening resolves current launch checkmarks, folder actions, and Undo state.

## Validation completed

- **87/87 unit/layout tests passed**, with no failures or skips. Coverage includes
  cache persistence and recovery, URL boundaries, editor preservation, session
  timing, and exactly-once, scene-specific shortcut consumption.
- **Nine distinct launch/resume UI scenarios passed** with synthetic notebooks:
  eight in the main run, then the Control Center scenario in a focused rerun
  after correcting the automation assertions. These cover all launch preferences,
  brief returns preserving cursor/reading position, inactive interruptions,
  cold/warm Home Screen actions, draft preservation, empty-composer reuse, and
  the 1,000-note cached-launch regression.
- **Three menu UI regressions passed** in the final run: the main menu and launch
  submenu stay open during hydration, and reopening updates Undo availability.
  An earlier Undo assertion was corrected to inspect the visible empty state
  and synthetic file after UIKit retained a deleted preview in accessibility.
- Source review found no release blocker. Simulator fixture persistence and the
  shortened test resume interval are compiled only for Debug simulator builds.
  Release retains the five-minute interval and excludes diagnostic recording.
- Release export checks verified version/build/bundle identity, a valid personal
  team distribution signature, `get-task-allow = false`, exclusion of test
  harnesses, and unchanged production source across archive/export.

## Physical phone and privacy

Build 9's phone diagnostics showed the index loaded before the first notebook
frame, no spinner, and bookmark restoration after the list appeared. The first
notebook frame was recorded **130 ms after app initialization**, excluding OS
launch time. The user confirmed that launch speed was much better. Only timing,
count, and boolean diagnostics were retrieved; no note text, filenames, folder
paths, or bookmarks were collected.

The signed normal Drift build 10 was subsequently installed on the phone and its
version verified without opening or inspecting the live notebook. No separate
build 10 phone behavior feedback has been recorded here. Automated scenarios
used disposable notebooks; actual notes were not read, modified, copied, or
shared for these checks. Simulator coverage is not a claim of an end-to-end
physical-device launch time or a physical-device iCloud/offline test for build 10.

## Evidence and distribution artifacts

- Unit/layout result: `/tmp/drift-resume-units-rerun.xcresult`
- Launch/resume results: `/tmp/drift-resume-ui.xcresult` and
  `/tmp/drift-resume-control-center-final.xcresult`
- Final menu result: `/tmp/drift-menu-final.xcresult`
- Release archive: `/tmp/drift-build10-release.xcarchive`
- Archive log: `/tmp/drift-build10-release-archive.log`
- Distribution export: `/tmp/drift-build10-testflight-export/Drift.ipa`
- Export log: `/tmp/drift-build10-export.log`
- Successful upload log: `/tmp/drift-build10-upload.log`
- Verified live group: [Public Beta builds](https://appstoreconnect.apple.com/teams/89200b61-2cf7-4779-b73a-b7f915db50ad/apps/6809245122/testflight/groups/f9e45cce-770d-4518-b8fb-60a3eb0e51b5/builds)
- Artifact checks: `/tmp/drift-build10-artifact-check.json`
- Source fingerprints: `/tmp/drift-build10-source-hashes.json`
- Signing team: `F486BUQ5G3`
- IPA SHA-256: `679dbfd52105c6035235d79aca9024287bffc40058ad220eabe807f8b812c063`

# Drift release validation — September 18, 2026

Mac source: `38f8ca625a77b876868a84a2266c33bc32685eaf`.
iOS source: `e5a84701af7133bf4aadcba655c85b10c19ec8ee` — version 0.2 (8). Build 7 was superseded before distribution to add device-appropriate folder selection on iPad.

## Checks completed

- iOS: 85/85 simulator tests passed, no failures or skips (66 unit/layout, 19 UI). Includes first-use Browse guide, pin/unpin persistence, launch choices, large-notebook relaunch, search, editing, and navigation.
- Mac: 39 Rust tests, 9 TypeScript tests, 162 Chromium/WebKit cases passed. Production dependency audit reported zero vulnerabilities.
- Physical phone and native Mac QA apps used a newly created, explicitly selected synthetic iCloud folder. Phone read Mac seed, wrote/pinned a note, Mac renamed and edited it, phone read the rename and edited again, and Mac received the return edit. The `.pinned.md` marker survived throughout.
- Physical cached index restored two synthetic notes in about 0.8 ms; notebook controller layout took about 16 ms. These are internal store/layout measurements, not total cold-launch-to-first-frame timings.
- iOS build 8 archive, distribution export, and upload passed under the personal Apple team. Exported app is version 0.2 build 8, distribution signed, get-task-allow false. IPA contains no QA harness/test fixtures.
- Mac release notarization accepted, signature/staple/Gatekeeper checks passed. Hosted DMG was downloaded and verified again, including the mounted contained app.
- Mac v0.2.2 published; live website now links the release and retains the existing public TestFlight invitation.

## Scope and limits

- Actual user notes were not read, modified, copied, or shared. Production installed apps and their saved folders were not used for synthetic tests.
- Phone UI test runner could not enable automation; the user granted the separate QA app access to the exact synthetic folder manually. The round trip exercised production storage code on that phone and the native Mac UI. Simulator UI tests passed separately.
- A temporary measurement harness initially omitted the navigation container and crashed; corrected to use the app's normal navigation hierarchy, then passed. No production source changes were required.
- No physical offline-network toggle was performed. Cache/recovery and conflict protections were exercised with synthetic automated tests. No macOS 14 hardware or fresh-user-account launch test was available.
- The final iPad check found that its picker has a Locations sidebar instead of the phone Browse tab. Build 8 skips the extra phone-specific guide on iPad. Focused iPhone and iPad checks both passed on build 8 in dark mode with accessibility-extra-large text; final screenshots were visually checked. The full 85-test suite preceded this narrow fix.
- Apple accepted the build 8 upload at 21:58 PDT. Build 8 was submitted to the existing Public Beta group with automatic tester notification enabled, then verified as **Testing** in that group at approximately 22:03 PDT. The public invitation remains https://testflight.apple.com/join/YfEQ1TSH. Build 7 remains unassigned to tester groups and was not released.

## Evidence

- iOS result: `/tmp/drift-final-simulator-qa.xcresult`; focused `/tmp/drift-final-ipad-guide-fixed.xcresult` and `/tmp/drift-final-iphone-guide-accessibility.xcresult`
- Physical reports: `/tmp/drift-physical-qa/qa-write.json`, `qa-verify.json`, `qa-cache.json`
- iOS upload log: `/tmp/drift-testflight-build8-upload.log`
- Mac detailed record: `/tmp/drift-mac-0.2.2-validation.md`
- Mac release: https://github.com/cjbest/drift/releases/tag/v0.2.2
- DMG SHA256: `728da99029d9aa4adea78c71c1ed53d09c3477465c739c5f329189475c4e14c0`

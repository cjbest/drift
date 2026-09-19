# iPhone release copy

Release copy for Drift 0.2 (8). The copy below is not evidence of an uploaded
or approved build.

The first public TestFlight beta is live. Build **0.2 (6)** was verified as
**Approved** in App Store Connect on September 16, 2026. The Public Beta
group's invitation was enabled and verified the same day:
<https://testflight.apple.com/join/YfEQ1TSH>.

## App information

- Name: **Drift — Markdown Notes**
- Apple app ID: `6809245122`
- Bundle ID: `best.christopher.drift`, registered under the owner's personal
  membership. The on-device display name remains **Drift**.
- Subtitle: **A quiet place for your notes**
- Primary category: **Productivity**
- Support URL: <https://github.com/cjbest/drift/blob/main/docs/SUPPORT.md>
- Privacy policy URL: <https://github.com/cjbest/drift/blob/main/docs/PRIVACY.md>
- Marketing URL: <https://drift.christopher.best/>
- Keywords: `markdown,notes,notebook,writing,checklist,plain text,icloud`

Confirm the review-contact details before submitting. Keep the app free for the initial TestFlight beta.
Public App Store pricing, territories, and seller details need to be set before
the later store release.

## Description

The Markdown editor I always wanted for my personal notes.

Drift is a quiet place to write, with beautiful type and almost nothing between
you and your notes. Notes are plain Markdown files, named from their contents
and saved automatically.

Choose a folder, then start writing. Search across your whole notebook, make
checklists, and write in light or dark mode. Pull down in a note for
a clean reading view.

Use a folder in iCloud Drive to keep the same notes available in Drift on your
Mac, iPhone, and iPad. Your files remain yours to open in other apps.

No Drift account. No ads. Nothing you don't want.

## TestFlight: what to test

This build adds pins, opening preferences, and faster cached startup.

- Long-press a note to pin or unpin it. Pins travel with the Markdown filename;
  use Drift 0.2.2 or later on Mac to preserve them when editing there.
- In Notebook Options → On Launch, choose Notes List, Open Last, or New Note.
- Double-tap the empty space below your notes to start a new one.
- Returning launches show your locally cached list while the shared folder
  reconnects.
- A visual guide helps you find Browse when choosing an iCloud Drive folder.

Try choosing the same disposable iCloud Drive folder on iPhone and Mac, then
write, pin, rename, and reopen a test note on each. Try reopening the app with
a previously used folder while offline, then reconnect and check your changes.

Please report anything that feels slow, moves unexpectedly, or does not save
as you expect. Include your device and the steps that led to the problem.
Feedback screenshots may contain note text; check them before sending.

## Review instructions

Drift does not require a login or a paid account.

1. On first launch, tap **Choose Shared Folder**. On iPhone, tap **Continue** in
   the illustrated guide.
2. In the system Files picker, use **Browse** on iPhone or the **Locations**
   sidebar on iPad, then choose or create an empty folder in **On My
   iPhone/iPad** or **iCloud Drive**. A local folder is sufficient to review the
   app; iCloud is optional.
3. Tap **+** to create a note. The first nonempty line becomes its title. Type some text,
   then go back to the notebook; writing saves automatically.
4. Search for text in the note and open the result.
5. The notebook's options menu includes folder selection, the privacy policy,
   and support. Appearance follows the device's light/dark setting. Pull down
   in an open note to toggle Read Mode.

The app accesses only the folder selected through Apple's document picker.
It has no account, subscription, Drift-hosted service, or demo credentials.

## Submission checks

- Publish and verify the support and privacy URLs before uploading.
- Use the verified personal Apple team for the app record, App ID, profile,
  certificates, archive, and export. Never use the company team previously used
  for development.
- Confirm the app record's bundle ID before signing; keep it stable afterward.
- Use a new build number for every uploaded archive.
- Answer Apple's privacy, age-rating, content-rights, and export-compliance
  questions against the exact release build. Drift has no app-owned analytics
  or custom encryption. TestFlight diagnostics are handled by Apple.
- For external TestFlight, complete the beta description, feedback email,
  review contact, and reviewer notes, then submit to beta review.
- Create an internal TestFlight group before the external group. Upload for
  App Store Connect; do not restrict the build to “TestFlight Internal Only.”
- For a permanent App Store release, prepare separate full-resolution iPhone
  and iPad screenshots from the release build. The README's two-phone image
  is promotional artwork, not a store screenshot set.

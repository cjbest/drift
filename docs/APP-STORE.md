# iPhone release copy

Build **0.2 (11)** is live in the **Public Beta** group. Apple's API confirmed
**IN_BETA_TESTING** and **APPROVED** on September 20, 2026 at **10:09 PDT**, with
automatic tester notification enabled. Group membership and the saved testing
notes were verified separately. The public invitation remains active:
<https://testflight.apple.com/join/YfEQ1TSH>.

The Mac release remains **0.2.2**. Build 11 improves keyboard, editor, and
notebook transitions and fixes the narrow empty-state text reported in build 10.
See [the build 11 validation record](releases/2026-09-20-build11-validation.md)
for exact coverage and limitations; [build 10's record](releases/2026-09-18-build10-validation.md)
contains the preceding launch and menu work.

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

This update makes writing and moving around your notebook feel smoother.

- The keyboard and page arrive together when you start a note.
- Returning to the notebook keeps rows steady, including after Search.
- Editing a long note keeps your place as the keyboard opens and closes.
- Deleting all the text and returning avoids a temporary empty row.
- Empty notebook and search messages use readable spacing instead of wrapping
  into a narrow column.

Try creating a note, typing immediately, and going back. Open a long note and
edit near the middle and end; dismiss the keyboard and resume writing. Try
Search, a cancelled swipe back, and both light and dark appearance. Check that
your writing is saved when you return or reopen the app.

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

- Run the iPhone/iPad [Jank Audit](JANK-AUDIT.md) on the candidate build, including
  physical-device keyboard and gesture evidence. Report open findings and any
  unavailable coverage; simulator tests alone do not establish smoothness.
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

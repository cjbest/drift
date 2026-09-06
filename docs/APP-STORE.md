# iPhone release copy

Prepared for the first public TestFlight beta. These are proposed App Store
Connect field values, not a record of an uploaded or approved build.

## App information

- Name: **Drift** (check availability in the personal developer account).
- Subtitle: **A quiet place for your notes**
- Primary category: **Productivity**
- Support URL: <https://github.com/cjbest/drift/blob/main/docs/SUPPORT.md>
- Privacy policy URL: <https://github.com/cjbest/drift/blob/main/docs/PRIVACY.md>
- Marketing URL: <https://github.com/cjbest/drift>
- Keywords: `markdown,notes,notebook,writing,checklist,plain text,icloud`

Confirm the personal account's bundle identifier and review-contact details
before creating the record. Keep the app free for the initial TestFlight beta.
Public App Store pricing, territories, and seller details need to be set before
the later store release.

## Description

The Markdown editor I always wanted for my personal notes.

Drift is a quiet place to write, with beautiful type and almost nothing between
you and your notes. Notes are plain Markdown files, named from their contents
and saved automatically.

Choose a folder, then start writing. Search across your whole notebook, make
checklists, and switch between light and dark mode. Pull down in a note for
a clean reading view.

Use a folder in iCloud Drive to keep the same notes available in Drift on your
Mac, iPhone, and iPad. Your files remain yours to open in other apps.

No Drift account. No ads. Nothing you don't want.

## TestFlight: what to test

Welcome to Drift's first public beta.

Try choosing a notes folder, writing and reopening a note, making a checklist,
and searching your notebook. If you also use Drift on Mac, choose the same
iCloud Drive folder on both devices and try editing a note on each.

Please report anything that feels slow, moves unexpectedly, or does not save
as you expect. Include your device and the steps that led to the problem.
Feedback screenshots may contain note text; check them before sending.

## Review instructions

Drift does not require a login or a paid account.

1. On first launch, tap **Choose Folder**.
2. In the system Files picker, choose or create an empty folder in **On My
   iPhone/iPad** or **iCloud Drive**. A local folder is sufficient to review the
   app; iCloud is optional.
3. Tap **+** to create a note. The first line becomes its title. Type some text,
   then go back to the notebook; writing saves automatically.
4. Search for text in the note and open the result.
5. The notebook's options menu includes folder selection, the privacy policy,
   and support. Appearance follows the device's light/dark setting. Pull down
   in an open note to toggle Read Mode.

The app accesses only the folder selected through Apple's document picker.
It has no account, subscription, external service, or demo credentials.

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
- For a permanent App Store release, prepare separate full-resolution iPhone
  and iPad screenshots from the release build. The README's two-phone image
  is promotional artwork, not a store screenshot set.

# Drift for iPhone and iPad

A native notebook for your plain Markdown files. Choose a folder once. To share
notes with the Mac app, choose the same folder in iCloud Drive on both devices.

This is the main Drift iOS app, built around UIKit navigation and text editing.
The normal `Drift` target uses `best.christopher.drift` for the public app. It
installs separately from the older `com.drift.notes` development app. To use
existing notes, choose the same external Markdown folder in the new app; folder
permissions, settings, and local recovery drafts do not transfer between apps.
Keep the old app installed until any pending writing has saved and the notes
open correctly in the new app. The interface stays compact: search and compose
above the list, and almost nothing but the text inside a note.

- Full-text search with matching excerpts; results open at the matching passage.
- Indexed notes open from their cached text and check for updates after the
  opening animation. Folder scans run separately from document reads and saves.
- Startup restores a local catalogue, then checks the folder in the background.
  Returning launches show a small local list snapshot before restoring folder
  access; the list never waits for iCloud. Cached notes open from their saved
  text while the provider reconnects, with recovery drafts taking precedence.
  A first scan shows filenames and dates before reading every note's contents.
  Previews appear in place without changing row heights or scroll position.
- The composer stays temporary until there is meaningful writing. Opening a
  blank page and going back creates no note or trash entry.
- Native back navigation, selection, undo, dictation, and keyboard avoidance.
- A readable editor with Dynamic Type, compact spacing, and a floating Back
  control that moves away as you scroll. Pull beyond the top of the page to
  enter or leave Read Mode. Drag down to dismiss the keyboard.
- Floating home controls, immediate row feedback, remembered editing positions,
  and native sharing from a note's context menu.
- Long-press a note to pin or unpin it. Pins stay at the top without extra row
  controls, and sync through the filename on both iPhone and Mac.
- Double-tap empty space below the list to start a note.
- **Notebook Options > On Launch** selects **Notes List** (default), **Open Last**,
  or **New Note**. Open Last restores the note's cursor, scroll position, and
  reading/editing state; New Note stays unsaved until you write something.
- Serialized autosave, local recovery drafts, explicit save failures, and
  preservation of both versions when another app changes an open note.
- Reversible deletion. Use **Notebook Options > Undo Last Delete** to recover
  the most recently deleted note. Repeating this restores older deletions.

## Build

For an agent-led installation on a device, follow the
[installation guide](../docs/INSTALL.md#iphone-and-ipad), including the user's
own signing team. Run the commands below from the repository root.

Requires Xcode and XcodeGen (`brew install xcodegen`).

```sh
xcodegen generate --spec drift-ios/project.yml
open drift-ios/Drift.xcodeproj
```

Select the `Drift` scheme and your simulator or connected device. Device builds
need your Apple development signing configuration. The deployment target is iOS 17.

No signing team is checked into the project. For distribution, select the
verified personal Apple team and its matching App ID and provisioning profile.
The release declares `ITSAppUsesNonExemptEncryption = false`: Drift uses
CryptoKit's SHA-256 only to derive local cache and recovery filenames, with no
custom encryption or networking library. Reassess that declaration if the
app's cryptographic functionality changes.

For a separate simulator preview with disposable example notes:

```sh
./scripts/preview-ios.sh
```

The preview uses `com.drift.notes.preview`, so it does not replace the regular
app. Set `SIMULATOR_ID` to an available simulator UUID on another machine.

## Test

```sh
xcodebuild -project drift-ios/Drift.xcodeproj -scheme Drift \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test CODE_SIGNING_ALLOWED=NO
```

The interaction reference in [DESIGN.md](DESIGN.md) records the original
app's intentional details and the criteria for the rebuild.

Unit tests exercise conflicts, missing files, empty saves, rename collisions,
recovery during overlapping saves, reversible deletion, full-text search,
list editing, and native undo. UI tests exercise actual typing, immediate back
navigation, pull-to-read, disappearing controls, search/cancel, keyboard layout,
and background/relaunch persistence.

`DRIFT_TEST_FOLDER=/path/to/disposable/notes` bypasses the folder picker in test
launches. `__APP_TEMP__` uses an app-local temporary folder; combine it with
`DRIFT_RESET_TEST_FOLDER=1` for a fresh folder. These overrides are for testing.

## How the files work

In the folder chooser, navigate back to **Locations**, then **iCloud Drive →
Documents → Drift** if the Mac uses its default notebook and syncs Desktop &
Documents. **On My iPhone → Drift** is a separate local folder. Another iCloud
Drive folder works too: select that same folder in the Mac's File → Change Folder
menu. The iOS folder picker grants access; no app-owned iCloud container is used.

Every note remains a UTF-8 `.md` file. The first nonempty line supplies its title.
Title edits rename a file; body edits retain collision suffixes. Reads and writes
use file coordination away from the main actor. Unchanged notes reuse a metadata
cache during refresh. A purgeable local catalogue keeps known titles, previews,
and text available between launches; saves still compare the retained baseline
with the provider's current text before replacing anything. The folder refreshes
when the app becomes active and on pull-to-refresh; an open, unedited note also
checks for external updates on resume.

Local recovery drafts live in Application Support and are independent of provider
writes. They are removed after successful saves. A conflicting edit is saved as
a separate `Recovered` copy, preserving the external file. Deleted files and their
restore metadata live in a hidden `.drift-trash` subfolder of the selected folder.
Meaningful writing in a new composer is recoverable even before its first shared
file exists; blank and whitespace-only composers do not create recovery entries.

Pinned files end in `.pinned.md`, for example `Shopping.pinned.md`. Pinning changes
the filename without rewriting the Markdown. Title changes, conflict copies, and
Undo retain the marker. Both apps hide it in fallback titles and use it to order
the unfiltered list. A literal title ending in `.pinned` gets a numeric suffix when
unpinned so it cannot accidentally become a pin. As with other external renames,
pinning on one device while editing the old filename on another can produce a
recovered copy; the existing conflict safeguards preserve both versions.

iCloud transport is provided by the folder. Changes to file-provider behavior
need real-device validation as well as simulator tests.

# Drift for iPhone and iPad

A native notebook for your plain Markdown files. Choose a folder once, including
`iCloud Drive > Documents > Drift` to use the same files as the Mac app.

This is the main Drift iOS app, built around UIKit navigation and text editing.
The normal `Drift` target updates the existing `com.drift.notes` installation
and keeps its selected folder. The interface stays compact: search and compose
above the list, and almost nothing but the text inside a note.

- Full-text search with matching excerpts; results open at the matching passage.
- Indexed notes open from their cached text and check for updates after the
  opening animation. Folder scans run separately from document reads and saves.
- Startup restores a local catalogue, then checks the folder in the background.
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
- Serialized autosave, local recovery drafts, explicit save failures, and
  preservation of both versions when another app changes an open note.
- Reversible deletion. Use **Notebook Options > Undo Last Delete** to recover
  the most recently deleted note. Repeating this restores older deletions.

## Build

Requires Xcode and XcodeGen (`brew install xcodegen`).

```sh
xcodegen generate --spec drift-ios/project.yml
open drift-ios/Drift.xcodeproj
```

Select the `Drift` scheme and your simulator or connected device. Device builds
need your Apple development signing configuration. The deployment target is iOS 17.

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

iCloud transport is provided by the folder. Changes to file-provider behavior
need real-device validation as well as simulator tests.

# Desktop notebook reference

September 5–6, 2026. Original desktop reference: `2561c28` (desktop code last
changed at `d6bed39`). New implementation: branch `codex/desktop-rebuild`.

## What belongs to Drift

One note fills one window. There is no sidebar, dashboard, permanent saving
indicator, or formatting toolbar. Cmd+P briefly brings the notebook into view;
Escape returns immediately to writing. Cmd+N starts an unsaved page. The first
line is the title, inside the same document. File names follow meaningful title
changes, without churn when two notes have the same title.

Keep the monospaced body, comfortable line height, centered wide-window page,
hanging bullets and checklists, native editing keys, and space beyond the final
line. A subdued title appears in the window bar after the heading scrolls out.
Cmd+drag moves the window; Cmd+click follows links. Links must win over dragging.
The title receives a restrained Newsreader italic treatment; paper, ink, and
selection use the warm sepia palette. Both light and dark appearances work.

The original was used live: quick-open, note opening, a disposable long writing
fixture, heading and list layout, scrolling, and in-note search. The supporting
history includes `29fa32f`, `816d281`, `7be1795`, `d3dab61`, `168995b`, `05d9ae0`,
`ff3efdc`, `d6bed39`, and `7de7944`. The original fixture was removed from the real
notebook before development continued. No work-note editing was part of testing.

## Rebuilt foundations

- Separate document sessions, serialized writes, and document-specific undo.
  A save acknowledges only its own snapshot; typing during a write remains dirty.
- Synchronous browser recovery on edits, disk recovery before writing, atomic
  replacement, and independent saved history for incoming and previous versions.
- macOS file coordination for replacement, with blocking I/O off the UI/runtime
  executor. Mismatched or missing baselines produce a separate conflict note.
- Close and Quit wait for saves. A failed write leaves the window and draft intact.
- Clean open notes refresh after external changes. Dirty notes keep local writing
  and resolve differences through the same conflict-preserving save path.
- Metadata arrives before bodies. Four background readers index full text while
  opening and editing remain available. Search rows reserve their final height.
- Whole-note search, relevant excerpts, stable selection, and opening at body
  matches. Title matches preserve the previous document position.
- The unused AI editing and API-key interface are removed.

During the side-by-side preview, the original app could still perform its old,
uncoordinated writes. The rebuild keeps independent history of its own saved
versions, but cannot fix an older binary's behavior. The main installation was
replaced after the user approved promotion; its original bundle is backed up.

## Side-by-side builds and data

`npm run build:desktop` builds the main **Drift.app**, bundle identifier
`com.drift.app`. The user authorized replacing the original installation on
September 6. Main and preview builds use `scripts/build-desktop.sh`, which
requires a stable Apple signing identity; do not use ad-hoc signing for installed
updates. Its changing code-hash identity caused repeated Documents consent.
Use `DRIFT_SIGNING_IDENTITY` when several signing identities are available.

`npm run build:desktop-preview` builds **Drift Preview.app**, bundle identifier
`com.drift.desktop-preview`. Install this only as **Drift Preview.app**.

Development defaults to:
`~/Library/Application Support/com.drift.desktop-preview/Notebook`.

`./scripts/preview-desktop.sh` explicitly forces that copied notebook even when
the installed preview has been connected to the real one. Test files belong
there or in test-created temporary directories. The user-facing preview uses
an explicit `notebook-location.json` containing the absolute real folder path.
Its recovery/history then use the separate `Live` directory. Browser recovery
and reading positions are namespaced by notebook folder as well.

Do not copy test drafts into the live notebook. The original notebook snapshot
and file checksums are local under the preview's `audit` directory; do not commit
private notes or their names. The current app and notebook must be checked before
and after release preparation.

## Verification

Run `npm run build`, `npx tsx --test tests/session.test.ts`,
`cargo test --manifest-path src-tauri/Cargo.toml --lib`, and
`npx playwright test e2e/desktop-rebuild.spec.ts`.

Browser tests use the explicit notebook API mock in `e2e/preview-mocks.ts`.
They cover full-text opening, failed and concurrent saves, clearing text,
crash recovery, external changes, isolated undo, closing, a 1,000-note index,
empty-result navigation, mixed links, and screenshots at narrow/normal sizes.
They complement native Rust filesystem tests and manual native app checks;
mocked browser tests do not establish behavior of a real iCloud provider.

The legacy `e2e/tauri-mocks.ts` represented the original filesystem API. Keep
its fixture adapter current when running the older interaction checks; do not
interpret a permissive unhandled command as filesystem verification.

## Release check, September 6

The release bundle was installed as `/Applications/Drift Preview.app`, locally
signed, and passed strict signature verification. Thirteen native filesystem
checks and three save-queue tests passed. The larger browser run passed 54 checks;
after bounded list rendering, all 36 rebuild checks passed, including reaching
the final row of a 1,000-note search. The earlier run includes the legacy scrolling
and wrapping scenarios. Visual fixtures are in `desktop-evidence/`.

Native walkthroughs covered both appearances, long-note reading/typing, Find,
quick-open, restoring a note after quitting, multiple windows, and focusing a
previously opened note while retaining the second window's writing. The final
Find placement and the bounded search list were visually checked in the installed
app. Real provider synchronization between physical devices remains untested.

All 803 original Markdown contents and the installed original executable matched
their recorded checksums before connecting the finished preview to the real
notebook. Its separate test notebook remains available for future development.

The first real-folder launch showed an empty catalogue during macOS's initial
Documents access transition. After a normal restart the real catalogue and a
real note opened successfully. A final checksum check confirmed the 803 recorded
note contents and original app executable were unchanged; live history and
recovery directories contained no writes from that read-only walkthrough.

## Desktop polish, September 6

New windows inherit the current window's size and cascade 28 logical pixels down
and right, rolling back inside the current monitor's usable area at the edge.
Help → Keyboard Shortcuts (Cmd+/) opens a temporary reference. Escape or the
same shortcut returns to the existing editor selection. Handle this key before
CodeMirror's default comment command so opening help never edits the document.

Selection backgrounds are measured per visual row, using CodeMirror's
bidi-aware rectangles and caret layer. A selected newline extends horizontally
without joining through the line spacing; body text, titles, and wrapped lists
keep the same selection height as the range grows.

`e2e/desktop-polish.spec.ts` checks those selection transitions and the shortcut
reference, including unchanged note text and focus restoration. Window placement
has a separate check for offset, monitor edges, and oversized parent windows.

The macOS menu bridge maps muda's keypad Enter equivalent to ordinary Return.
The shortcut reference spells out `⌘ Return`; native QA checked that key toggles
one checkbox exactly once. Final native and browser checks passed (13 Rust,
4 TypeScript, and 44 browser scenarios across Chromium and WebKit; the 8 polish
checks were also rerun after the Return label change). The installed update was
signed and verified, with the previous build retained in the preview's audit
folder. The user's running windows were left open for a convenient restart.
QA used the copied notebook, and the original Drift binary was unchanged at this stage.
The live notebook changed during this session while the user continued using it;
those changes were left intact, with no attempt to restore the earlier snapshot.

List toggles map an empty cursor after newly inserted prefixes, so a blank or
indented checklist line is ready for writing. Selected bullets and checklists
convert by replacing prefixes while preserving indentation and the text range.
A mixed selection keeps existing checked items when converted to checklists;
invoking the same format on a uniformly formatted selection removes its markers.
The polish suite covers typing after an empty marker, converting in both
directions, mixed selections, and toggling back to plain text.

Cmd+Return applies to every checkbox on the selected lines. If any are unchecked,
it checks them all; if all are checked, it unchecks them. Plain lines stay intact,
and a selection ending at the start of the next line excludes that line. The
selection is retained and the batch is one undoable change. With only a cursor,
the command still applies to the current line.

Typing `[]`, `-[]`, or `- []` followed by Space at the start of a line expands
to `- [ ] `, preserving indentation and placing the cursor after the marker.
Undo restores the shorthand. Pasted text, selections, and code remain literal.

## Launch and quit presentation

Windows start hidden, including Cmd+Shift+N and reopening after the last window.
An inline head script applies the saved appearance before the main module loads;
the title font is preloaded. Once the note and lifecycle handlers are ready,
`window_ready` matches the native background to the page and reveals the window.
The initial catalogue scan follows presentation. Do not await animation frames
while the native window is hidden: WebKit may suspend them.

Quit and Close handlers register before notebook reads. Startup-time Quit waits
for recovery initialization and then saves; native readiness replays a request
that arrived before JavaScript registered. Destroyed windows stop counting toward
pending quit acknowledgments. A failed save cancels Quit for all windows and
allows another attempt. Once all saves finish, windows hide before teardown.

`DRIFT_PROFILE=1` logs lifecycle timings without note contents. On the disposable
notebook, instrumented pre-change readiness took 547–572 ms. Updated readiness
was 526–561 ms (shown at 532–573 ms). These measurements do not establish a speed
regression or improvement versus older historical builds; the presentation
sequence is the concrete improvement. A clean single-window quit took about 7 ms;
a two-window quit with pending writing saved in 44 ms and reached the process exit
event in 554 ms. Teardown timing varies, so do not describe every quit as instant.

The final run passed 64 Chromium/WebKit checks, 13 Rust checks, and 4 TypeScript
checks. Lifecycle checks include early Quit, recovered drafts, failed saves,
retrying after another window cancels Quit, early theme paint, and presentation
before indexing. Native QA covered light/dark relaunches and quitting two windows
with pending writing, using only the disposable notebook.

## Links

Plain click expands a compact link for editing; Cmd+click opens it. This choice
was confirmed by the user. Replacement widgets must forward mouse events to the
editor, and modified selection gestures must retain ordinary editing semantics.
Opening a link never changes the note, moves the caret, or starts a window drag.

Only the link containing the caret or intersecting the selection expands, rather
than every link on its line. Hover shows the complete destination in a small,
selectable preview without reflow; Escape dismisses it. URL text remains complete
in the document and clipboard. Compact addresses retain their host and up to
16 characters of path, with an ellipsis when more is hidden. Clicking a visible
character places the cursor at that source position; the ellipsis goes to the
end of the full destination.

Link boundaries come from the Markdown parser, including bare/autolink support,
balanced URL parentheses, and punctuation. Code spans stay inert. Only valid
HTTP(S) destinations open externally; no metadata or previews are fetched.
The link suite verifies the browser-open request and exact destination, editing,
hover placement, source copying, selection gestures, and launch-error reporting.

The release regression run passed 84 Chromium/WebKit checks. After refining
literal ampersand handling, all 22 link checks passed again and TypeScript
compilation passed. Native QA confirmed compact rendering and plain-click
editing of bare and named links using the copied notebook; the fixture remained
unchanged. External-open requests and hover placement were verified in browser
tests. The signed update was installed with the previous build retained and
the user's running windows left open. The original installed app was unchanged
at this stage.

## Main app promotion, September 6

The user approved replacing the main desktop installation with version 0.2.
The main app uses the same real Markdown folder through
`~/Library/Application Support/com.drift.app/notebook-location.json`. Promotion
backs up the notebook and both apps' state, then transfers only the live
notebook's appearance, reading positions, history, and recovery. Test notebooks
and their preferences remain separate. Preserve the installed app's outer
directory when exchanging signed Contents so its Dock reference stays valid.

File → Allow Notebook Access… opens a standard macOS folder chooser for the
configured notebook. It grants access to that existing folder without moving
notes or changing the notebook location. Stable certificate signing preserves
the app's identity across subsequent updates.

Protected-folder access is deferred until commands can report failures in the
window. A slow initial read shows the warm window after 750 ms; failure retains
the previous note's identity and offers Retry opening. Denied enumeration does
not masquerade as an empty notebook. Recovery is claimed only once per process,
after successful reading, so new or recreated windows cannot replay another
live window's drafts. Disk and browser recovery still survive a fresh launch.
After granting access, catalogue refresh proceeds independently of retrying an
unavailable previous note, so other notes become available immediately.

The first line has title metrics even before it contains text. A new page starts
with a large caret, and typing the first character keeps its row height steady.

The final regression run passed 140 browser checks across Chromium and WebKit,
4 TypeScript session/window checks, and 18 native Rust checks. Native QA used a
disposable notebook to verify checklist shorthand, exact cursor placement inside
compact links, the initial title caret, multiple windows, and saving on Quit.
Both installed bundles passed strict signature verification.
After the final access-retry change, all 28 lifecycle checks passed again.

The main app was granted access to the existing notebook through the native
folder chooser. A normal quit and Launch Services relaunch restored an existing
note and searched the real catalogue without another permission prompt. This
walkthrough was read-only: all 814 files in the final notebook snapshot matched
their SHA-256 hashes afterward, with no added or missing files. Original apps,
preferences, notebook contents, and the checksum manifest remain in the local
preview audit directory.

# Drift interaction reference

Review date: September 5, 2026. Original reference: commit `daced39`.
This records the original app's behavior and the accepted direction. After
using the rebuild on their phone, the user approved it as the main iOS app.
The normal `Drift` target is the product; Drift Preview is disposable QA only.

## Direction

The user values the original app's fine interaction details, including controls
sliding away. They liked some of the rebuild's typography, disliked added
chrome and accidental spacing, and identified the home screen's top buttons
as an area that could improve.

The strongest interpretation of the original is that the note should occupy
attention while controls recede with use. Motion, touch feedback, and the
continuity between states are part of the design. A quiet screenshot alone
does not establish that the interaction is right.

## Behaviors to preserve

### Reading

- Controls retreat as the user moves into the document. The original at
  `daced39` fades the floating Back control between 8 and 76 points of scroll
  and disables its hit target when hidden. Earlier versions explicitly made
  the bar slide proportionally with the swipe (`9414424`) and placed a menu
  inside the scrolling content (`eaf044e`). Preserve the intended motion;
  do not blindly restore the old navigation heuristic, which caused jank and
  interfered with edge-back (`a138137`).
- Pull beyond the top of the page to reveal Read Mode. Its label brightens
  past a 78-point threshold; releasing toggles the mode. The same gesture
  exits. The persistent editor menu was intentionally removed (`5ecb11d`).
- Read Mode is scroll-only: no keyboard, cursor, text selection, or callout.
  A small, subdued lock provides the sole mode indicator. Its material bubble
  was deliberately removed to reduce visual weight (`8cbeb1d`). Exiting the
  mode allows editing without immediately forcing the keyboard open.
- The page extends beneath system edges, with soft paper gradients rather
  than a hard boundary below a toolbar.
- Extra space after a short document lets the reader move it upward into a
  comfortable position. Preserve that ability while eliminating accidental
  gaps between lines or paragraphs.
- The native edge-back gesture stays available even when the visible Back
  control has disappeared.

### Opening and writing

- Existing populated notes open quietly, with text already present during
  navigation. The title and body must not appear after the slide completes.
- Compose opens the page and raises the keyboard together, as one movement
  (`eaf044e`). Existing empty notes also focus automatically.
- The first nonblank line is the title inside the same editable document.
- A newly created note abandoned while empty leaves no list debris.
- Typing keeps the caret comfortably above the keyboard. Keyboard dismissal
  follows the drag interactively. The paper color continues through window,
  navigation, and keyboard transitions without a white flash.
- Native undo and selection should remain stable while heading styling changes.

### Home and search

- Keep a single row for menu, search, and compose. The original already removed
  a separate wordmark/header during its own simplification (`5c2c499`).
- Rows pass underneath the floating glass controls. This was explicitly added
  to make the glass feel translucent, with a soft status-bar fade (`23f90a5`).
- The list extends to the bottom screen edge when the keyboard is hidden;
  search keeps its viewport above the keyboard without leaving a fixed bottom strip.
- Search replaces compose with cancel using a small opacity/scale transition.
  Cancel clears both query and keyboard. Search excerpts show the relevant
  passage and emphasize the match.
- Row feedback begins on touch-down, in sepia, and remains through the opening
  transition. The original uses an immediate highlight latched for 450ms.
- Rows use quiet date/excerpt metadata, full-width hairlines, and no chevrons.
  Dates adapt from time to yesterday, weekday, month/day, and year as needed.
- Copy and delete are secondary actions on a long-pressed row. They do not
  require permanent editor controls.

## Refinement allowed by current feedback

The home controls can have better proportion, alignment, and visual weight
while retaining their floating behavior. In particular, avoid an ellipsis
inside a drawn circle inside another circular button. Keep the single row.

The current serif headings and readable system body are part of the accepted
app. Typography can improve selectively; keep the warm paper/ink/sepia palette
and judge changes in the real reading and writing flows.

Reliable saving, conflict preservation, recovery, and responsive file access
belong beneath these interactions. Surface an actual problem when it needs
attention; successful routine saving does not need a permanent label.

New pins, sections, status bars, labels, and always-present menu buttons are
not established requirements. Evaluate any addition against the existing
workflow before adding it.

## Restoration in the rebuild

The fixed editor bar has been replaced with a floating Back control that
translates upward and fades with the document. Pull-to-read, scroll-only
reading, a subtle lock, and leaving Read Mode without keyboard focus are
restored. The pull hint appears below the system status area, and a keyboard
dismissal drag cannot also trigger a mode change.

The editor again spans the page with soft edges and deliberate short-note
overscroll. New and empty notes request focus during the opening transition.
The home uses a floating glass row, compose/cancel animation, immediate row
feedback, full-width separators, and the original adaptive dates. Added pins
and the persistent undo toolbar have been removed. Actual deletion offers a
temporary Undo action; recovery remains available from Notebook Options.

The storage safeguards and the rebuild's serif headings/readable system body
remain in the accepted app.

## How to assess a revision

Compare the original and revised app with the same disposable short and long
notes. Watch touch-down, opening, scrolling in both directions, pull-to-read,
returning to edit, edge-back, compose, keyboard appearance/dismissal, and search
entry/cancel/result selection. Check continuity and touch response, not only
settled screenshots. Test keyboard, recovery, and conflict behavior separately.

Original-reference evidence: source and focused commit history were reviewed. A separate
original build was launched and its home, opening transition, and short editor
were inspected in Simulator. The live gesture walkthrough was incomplete
because the Mac locked; precise gesture rules above are source-confirmed, not
claimed as fully verified by that walkthrough.

Rebuild validation, September 5, 2026: 29 unit tests and all 14 UI scenarios
passed across the full run and focused reruns after fixes. Coverage includes
save/relaunch, recovery and conflicts, native undo, compose focus, search,
pull-to-read, keyboard dismissal, short/long document scrolling, completed and
cancelled edge-back gestures, and landscape typing/saving. Additional runs on
an iPhone 16e simulator passed search, reading, and long-note editing in dark
mode with accessibility-large text. Exported screenshots were visually checked
for control placement, safe areas, keyboard clearance, and typography. Selected
evidence is in `screenshots/rebuild-*.png`; these are disposable test notes.

The separate Drift Preview simulator build contains sample notes. Subsequent
physical iPhone feedback and fixes are recorded below. Provider changes still
need device validation; simulator checks alone do not establish iCloud behavior.

## First device feedback: build 3

The first phone release exposed a catalogue-size dependency in note opening.
The listing worker and document worker are now independent; opening uses the
already indexed text plus any local recovery draft, and checks for external
updates after the push finishes. Concurrent refresh requests share one scan,
with a replacement if a mutation invalidates its result. Provider writes still
compare against the saved baseline before replacing any text.

Compose now starts an unsaved session. An untouched or whitespace-only page
creates no shared file, catalogue row, or trash entry. Meaningful writing is
journaled before its first titled file is created. Recovery and late writes
retain the document identity when that temporary session becomes a real file.

The home scroll indicator has its own safe-area inset instead of inheriting
the larger content inset for the floating controls. The checked screenshot is
`screenshots/rebuild-home-scroll-indicator.png`.

A 1,000-note regression fixture held an unrelated file inside a coordinated
write while opening a different note. Cached opening took about 0.9 ms and
fresh opening about 3 ms, both before the busy file was released. These measure
the store APIs in Simulator, not total touch-to-display time on the phone.

Build 3 validation: all 38 unit tests and six focused UI scenarios passed.
The added checks cover blank composers, first-save collisions, recovery before
the first shared file exists, delayed journals after materialization, recovered
draft deletion/Undo, and scans invalidated by edits. UI checks cover immediate
compose/back, typing/save/reopen, background/relaunch, cancelled edge-back,
full-body search, and opening/reopening with 1,000 other notes. The scroll
indicator screenshot was visually checked at the top of that large list.

## Startup and editor scroll feedback: build 4

Startup no longer waits for all note bodies. A metadata-only directory pass
publishes filenames and dates first; recent previews and full-text search are
filled in progressively. A purgeable local catalogue restores known rows and
text on subsequent launches before the provider scan. Bookmark restoration no
longer validates the entire folder before showing that cache. Folder selection
also becomes interactive as soon as its catalogue is available.

Cached text remains a saved baseline, with local recovery drafts taking
precedence. Every partial scan validates the folder, refresh identity, and
mutation revision before publishing. Successful saves and deletes checkpoint
the local cache without waiting for a provider scan. The home reconfigures only
changed rows as previews arrive.

The editor scroll indicator now uses its own safe-area insets, independently
of the title padding and floating Back control, matching the home fix. Page
spacing, short-note overscroll, and the retreating control remain unchanged.

All 43 unit tests passed. New regressions cover first catalogue publication
with an unrelated body held busy, bookmark-based restart with the whole folder
blocked, external deletion reconciliation across restarts, orphaned recovery
drafts, and deletion during background hydration. The cold 802-note catalogue
and selected note were available in about 0.36 seconds while the unrelated
file was still held. This measures store availability in Simulator, not
touch-to-display performance on the phone.

Five focused UI scenarios also passed: empty compose/back, long-note scrolling
and edge-back, full-body search, landscape editing with the keyboard, and
opening/reopening/relaunching with 1,000 other notes. The signed 0.2 build 4 was
installed and its version verified on the physical phone. The phone was locked,
so automatic launch and on-device timing were not verified.

The focused long-note gesture test passed again after moving its screenshot
past the return animation. Visually reviewed evidence includes the visible
thumb during return (`screenshots/rebuild-editor-scroll-return.png`), the
settled top with Back restored (`screenshots/rebuild-editor-at-top.png`), and
landscape keyboard clearance. The thumb had faded in the settled capture;
a further live check was interrupted when the Mac locked.

## Smooth preview arrival: build 5

The first uncached load was reproduced with a real coordinated read held busy
after metadata published. Empty previews had hidden the larger subheadline
label, so adding them grew each regular row from 78.33 to 82 points. The third
row moved 7.33 points; with accessibility-large text, it moved 9.33 points.

Rows now use their final font-derived height from the start, including a
reserved metadata line. Titles and dates stay in place while the first preview
fades in over 160 ms, respecting Reduce Motion. Explicit row heights also avoid
estimated-height corrections when scrolling a large notebook. Fonts continue
to scale with the view's Dynamic Type category.

Hydration follows the visible date/filename order and publishes the first eight
changed previews before starting another body read. The remaining work stays
batched; unchanged scans do not publish extra body updates. Missing modification
dates retain the metadata-stage fallback instead of temporarily appearing new.
The initial list still never waits for every body to load.

Validation: 44 store/editor tests, one hosted layout regression, and three UI
scenarios passed. The layout regression checks row, title, date, and scroll
positions at the top and partway down, in regular/light and accessibility-large/
dark. The separate provider barrier test confirms a ready first preview and its
searchable text appear while the next file is still blocked. The 802-note cold
catalogue/selected-note check remained about 0.34 seconds in Simulator. UI checks
cover home/opening, full-body search, and opening/reopening/relaunching with
1,000 other notes. Build 5 was installed, its version verified, and launched on
the physical phone; the timing above remains a simulator store measurement.

Before/after phase captures are in `screenshots/startup-hydration/`. The final
hosted capture uses layer rendering for repeatable text/layout evidence;
actual UI screenshots separately confirm the system glass and home appearance.

## Main app release preparation: build 6

The user approved this version as the main iOS app. `AGENTS.md` captures the
short aesthetic guide, and the normal `Drift` target retains the original
bundle identity and saved folder bookmark. The previous UI is available in Git
history; the separate Preview installation remains a development tool.

Review fixed two recovery edge cases: renewal failure for an otherwise usable
folder bookmark no longer prevents opening it, and Undo must relocate a pending
draft before moving its shared file or removing the trash record. The latter
has a failure/restart/retry test that checks the newer writing, baseline, and
document identity survive.

Release preparation passed 45 store/editor tests, one hosted layout test, and
all 15 UI scenarios. The signed Release build also passed signature validation.

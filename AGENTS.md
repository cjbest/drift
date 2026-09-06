# Drift

For a request to build and install the app, follow [docs/INSTALL.md](docs/INSTALL.md).
Install the normal **Drift** app; Preview builds are for development and testing.

The Mac app, its dependencies, and its tests live in `drift-mac`. Run npm and
Cargo commands there. The native iPhone and iPad app lives in `drift-ios`.

The normal `Drift` target in `drift-ios` is the main iOS app. `Drift Preview`
is only a separate installation for disposable QA.

- **Keep the notebook quiet.** Notes should hold attention. Preserve the warm
  paper, ink, and sepia palette; avoid adding persistent save labels, counters,
  pins, sections, or extra controls without a concrete need. Selective
  typography improvements are welcome; a broader redesign is not implied.
- **Treat interaction details as design.** Retreating controls, pull-to-toggle
  Read Mode, edge-back, immediate row feedback, and the keyboard joining the
  opening transition were deliberate. Understand the existing behavior before
  simplifying it. Preserve useful details while improving their reliability.
- **Keep the page steady.** Loading previews must not resize rows or move the
  list. Titles and text should arrive with the opening transition; typing and
  keyboard dismissal should feel continuous. Judge the app in motion as well
  as in a settled screenshot.

See [the iOS interaction reference](drift-ios/DESIGN.md) for the specific
behaviors and the reasoning behind them.

For desktop behavior, side-by-side builds, and safe notebook testing, see
[the desktop reference](docs/DESKTOP-DESIGN.md). Desktop development must use the
copied notebook; `scripts/preview-desktop.sh` enforces that choice.

Every keyboard shortcut must also appear in the native app menu.

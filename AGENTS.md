# Drift

For a request to build and install the app, follow [docs/INSTALL.md](docs/INSTALL.md).
Install the normal **Drift** app; Preview builds are for development and testing.

The Mac app, its dependencies, and its tests live in `drift-mac`. Run npm and
Cargo commands there. The native iPhone and iPad app lives in `drift-ios`.

The normal `Drift` target in `drift-ios` is the main iOS app. `Drift Preview`
is only a separate installation for disposable QA.

- **Keep the notebook quiet.** Preserve warm paper, ink, sepia, and attention
  on the note. Persistent labels, counters, pins, and controls need a concrete
  purpose. Selective typography improvements do not imply a redesign.
- **Treat interaction details as design.** Retreating controls, pull-to-toggle
  Read Mode, edge-back, immediate row feedback, and the keyboard joining the
  opening transition are deliberate. Start feedback immediately; coordinate
  content, intended focus, and surfaces. Do not hide flashes by postponing input.
- **Keep the user's place.** Prepare content before revealing it; loading must
  not move targets. A keyboard changes the viewport, not the document. Recompute
  affected content only; preserve the caret, selection, and reading position.
- **Give active state one owner.** Handle only the owning view's keyboard;
  background refresh must not recreate an active menu. Keep view/layout identities
  stable. Investigate competing writers and rebuilds before tuning delays or easing.
- **Make interruption ordinary.** Typing during motion, reversing a gesture,
  and cancelling Back must remain coherent. Respond with reversible presentation;
  save and clean up safely underneath. Never delete data early or wait on a
  provider merely to smooth a frame.

See [the iOS interaction reference](drift-ios/DESIGN.md) for the specific
behaviors and the reasoning behind them.

For desktop behavior, side-by-side builds, and safe notebook testing, see
[the desktop reference](docs/DESKTOP-DESIGN.md). Desktop development must use the
copied notebook; `scripts/preview-desktop.sh` enforces that choice.

Every keyboard shortcut must also appear in the native app menu.

## Jank Audit

After interaction, rendering, loading, focus, or appearance changes, run the
affected routes in [docs/JANK-AUDIT.md](docs/JANK-AUDIT.md). Before a release,
run the core routes for that platform. Judge transitions in motion, including
repeated and interrupted use; passing functional tests or settled screenshots
alone do not establish smoothness. Use disposable notes and report coverage.
Fold new lessons into these principles; keep platform exceptions beside their
implementation and [prune rather than append](docs/JANK-AUDIT.md#keep-the-learning-small).

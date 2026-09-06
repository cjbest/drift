# Build and install Drift

Instructions for a coding agent installing Drift for its user. Read [AGENTS.md](../AGENTS.md)
first. An installation request means the normal **Drift** app. Preview builds
are for development and disposable testing.

## Mac

1. Read the relevant section of [DESKTOP-DESIGN.md](DESKTOP-DESIGN.md) before changing an existing
   installation. Preserve its notebook, preferences,
   history, and recovery. The main bundle ID is `com.drift.app`. Do not change
   this identifier, overwrite notebook configuration, or copy demonstration
   notes into the user's notebook.
2. Check `node --version`, `npm --version`, `cargo --version`,
   `rustc --version`, and `xcode-select -p`. Use a supported Node LTS satisfying
   `>=22.12.0` and current stable Rust. Use the lockfile
   rather than relying on the older minimum listed in `Cargo.toml`. Install Apple
   command-line tools with `xcode-select --install` if absent. Full Xcode is
   also suitable; launch it once to finish setup.
3. Check `security find-identity -v -p codesigning`. The desktop build requires
   a stable **Apple Development** or **Developer ID Application** identity.
   Select a certificate belonging to the user's own Apple team. Set
   `DRIFT_SIGNING_IDENTITY` to its SHA-1 hash and `DRIFT_APPLE_TEAM_ID` to its
   ten-character team ID. Verify the certificate's organization and team, not
   just the person's name in its label. The scripts never select an identity
   automatically and reject the project's former Substack signing team.
   Never bypass the script with ad-hoc signing.
   An Apple Development certificate can be created with a free Apple account;
   paid membership is needed for Developer ID distribution, not this local build.
   If none exists, the user must add their Apple account in Xcode and create an
   Apple Development certificate under Settings → Accounts → Manage Certificates.
   Continue installing other prerequisites while any human-only setup is pending.
4. From the repository root, run:

   ```sh
   npm --prefix drift-mac ci
   npm --prefix drift-mac run build:desktop
   ```

   This builds the frontend, Rust backend, and signed application. The result is
   `drift-mac/src-tauri/target/release/bundle/macos/Drift.app`. It does not install the app.
   Keep both lockfiles; do not update dependencies merely to install Drift.
5. Install as `/Applications/Drift.app`, or `~/Applications/Drift.app` if the user
   cannot write to the system Applications directory. Keep an existing app at
   its current path. If updating, quit it normally so its autosave can finish,
   wait for the process to exit, and retain a backup of the old signed bundle.
   Preserve the existing outer `Drift.app` directory to keep its Dock reference;
   replace its entire `Contents` directory with the newly built `Contents`.
   Do not merge over stale Contents files or delete Application Support.
   For a first installation, copy the complete bundle:

   ```sh
   ditto "drift-mac/src-tauri/target/release/bundle/macos/Drift.app" "/Applications/Drift.app"
   ```

   Adjust the destination if using the user Applications folder. Do not replace
   an installed app that has failed to quit or finish saving.
6. Verify the installed copy and launch that exact path:

   ```sh
   codesign --verify --deep --strict --verbose=2 /Applications/Drift.app
   open /Applications/Drift.app
   ```

   Confirm that the window opens and report the installation path. Use Preview
   for any scripted writing or save tests; do not test by modifying real notes.

### Notebook location

A fresh installation needs no folder setup. It creates and uses:

`~/Documents/Drift`

It opens a short first note explaining autosave and the main shortcuts. If
that folder already contains Markdown notes, Drift uses the existing notes
instead of adding the introduction. Allow macOS access to Documents if asked.

Upgrades keep the current notebook. Older installations using the app-owned
`~/Library/Application Support/com.drift.app/Notebook` stay there, and any
explicitly configured folder is preserved.

File → Show Notebook in Finder reveals the current folder. Preserve an existing
`~/Library/Application Support/com.drift.app/notebook-location.json` on upgrades.

Use **File → Choose Notebook Folder…** to select or create a different folder.
Drift saves its open notes and reopens in the selected folder. Existing notes
stay where they are; the command does not move or merge notebooks. Recovery
and history remain separate for each folder. A failed save cancels the switch
so the current writing stays available.

Do not edit the notebook configuration by hand or replace it during an upgrade.
Legacy configurations containing an absolute path as a JSON string remain
supported. **File → Allow Notebook Access…** grants macOS access to the current
folder if needed; it does not change the notebook location. For iCloud sync,
choose the same actual Markdown folder on both devices; do not assume another
Mac's path or move an existing notebook without the user's instruction.

### Development

From the repository root, `./scripts/preview-desktop.sh` builds and launches **Drift Preview** with its
app-owned notebook copy. It forces `DRIFT_NOTEBOOK_MODE=preview` even if an
installed Preview app was previously configured for another folder. Follow
[DESKTOP-DESIGN.md](DESKTOP-DESIGN.md) for changes and tests. Installing the existing app does not
require running the entire development test suite.

## iPhone and iPad

Run the commands in this section from the repository root.

This is a separate native Swift app in `drift-ios`; it does not need Tauri's
mobile tooling, CocoaPods, Node, or Rust. It requires full Xcode and iOS 17 or
later. Install XcodeGen (`brew install xcodegen`), then:

```sh
xcodegen generate --spec drift-ios/project.yml
open drift-ios/Drift.xcodeproj
```

Use the normal **Drift** scheme. The project intentionally has no default
development team. Select the user's own team in Xcode, or pass
`DEVELOPMENT_TEAM` in command-line build arguments. Do not use an employer's
team or commit personal signing settings. For a new user's device install, select an available bundle identifier
under their team if `com.drift.notes` cannot be provisioned. Record that choice
and keep it for subsequent updates. Existing installations must retain their
team and bundle identity to preserve the app and selected-folder state; never
delete the installed app to solve a signing error.

Trust and unlock the connected device, enable Developer Mode when Xcode asks,
select it as the destination, and build/run. Apple account login, device trust,
and device consent require the user's participation when not already configured.
On first launch, choose a Markdown folder through the native picker. For shared
notes, select the same iCloud Drive folder used on the Mac.

With a free Personal Team, device provisioning expires after seven days. Build
and reinstall over the same app to renew it; see [Apple's account guide](https://developer.apple.com/help/account/basics/about-your-developer-account).

For a simulator preview with disposable notes, use `./scripts/preview-ios.sh`.
That script defaults to an available iPhone 17 Pro. On another machine, obtain
an available UUID with `xcrun simctl list devices available` and set
`SIMULATOR_ID` explicitly. It installs the separate `com.drift.notes.preview`
app without signing. See [drift-ios/README.md](../drift-ios/README.md) for the native test workflow.

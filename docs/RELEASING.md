# Releasing Drift

The first public distribution is a notarized **Apple Silicon Mac download** and
an **iPhone/iPad TestFlight beta**. Use the owner's personal Apple Developer
membership for both. Customers do not need a developer account or Xcode.

## Signing ownership

Confirm the personal membership's legal name and Team ID on
[Apple's membership page](https://developer.apple.com/account). Do not infer
ownership from a developer's name on a certificate: a certificate bearing that
name can belong to an employer's team.

Do not use, modify, export, or revoke Substack's certificates, private keys,
provisioning profiles, or App Store Connect credentials. The old local
development certificate belongs to that organization; it is not a Drift release
credential. `scripts/apple-signing.sh` rejects that team and Substack-owned
certificates, and requires an explicit identity and verified Team ID for every
signed desktop build. No certificate is chosen automatically.

Keep certificate private keys, app-specific passwords, and API keys in Keychain
or another appropriate secret store. Do not put them in the repository, shell
history, issue comments, or agent messages. Public Team IDs and certificate
fingerprints are identifiers, not passwords.

## Mac

### One-time setup

1. Use the personal membership to create a **Developer ID Application**
   certificate and install it with its private key in the login Keychain.
   Apple Development is sufficient for local development, but not for this
   public download. Follow [Apple's Developer ID guide](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/).
2. Set these identifiers locally, after checking their ownership. Find the
   certificate's SHA-1 with `security find-identity -v -p codesigning`.

   ```sh
   export DRIFT_APPLE_TEAM_ID="YOURTEAMID"
   export DRIFT_SIGNING_IDENTITY="YOUR_DEVELOPER_ID_CERTIFICATE_SHA1"
   export DRIFT_NOTARY_PROFILE="drift-personal-$DRIFT_APPLE_TEAM_ID"
   ```

3. Create a new Drift-only Keychain profile for notarization. Use the personal
   account's email address below. `notarytool` securely prompts for an
   [app-specific password](https://support.apple.com/102654); do not pass that
   password as a command-line argument. The explicit Team ID must match the
   certificate verified above. Do not reuse a company notary profile.

   ```sh
   xcrun notarytool store-credentials "$DRIFT_NOTARY_PROFILE" \
     --apple-id "YOUR_PERSONAL_APPLE_ACCOUNT_EMAIL" \
     --team-id "$DRIFT_APPLE_TEAM_ID"
   ```

   The profile is stored in Keychain without enabling iCloud Keychain sync.
   Its setup validates the credentials with Apple. The release preflight
   checks that the profile still authenticates; it cannot independently discover
   which team was originally used to create an existing profile.

4. Install the build prerequisites in [INSTALL.md](INSTALL.md), including full
   Xcode for `notarytool` and `stapler`. Then, from the repository root:

   ```sh
   npm --prefix drift-mac ci
   ./scripts/release-desktop.sh --check
   ```

   This verifies the installed Developer ID certificate, its actual owning
   team, required tools, and the dedicated notary profile. It does not build,
   sign, install, or submit an app.

### Build the download

Finish the application tests listed in [DESKTOP-DESIGN.md](DESKTOP-DESIGN.md)
and check the release diff first. Keep the Tauri, npm, and Cargo application
versions aligned when incrementing the version. From the repository root:

```sh
./scripts/release-desktop.sh
```

The script uses Tauri's standard drag-to-Applications DMG. It builds the normal
`com.drift.app` app for Apple Silicon (`arm64`), with a release-only minimum of
macOS 14. This is the declared compatibility floor, not evidence that every
supported OS has been tested. The initial release must say **Apple Silicon**;
do not advertise an Intel or universal build until one has been built and tested.

The script keeps output under `drift-mac/src-tauri/target/distribution` and never
installs over the local app. It verifies the app's certificate, Team ID,
hardened runtime, secure timestamp, bundle ID, architecture, and absence of
debugger entitlements. It signs the final DMG, submits that outer container to
Apple, checks acceptance, staples its ticket, validates it, checks Gatekeeper on
both the DMG and the contained app, and writes `SHA256SUMS` after stapling.

Do not run `build-desktop.sh` over release output or re-sign an accepted image.
The local development script deliberately does not perform notarization; the
distribution signature and ticket must remain intact. Apple's workflow is
documented in [Packaging Mac software for distribution](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)
and [Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

Apple's first notarization can take longer than subsequent submissions. The
script saves the submission ID and waits up to 30 minutes. If it times out,
keep the same environment and use the exact work directory it printed:

```sh
./scripts/release-desktop.sh --finish "/absolute/path/to/release-directory"
```

This resumes the existing submission without rebuilding, re-signing, or
uploading again. It checks that the original DMG and selected signing identity
still match the saved submission. The original stays in the `submitted/`
subdirectory; the final download is created separately, so a later interrupted
staple or Gatekeeper check can be retried safely. If Apple rejects the build, inspect the saved
`notarization-log.json`, fix the problem, and create a new release build.

### Third-party notices

The app bundles `Contents/Resources/notices`, including dependency and font
licenses plus the Rust standard library's own copyright report. The checked-in
notices are generated from both lockfiles and the current Rust toolchain;
the release script refuses stale or missing notices.

After changing dependencies, font notices, or the Rust toolchain, regenerate:

```sh
cargo install --locked --version 0.9.2 --features cli cargo-about
rustup component add rust-docs
npm --prefix drift-mac ci
node scripts/generate-notices.mjs
node scripts/generate-notices.mjs --check
```

`cargo-about` supplies the Rust dependency graph and license texts. The generator
also preserves actual package copyright files and pinned upstream notices from
`drift-mac/licenses/upstream.json`; it does not invent holders for SPDX template
placeholders. Five older crates declare their licenses only in package metadata;
their declared terms and author attribution are included explicitly. Review new
missing-license cases before updating that list. The application Cargo package
is marked non-publishable so this process does not assign a license to Drift.

The check hashes the font and upstream source notices as well as the generated
files, lockfiles, configuration, generator, and Rust version. Normal source
installs use the checked-in resources and do not require `cargo-about`.

### Verify and publish

Before publication, test the finished DMG on a fresh user account or a separate
Mac. Use a disposable notebook for writing tests. Check first launch, creating
and reopening a note, choosing an existing notebook, search, keyboard shortcuts,
dark mode, and saving on Quit. Check both the declared oldest supported macOS
and the current macOS when those test machines are available; record any
unavailable coverage in the release notes.

Test a real iCloud Drive folder with a physical iPhone: edits in both directions,
offline edits followed by reconnection, and concurrent changes. This is separate
from the mocked browser tests. Do not use the author's real notes as release
fixtures. Preserve the installed app's notebook configuration, preferences,
history, and recovery during update testing.

Create a GitHub release for the exact tested commit and upload the completed
`.dmg` and `SHA256SUMS`. The download should be labeled with the version, Apple
Silicon requirement, and macOS minimum. Download that hosted copy in a browser
on a fresh account or second Mac and repeat the drag-to-Applications and launch
check. This exercises the quarantine/Gatekeeper path that a local build skips.
Never tell customers to remove quarantine or disable Gatekeeper.

Only after the release asset exists and the downloaded copy works, add a
**Download for Mac** link to the README. Updates initially use the same download
and replace-app flow; no automatic updater is shipped yet. Do not promise
automatic updates in the release copy.

## iPhone and iPad

Use the normal **Drift** target and the same verified personal membership.
`Drift Preview` remains a disposable local installation. The product and privacy
details for App Store Connect are in [APP-STORE.md](APP-STORE.md).

Create the Drift app record under the personal team, archive a distribution build,
and upload it through Xcode Organizer. Select the personal team explicitly during
archive/export and inspect the resulting signing team before upload. The old
company development team must not be reused. If the existing bundle identifier
is unavailable to the personal team, stop and resolve app ownership and identifier
choice before changing it; do not silently replace an installed app's identity.

For the first beta, create an external TestFlight group and public invitation
link, complete the beta review information, and submit the build for external
testing. External testers need Apple's TestFlight app, not a developer account.
Builds expire 90 days after upload. See [Apple's TestFlight guide](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview).
Only add **Try on iPhone** to the README once its actual invitation link works.

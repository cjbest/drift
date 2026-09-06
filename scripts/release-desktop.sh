#!/bin/bash
set -euo pipefail
script_dir="$(cd "$(dirname "$0")" && pwd)"
desktop_dir="$(cd "$script_dir/../drift-mac" && pwd)"
cd "$desktop_dir"

usage() {
  cat <<'EOF'
Usage: scripts/release-desktop.sh [--check | --finish RELEASE_DIRECTORY]

Build an Apple Silicon DMG, sign with the owner's Developer ID, notarize, and
staple it. Does not install the app or publish a GitHub release.

Required environment:
  DRIFT_APPLE_TEAM_ID       Verified personal Apple Developer Team ID
  DRIFT_SIGNING_IDENTITY    SHA-1 of that team's Developer ID Application cert
  DRIFT_NOTARY_PROFILE      Dedicated notarytool Keychain profile for that team

--check checks prerequisites and credentials without building or submitting.
--finish resumes an existing notarization without rebuilding or re-signing.
See docs/RELEASING.md for credential setup and the final download smoke test.
EOF
}
mode=build
release_dir=""
case "${1:-}" in
  "") [[ $# == 0 ]] || { usage >&2; exit 2; } ;;
  --check) [[ $# == 1 ]] || { usage >&2; exit 2; }; mode=check ;;
  --finish) [[ $# == 2 ]] || { usage >&2; exit 2; }; mode=finish; release_dir="$2" ;;
  --help|-h) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac
if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
  echo "The first public release is built on Apple Silicon for Apple Silicon Macs." >&2
  exit 1
fi
commands=(node xcrun)
if [[ "$mode" != finish ]]; then commands+=(npm cargo rustc); fi
for command in "${commands[@]}"; do
  command -v "$command" >/dev/null || { echo "Missing prerequisite: $command" >&2; exit 1; }
done
if [[ "$mode" != finish ]]; then
  [[ -d node_modules/@tauri-apps/cli ]] || { echo "Run npm --prefix drift-mac ci first." >&2; exit 1; }
  node "$script_dir/generate-notices.mjs" --check
fi
source "$script_dir/apple-signing.sh"
drift_require_signing_identity developer-id
[[ -n "${DRIFT_NOTARY_PROFILE:-}" ]] || { echo "Set DRIFT_NOTARY_PROFILE to a dedicated personal-team Keychain profile." >&2; exit 1; }
/usr/bin/xcrun --find stapler >/dev/null
/usr/bin/xcrun notarytool history --keychain-profile "$DRIFT_NOTARY_PROFILE" --output-format json >/dev/null
if [[ "$mode" == check ]]; then
  echo "Release prerequisites and personal signing certificate verified. Nothing built or submitted."
  exit 0
fi

scratch="$(mktemp -d "${TMPDIR:-/tmp}/drift-release.XXXXXX")"
mounted=0
cleanup() {
  if [[ "$mounted" == 1 ]]; then /usr/bin/hdiutil detach "$scratch/mounted" >/dev/null || true; fi
  rm -rf "$scratch"
}
trap cleanup EXIT

json_value() {
  node --input-type=module -e 'import fs from "node:fs"; const value = JSON.parse(fs.readFileSync(process.argv[1], "utf8"))[process.argv[2]]; if (typeof value !== "string" || !value) process.exit(1); process.stdout.write(value);' "$1" "$2"
}
verify_signature() {
  local artifact="$1" details
  /usr/bin/codesign --verify --deep --strict --verbose=2 "$artifact"
  details="$(/usr/bin/codesign -dv --verbose=4 "$artifact" 2>&1)"
  [[ "$details" == *$'\n'"TeamIdentifier=$DRIFT_APPLE_TEAM_ID"* ]] || { echo "Unexpected signing team: $artifact" >&2; exit 1; }
  [[ "$details" == *"Authority=$DRIFT_APPLE_IDENTITY_NAME"* ]] || { echo "Unexpected signing certificate: $artifact" >&2; exit 1; }
  [[ "$details" == *$'\nTimestamp='* ]] || { echo "Missing secure signing timestamp: $artifact" >&2; exit 1; }
}
verify_application() {
  local app="$1" details executable
  verify_signature "$app"
  details="$(/usr/bin/codesign -dv --verbose=4 "$app" 2>&1)"
  [[ "$details" == *"(runtime)"* ]] || { echo "Hardened runtime is missing." >&2; exit 1; }
  [[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Contents/Info.plist")" == com.drift.app ]] || { echo "Not the main Drift bundle." >&2; exit 1; }
  executable="$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$app/Contents/Info.plist")"
  [[ "$(/usr/bin/lipo -archs "$app/Contents/MacOS/$executable")" == arm64 ]] || { echo "Unexpected release architecture." >&2; exit 1; }
  /usr/bin/codesign -d --entitlements :- "$app" > "$scratch/entitlements.plist" 2>/dev/null
  if [[ -s "$scratch/entitlements.plist" ]] && [[ "$(/usr/libexec/PlistBuddy -c 'Print com.apple.security.get-task-allow' "$scratch/entitlements.plist" 2>/dev/null || true)" == true ]]; then
    echo "A distribution app must not enable get-task-allow." >&2
    exit 1
  fi
}

if [[ "$mode" == build ]]; then
  version="$(json_value src-tauri/tauri.conf.json version)"
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Use a numeric release version." >&2; exit 1; }
  # Isolate release output from installed/development builds. Disallow inherited
  # Tauri credential imports or automatic notarization under another account.
  export CARGO_TARGET_DIR="$desktop_dir/src-tauri/target/distribution"
  unset APPLE_CERTIFICATE APPLE_CERTIFICATE_PASSWORD APPLE_ID APPLE_PASSWORD
  unset APPLE_API_ISSUER APPLE_API_KEY APPLE_API_KEY_PATH APPLE_TEAM_ID
  export APPLE_SIGNING_IDENTITY="$DRIFT_SIGNING_IDENTITY"
  config='{"bundle":{"macOS":{"minimumSystemVersion":"14.0","hardenedRuntime":true}}}'
  npm exec -- tauri build --target aarch64-apple-darwin --bundles app dmg --config "$config" --ci
  bundle_dir="$CARGO_TARGET_DIR/aarch64-apple-darwin/release/bundle"
  verify_application "$bundle_dir/macos/Drift.app"
  built_dmg="$bundle_dir/dmg/Drift_${version}_aarch64.dmg"
  [[ -f "$built_dmg" ]] || { echo "Expected Apple Silicon DMG was not generated." >&2; exit 1; }
  release_dir="$(mktemp -d "$CARGO_TARGET_DIR/Drift-$version-macOS-AppleSilicon.XXXXXX")"
  mkdir "$release_dir/submitted"
  dmg="$release_dir/submitted/Drift-$version-macOS-AppleSilicon.dmg"
  /usr/bin/ditto "$built_dmg" "$dmg"
  # The app inside is already final and signed by Tauri. Sign only the outer
  # disk image here, before its one notarization submission; never re-sign later.
  /usr/bin/codesign --force --sign "$DRIFT_SIGNING_IDENTITY" --timestamp "$dmg"
  verify_signature "$dmg"
  node --input-type=module - "$dmg" "$DRIFT_APPLE_TEAM_ID" "$DRIFT_SIGNING_IDENTITY" > "$release_dir/release.json" <<'NODE'
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
const [dmg, team, identity] = process.argv.slice(2);
console.log(JSON.stringify({ file: path.basename(dmg), team, identity: identity.toUpperCase(), sha256: crypto.createHash('sha256').update(fs.readFileSync(dmg)).digest('hex') }, null, 2));
NODE
  /usr/bin/xcrun notarytool submit "$dmg" --keychain-profile "$DRIFT_NOTARY_PROFILE" --no-wait --output-format json > "$release_dir/submission.json"
else
  release_dir="$(cd "$release_dir" && pwd)"
  file="$(json_value "$release_dir/release.json" file)"
  [[ "$file" == "$(basename "$file")" && "$file" == *.dmg ]] || { echo "Invalid release filename." >&2; exit 1; }
  dmg="$release_dir/submitted/$file"
  node --input-type=module - "$release_dir/release.json" "$dmg" "$DRIFT_APPLE_TEAM_ID" "$DRIFT_SIGNING_IDENTITY" <<'NODE'
import fs from 'node:fs';
import crypto from 'node:crypto';
const [manifest, dmg, team, identity] = process.argv.slice(2);
const saved = JSON.parse(fs.readFileSync(manifest));
const hash = crypto.createHash('sha256').update(fs.readFileSync(dmg)).digest('hex');
if (saved.team !== team || saved.identity !== identity.toUpperCase() || saved.sha256 !== hash) {
  console.error('The submitted disk image or selected signing identity changed. Refusing to finish.');
  process.exit(1);
}
NODE
  verify_signature "$dmg"
fi

submission="$(json_value "$release_dir/submission.json" id)"
echo "Notarization submission: $submission"
echo "Release work directory: $release_dir"
if ! /usr/bin/xcrun notarytool wait "$submission" --keychain-profile "$DRIFT_NOTARY_PROFILE" --timeout 30m --output-format json > "$release_dir/notarization.json"; then
  echo "Notarization has not finished successfully. Resume without rebuilding:" >&2
  printf '  %q --finish %q\n' "$script_dir/release-desktop.sh" "$release_dir" >&2
  exit 1
fi
if [[ "$(json_value "$release_dir/notarization.json" status)" != Accepted ]]; then
  /usr/bin/xcrun notarytool log "$submission" --keychain-profile "$DRIFT_NOTARY_PROFILE" "$release_dir/notarization-log.json"
  echo "Apple did not accept this release. See $release_dir/notarization-log.json" >&2
  exit 1
fi
# Keep the submitted bytes unchanged. Stapling modifies the disk image, and a
# later Gatekeeper or mount check may fail. --finish can always retry from this
# immutable submission and create the final, stapled download again.
submitted_dmg="$dmg"
dmg="$release_dir/$(basename "$submitted_dmg")"
/usr/bin/ditto "$submitted_dmg" "$dmg"
/usr/bin/xcrun stapler staple "$dmg"
/usr/bin/xcrun stapler validate "$dmg"
verify_signature "$dmg"
/usr/sbin/spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
mkdir "$scratch/mounted"
/usr/bin/hdiutil attach "$dmg" -readonly -nobrowse -mountpoint "$scratch/mounted" >/dev/null
mounted=1
verify_application "$scratch/mounted/Drift.app"
/usr/sbin/spctl --assess --type execute --verbose=2 "$scratch/mounted/Drift.app"
/usr/bin/hdiutil detach "$scratch/mounted" >/dev/null
mounted=0
(cd "$release_dir" && /usr/bin/shasum -a 256 "$(basename "$dmg")" > SHA256SUMS)
echo "Signed, notarized Apple Silicon DMG ready: $dmg"
echo "Complete the downloaded-copy smoke test in docs/RELEASING.md before publishing."

#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../drift-mac"
# Keep Cargo's output aligned with the bundle paths verified and signed below,
# even when the caller normally uses a shared or custom Cargo target directory.
export CARGO_TARGET_DIR="$PWD/src-tauri/target"

variant="${1:-main}"
build_args=(build --bundles app)
case "$variant" in
  main)
    bundle="src-tauri/target/release/bundle/macos/Drift.app"
    ;;
  preview)
    bundle="src-tauri/target/release/bundle/macos/Drift Preview.app"
    build_args+=(--config src-tauri/tauri.preview.conf.json)
    ;;
  *)
    echo "Usage: $0 [main|preview]" >&2
    exit 2
    ;;
esac
if [[ $# -gt 1 || "$(uname -s)" != Darwin ]]; then
  echo "This script builds and signs a macOS app: $0 [main|preview]" >&2
  exit 2
fi

# Signing must use an explicitly selected personal certificate and team. Never
# fall back to an unrelated company identity merely because it is installed.
source ../scripts/apple-signing.sh
drift_require_signing_identity development
signing_identity="$DRIFT_SIGNING_IDENTITY"

# This is the local build path. Public downloads use release-desktop.sh, which
# preserves timestamped runtime signatures and notarizes the final disk image.
# Ignore inherited certificate imports and notary credentials in this path.
unset APPLE_CERTIFICATE APPLE_CERTIFICATE_PASSWORD APPLE_ID APPLE_PASSWORD
unset APPLE_API_ISSUER APPLE_API_KEY APPLE_API_KEY_PATH APPLE_TEAM_ID

# Tauri signs any nested code before the enclosing app. Re-sign the app itself
# explicitly as well, so the final bundle always uses the selected identity.
APPLE_SIGNING_IDENTITY="$signing_identity" npm exec -- tauri "${build_args[@]}"
/usr/bin/codesign --force --sign "$signing_identity" --timestamp=none "$bundle"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$bundle"
signed_team="$(/usr/bin/codesign -dv --verbose=4 "$bundle" 2>&1 | /usr/bin/sed -n 's/^TeamIdentifier=//p')"
if [[ "$signed_team" != "$DRIFT_APPLE_TEAM_ID" ]]; then
  echo "The signed app does not belong to the expected personal team." >&2
  exit 1
fi
requirement="$(/usr/bin/codesign -d -r- "$bundle" 2>&1)"
if [[ "$requirement" == *"designated => cdhash "* ]]; then
  echo "The build has an unstable ad-hoc identity; it is not ready to install." >&2
  exit 1
fi
echo "$requirement"
echo "Signed app ready: $bundle"

#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../drift-mac"

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

# Ad-hoc signatures identify each rebuild by its content hash. Signing with a
# stable certificate lets macOS recognize updates and retain folder consent.
# Keep personal signing identities out of source control.
signing_identity="${DRIFT_SIGNING_IDENTITY:-}"
if [[ -z "$signing_identity" ]]; then
  signing_identity="$(/usr/bin/security find-identity -v -p codesigning |
    /usr/bin/awk '/^[[:space:]]*[0-9]+\) [A-Fa-f0-9]+ "(Apple Development|Developer ID Application):/ { print $2 }')"
  if [[ -z "$signing_identity" || "$signing_identity" == *$'\n'* ]]; then
    echo "Set DRIFT_SIGNING_IDENTITY to one available Apple Development or Developer ID Application signing identity." >&2
    echo "List identities with: security find-identity -v -p codesigning" >&2
    exit 1
  fi
fi
if [[ "$signing_identity" == "-" ]]; then
  echo "Ad-hoc signing is not supported for desktop releases; use a stable signing identity." >&2
  exit 1
fi

# Tauri signs any nested code before the enclosing app. Re-sign the app itself
# explicitly as well, so the final bundle always uses the selected identity.
APPLE_SIGNING_IDENTITY="$signing_identity" npm exec -- tauri "${build_args[@]}"
/usr/bin/codesign --force --sign "$signing_identity" --timestamp=none "$bundle"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$bundle"
requirement="$(/usr/bin/codesign -d -r- "$bundle" 2>&1)"
if [[ "$requirement" == *"designated => cdhash "* ]]; then
  echo "The build has an unstable ad-hoc identity; it is not ready to install." >&2
  exit 1
fi
echo "$requirement"
echo "Signed app ready: $bundle"

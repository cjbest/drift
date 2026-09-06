#!/bin/bash
# Build a separate simulator app with disposable sample notes.
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [ -z "${SIMULATOR_ID:-}" ]; then
  SIMULATOR_ID="$(xcrun simctl list devices available --json | python3 -c 'import json,sys; devices=[d for ds in json.load(sys.stdin)["devices"].values() for d in ds if d["name"] == "iPhone 17 Pro"]; print(devices[0]["udid"] if devices else "")')"
fi
if [ -z "$SIMULATOR_ID" ]; then
  printf 'Set SIMULATOR_ID to an available iPhone simulator UUID.\n' >&2
  exit 1
fi
BUILD_DIR="${BUILD_DIR:-/tmp/drift-ios-preview-build}"
NOTES_DIR="$(mktemp -d /tmp/drift-preview-notes.XXXXXX)"
cat > "$NOTES_DIR/The shape of a good day.md" <<'NOTE'
The shape of a good day

A slow morning. A long walk. Enough time to follow an idea somewhere unexpected.

Small things worth keeping

- Coffee before the inbox
- A notebook within reach
- One thing finished, properly
- Dinner with people I love

The best days have room in them.
NOTE
cat > "$NOTES_DIR/Things to make.md" <<'NOTE'
Things to make

A reading corner by the window. A really good loaf of bread. More time for the people who matter.

- A place to collect half-formed ideas
- A playlist for the long way home
- A small dinner, no occasion needed
NOTE
cat > "$NOTES_DIR/Weekend, loosely planned.md" <<'NOTE'
Weekend, loosely planned

Saturday at the farmers market, then nowhere in particular.

- Flowers for the kitchen
- The bookshop on the corner
- Find a new path by the water
NOTE
xcodegen generate --spec "$REPO_DIR/drift-ios/project.yml"
xcodebuild -quiet -project "$REPO_DIR/drift-ios/Drift.xcodeproj" -scheme Drift \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -derivedDataPath "$BUILD_DIR" \
  build CODE_SIGNING_ALLOWED=NO PRODUCT_BUNDLE_IDENTIFIER=com.drift.notes.preview APP_DISPLAY_NAME='Drift Preview'
xcrun simctl boot "$SIMULATOR_ID" 2>/dev/null || true
xcrun simctl bootstatus "$SIMULATOR_ID" -b
xcrun simctl install "$SIMULATOR_ID" "$BUILD_DIR/Build/Products/Debug-iphonesimulator/Drift.app"
SIMCTL_CHILD_DRIFT_TEST_FOLDER="$NOTES_DIR" xcrun simctl launch --terminate-running-process "$SIMULATOR_ID" com.drift.notes.preview
printf 'Preview is running. Disposable notes: %s\n' "$NOTES_DIR"

#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
npm run build:desktop-preview
# Running the binary with this explicit override always uses the copied notebook,
# even after the installed preview has been connected to the real notebook.
DRIFT_NOTEBOOK_MODE=preview exec "src-tauri/target/release/bundle/macos/Drift Preview.app/Contents/MacOS/Drift"

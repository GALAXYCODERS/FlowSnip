#!/bin/bash
set -euo pipefail

# ============================================
# FlowSnip ZIP Exporter
# ============================================
# Builds FlowSnip and packages it as a ZIP for
# direct distribution (AirDrop, iCloud, etc.).
#
# Usage:
#   bash scripts/export-zip.sh             # full build + zip
#   bash scripts/export-zip.sh --skip-build  # zip existing build
#
# Output: build/FlowSnip.zip
# ============================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_PATH="$PROJECT_DIR/build/Release/FlowSnip.app"
ZIP_PATH="$PROJECT_DIR/build/FlowSnip.zip"
SKIP_BUILD=false

for arg in "$@"; do
  [[ "$arg" == "--skip-build" ]] && SKIP_BUILD=true
done

cd "$PROJECT_DIR"

# ── 1. Build ──────────────────────────────────────────────────────────────────
if [[ "$SKIP_BUILD" == false ]]; then
  echo "Building FlowSnip (Release)..."
  xcodebuild \
    -project FlowSnip.xcodeproj \
    -scheme FlowSnip \
    -configuration Release \
    -derivedDataPath build/DerivedData \
    CONFIGURATION_BUILD_DIR=build/Release \
    CODE_SIGN_STYLE=Automatic \
    clean build
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "Error: App not found at $APP_PATH" >&2
  exit 1
fi

# ── 2. Ad-hoc sign ────────────────────────────────────────────────────────────
echo "Signing app (ad-hoc)..."
codesign --deep --force --sign - "$APP_PATH"

# ── 3. ZIP ────────────────────────────────────────────────────────────────────
echo "Creating ZIP..."
rm -f "$ZIP_PATH"
cd "$PROJECT_DIR/build/Release"
zip -r ../FlowSnip.zip FlowSnip.app
cd "$PROJECT_DIR"

echo ""
echo "✓ ZIP erstellt: build/FlowSnip.zip"
echo ""
echo "─── Anleitung für deinen Freund ───────────────────────────────────────"
echo " 1. ZIP entpacken"
echo " 2. FlowSnip.app in den Ordner /Programme (Applications) ziehen"
echo " 3. Beim ersten Start: Rechtsklick auf die App → 'Öffnen' → 'Öffnen'"
echo "    (macOS fragt einmalig nach, weil die App nicht aus dem App Store kommt)"
echo ""
echo "    Alternativ per Terminal:"
echo "    xattr -dr com.apple.quarantine /Applications/FlowSnip.app"
echo "────────────────────────────────────────────────────────────────────────"

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
DERIVED_DATA="${FLOWSNIP_DERIVED_DATA:-$PROJECT_DIR/build/DerivedData}"
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
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$DERIVED_DATA" \
    CONFIGURATION_BUILD_DIR="$PROJECT_DIR/build/Release" \
    CODE_SIGNING_ALLOWED=NO \
    -quiet \
    build
fi

LICENSE_DIR="$APP_PATH/Contents/Resources/Licenses"
mkdir -p "$LICENSE_DIR"
chmod -R u+w "$LICENSE_DIR"
CHECKOUT_DIR="$DERIVED_DATA/SourcePackages/checkouts"
if [[ ! -d "$CHECKOUT_DIR" ]]; then
  echo "Error: Package checkout licenses are unavailable in $CHECKOUT_DIR" >&2
  exit 1
fi
while IFS= read -r -d '' repository; do
  repository_name="$(basename "$repository")"
  while IFS= read -r -d '' license_file; do
    mkdir -p "$LICENSE_DIR/$repository_name"
    cp "$license_file" "$LICENSE_DIR/$repository_name/$(basename "$license_file")"
  done < <(find "$repository" -maxdepth 1 -type f \( -iname 'license*' -o -iname 'notice*' \) -print0)
done < <(find "$CHECKOUT_DIR" -mindepth 1 -maxdepth 1 -type d -print0)
if [[ -d "$CHECKOUT_DIR/swift-crypto/Sources/CCryptoBoringSSL" ]]; then
  while IFS= read -r -d '' notice; do
    mkdir -p "$LICENSE_DIR/swift-crypto/BoringSSL"
    cp "$notice" "$LICENSE_DIR/swift-crypto/BoringSSL/$(basename "$notice")"
  done < <(find "$CHECKOUT_DIR/swift-crypto/Sources/CCryptoBoringSSL" -maxdepth 1 -type f \( -iname '*license*' -o -iname '*notice*' \) -print0)
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "Error: App not found at $APP_PATH" >&2
  exit 1
fi

# ── 2. Ad-hoc sign ────────────────────────────────────────────────────────────
echo "Signing app (ad-hoc)..."
codesign --deep --force --sign - "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"

# ── 3. ZIP ────────────────────────────────────────────────────────────────────
echo "Creating ZIP..."
rm -f "$ZIP_PATH"
cd "$PROJECT_DIR/build/Release"
ditto -c -k --sequesterRsrc --keepParent FlowSnip.app "$ZIP_PATH"
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

#!/bin/bash
set -euo pipefail

# ============================================
# FlowSnip DMG Creator
# ============================================
# Creates a distributable .dmg file for FlowSnip.
#
# Prerequisites:
#   - Xcode 27+ with macOS 27 SDK and Metal compiler
#   - Optional: create-dmg (brew install create-dmg) for fancy DMG styling
#
# Usage:
#   ./scripts/create-dmg.sh
#   ./scripts/create-dmg.sh --skip-build   # Use existing build
# ============================================

APP_NAME="FlowSnip"
SCHEME="FlowSnip"
PROJECT="FlowSnip.xcodeproj"
BUILD_DIR="build/Release"
DMG_DIR="build/dmg"
DMG_OUTPUT="build/${APP_NAME}.dmg"
VOLUME_NAME="${APP_NAME}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

SKIP_BUILD=false
if [[ "${1:-}" == "--skip-build" ]]; then
    SKIP_BUILD=true
fi

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== ${APP_NAME} DMG Creator ===${NC}"
echo ""

# Step 1: Build the app
if [[ "$SKIP_BUILD" == false ]]; then
    echo -e "${BLUE}[1/4] Building ${APP_NAME}...${NC}"
    bash "$SCRIPT_DIR/export-zip.sh"

    if [[ ! -d "${BUILD_DIR}/${APP_NAME}.app" ]]; then
        echo "Error: Build failed. ${APP_NAME}.app not found in ${BUILD_DIR}/"
        exit 1
    fi
    echo -e "${GREEN}Build successful.${NC}"
else
    echo -e "${BLUE}[1/4] Skipping build (--skip-build)${NC}"
    if [[ ! -d "${BUILD_DIR}/${APP_NAME}.app" ]]; then
        echo "Error: ${APP_NAME}.app not found in ${BUILD_DIR}/. Run without --skip-build first."
        exit 1
    fi
fi
codesign --verify --deep --strict "${BUILD_DIR}/${APP_NAME}.app"

# Step 2: Prepare DMG staging directory
echo -e "${BLUE}[2/4] Preparing DMG contents...${NC}"
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"
cp -R "${BUILD_DIR}/${APP_NAME}.app" "$DMG_DIR/"

# Step 3: Create DMG
echo -e "${BLUE}[3/4] Creating DMG...${NC}"
rm -f "$DMG_OUTPUT"

if [[ "${FLOWSNIP_FANCY_DMG:-0}" == "1" ]] && command -v create-dmg &> /dev/null; then
    # Fancy DMG with create-dmg (brew install create-dmg)
    create_dmg_exit=0
    create-dmg \
        --volname "$VOLUME_NAME" \
        --volicon "${BUILD_DIR}/${APP_NAME}.app/Contents/Resources/AppIcon.icns" \
        --window-pos 200 120 \
        --window-size 660 400 \
        --icon-size 100 \
        --icon "${APP_NAME}.app" 180 190 \
        --hide-extension "${APP_NAME}.app" \
        --app-drop-link 480 190 \
        --no-internet-enable \
        "$DMG_OUTPUT" \
        "$DMG_DIR/" || create_dmg_exit=$?
    if [[ "$create_dmg_exit" -ne 0 && "$create_dmg_exit" -ne 2 ]]; then
        echo "Error: create-dmg failed ($create_dmg_exit)."
        exit "$create_dmg_exit"
    fi
    # create-dmg returns exit code 2 when it can't set background but DMG was created
    if [[ ! -f "$DMG_OUTPUT" ]]; then
        echo "Error: DMG creation failed."
        exit 1
    fi
else
    # Fallback: basic DMG with hdiutil — needs manual Applications symlink
    echo "  Creating a standard app-and-Applications disk image."
    ln -s /Applications "$DMG_DIR/Applications"
    hdiutil create \
        -volname "$VOLUME_NAME" \
        -srcfolder "$DMG_DIR" \
        -ov \
        -format UDZO \
        "$DMG_OUTPUT"
fi

# Step 4: Cleanup
echo -e "${BLUE}[4/4] Cleaning up...${NC}"
rm -rf "$DMG_DIR"

# Done
DMG_SIZE=$(du -h "$DMG_OUTPUT" | cut -f1)
echo ""
echo -e "${GREEN}Done! DMG created:${NC}"
echo "  ${DMG_OUTPUT} (${DMG_SIZE})"
echo ""
echo "To install: Open the .dmg and drag ${APP_NAME} to Applications."

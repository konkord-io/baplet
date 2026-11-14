#!/usr/bin/env bash
# release.sh — Archive, export, create DMG, notarize, and staple Baplet for
# distribution outside the Mac App Store.
set -euo pipefail

APP_NAME="Baplet"
DISPLAY_NAME="Baplet"
SCHEME="baplet"
PROJECT="baplet.xcodeproj"
EXPORT_PLIST="ExportOptions.plist"
BUILD_DIR="./build"
ARCHIVE_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive"
EXPORT_PATH="${BUILD_DIR}/export"
DMG_PATH="${BUILD_DIR}/${DISPLAY_NAME}.dmg"
NOTARY_PROFILE="baplet-notary"

# ── Helpers ──────────────────────────────────────────────────────────────────

## Print a step header to stdout.
step() {
  echo ""
  echo "▸ $1"
  echo "────────────────────────────────────────"
}

## Print an error message to stderr and exit.
fail() {
  echo "✖ ERROR: $1" >&2
  exit 1
}

# ── Pre-flight checks ───────────────────────────────────────────────────────

step "Pre-flight checks"

for cmd in xcodebuild xcrun hdiutil; do
  command -v "$cmd" >/dev/null 2>&1 || fail "'$cmd' not found. Install Xcode command-line tools."
done
echo "  xcodebuild, xcrun, hdiutil — OK"

[ -f "$EXPORT_PLIST" ] || fail "'$EXPORT_PLIST' not found. Run this script from the project root."
echo "  $EXPORT_PLIST — OK"

# ── Check notarization credentials ──────────────────────────────────────────

step "Checking notarization credentials"

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo ""
  echo "  Notarization credentials for profile '$NOTARY_PROFILE' are not stored."
  echo ""
  echo "  Run the following command to store them:"
  echo ""
  echo "    xcrun notarytool store-credentials \"$NOTARY_PROFILE\" \\"
  echo "      --apple-id \"YOUR_APPLE_ID@example.com\" \\"
  echo "      --team-id \"H2MCB54VDW\" \\"
  echo "      --password \"YOUR_APP_SPECIFIC_PASSWORD\""
  echo ""
  echo "  Generate an app-specific password at https://appleid.apple.com/account/manage"
  echo ""
  exit 1
fi
echo "  Keychain profile '$NOTARY_PROFILE' — OK"

# ── Clean build directory ───────────────────────────────────────────────────

step "Cleaning build directory"
rm -rf "$BUILD_DIR"
echo "  Removed $BUILD_DIR"

# ── Archive ─────────────────────────────────────────────────────────────────

step "Archiving $APP_NAME"
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  | tail -1

echo "  Archive created at $ARCHIVE_PATH"

# ── Export ──────────────────────────────────────────────────────────────────

step "Exporting signed app"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$EXPORT_PLIST" \
  -exportPath "$EXPORT_PATH" \
  | tail -1

echo "  Exported to $EXPORT_PATH"

# ── Clean extended attributes ───────────────────────────────────────────────

step "Cleaning extended attributes"
xattr -cr "${EXPORT_PATH}/${APP_NAME}.app"
echo "  xattr cleaned"

# ── Create DMG ──────────────────────────────────────────────────────────────

step "Creating DMG"
hdiutil create \
  -volname "$DISPLAY_NAME" \
  -srcfolder "${EXPORT_PATH}/${APP_NAME}.app" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "  DMG created at $DMG_PATH"

# ── Notarize ────────────────────────────────────────────────────────────────

step "Submitting DMG for notarization"
xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

echo "  Notarization complete"

# ── Staple ──────────────────────────────────────────────────────────────────

step "Stapling notarization ticket"
xcrun stapler staple "$DMG_PATH"
echo "  Stapled"

# ── Verify ──────────────────────────────────────────────────────────────────

step "Verifying stapled DMG"
xcrun stapler validate "$DMG_PATH"
echo "  Validation passed"

# ── Done ────────────────────────────────────────────────────────────────────

echo ""
echo "══════════════════════════════════════════"
echo "  Release ready: $DMG_PATH"
echo "══════════════════════════════════════════"
echo ""

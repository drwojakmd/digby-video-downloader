#!/bin/bash
# Build "Digby Video Downloader.app".
#
#   Scripts/build_app.sh          → build/Digby Video Downloader.app
#   Scripts/build_app.sh --dmg    → also build/DigbyVideoDownloader-<version>.dmg
#
# The download engines (yt-dlp, FFmpeg, Deno) are NOT bundled: the app installs and verifies them
# itself on first run (Phase 3), so the bundle stays small and the engines stay current.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
VERSION=$(cat VERSION)
BUILD="$ROOT/build"
APP="$BUILD/Digby Video Downloader.app"
C="$APP/Contents"

# SwiftPM's build database misbehaves inside iCloud-synced folders (~/Documents).
SCRATCH="${DIGBY_SCRATCH:-${TMPDIR:-/tmp}/digby-video-downloader-build}"
echo "▸ Testing core logic…"
swift run -c release --arch arm64 --scratch-path "$SCRATCH" digby-dl-tests 2>&1 | tail -1
echo "▸ Compiling (release, arm64)…"
swift build -c release --arch arm64 --product DigbyDownloaderApp --scratch-path "$SCRATCH" 2>&1 | grep -vE '^\[[0-9]+/[0-9]+\]' || true
BINDIR=$(swift build -c release --arch arm64 --scratch-path "$SCRATCH" --show-bin-path)
BIN=$BINDIR/DigbyDownloaderApp
# The command-line tool ships inside the app (Contents/Helpers/digby-dl) so other Digby apps can use the
# engines without their own copy (other apps can save videos through it).
swift build -c release --arch arm64 --product digby-dl --scratch-path "$SCRATCH" 2>&1 | grep -vE '^\[[0-9]+/[0-9]+\]' || true
[ -x "$BINDIR/digby-dl" ] || { echo "build failed: digby-dl"; exit 1; }
[ -x "$BIN" ] || { echo "build failed"; exit 1; }

echo "▸ Assembling bundle…"
rm -rf "$APP"
mkdir -p "$C/MacOS" "$C/Helpers" "$C/Resources/Licenses"
cp "$BINDIR/digby-dl" "$C/Helpers/digby-dl"
cp "$BIN" "$C/MacOS/Digby Video Downloader"
cp Resources/AppIcon.icns "$C/Resources/AppIcon.icns"
cp LICENSE "$C/Resources/Licenses/LICENSE.txt"
rm -rf "$C/Resources/Browser Extension"; cp -R Extensions/Chrome "$C/Resources/Browser Extension"
cp Docs/THIRD_PARTY_NOTICES.md "$C/Resources/Licenses/THIRD_PARTY_NOTICES.md"

cat > "$C/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Digby Video Downloader</string>
  <key>CFBundleDisplayName</key><string>Digby Video Downloader</string>
  <key>CFBundleIdentifier</key><string>app.digbyvideo.downloader</string>
  <key>CFBundleExecutable</key><string>Digby Video Downloader</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSArchitecturePriority</key><array><string>arm64</string></array>
  <key>LSApplicationCategoryType</key><string>public.app-category.video</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleURLTypes</key><array><dict>
    <key>CFBundleURLName</key><string>Digby download link</string>
    <key>CFBundleURLSchemes</key><array><string>digby-video</string></array>
  </dict></array>
  <key>NSHumanReadableCopyright</key><string>© 2026 Digby</string>
</dict></plist>
PLIST

echo "▸ Signing (ad-hoc)…"
codesign --force --sign - --timestamp=none "$C/Helpers/digby-dl" 2>/dev/null
codesign --force --sign - --timestamp=none "$APP" 2>/dev/null
codesign --verify --deep --strict "$APP"
MINOS=$(vtool -show-build "$C/MacOS/Digby Video Downloader" 2>/dev/null | awk '/minos/{print $2; exit}')
du -sh "$APP" | awk '{print "  bundle size: "$1}'
echo "  binary minimum macOS: ${MINOS:-?}"

if [[ "${1:-}" == "--dmg" ]]; then
  echo "▸ Creating disk image…"
  STAGE="$BUILD/dmg"; rm -rf "$STAGE"; mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/"; ln -s /Applications "$STAGE/Applications"
  DMG="$BUILD/DigbyVideoDownloader-$VERSION.dmg"; rm -f "$DMG"
  hdiutil create -volname "Digby Video Downloader" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
  rm -rf "$STAGE"
  echo "  $DMG"
fi
echo "✓ $APP"

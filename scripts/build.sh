#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-cache"
mkdir -p .build/package-cache .build/package-config .build/package-security
# The native SwiftPM builder records the selected SDK version in the executable.
# This allows modern AppKit appearances with macOS 26 as the minimum.
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
SWIFT_OPTIONS=(--build-system native --scratch-path "$PWD/.build-native" --sdk "$SDK_PATH" --disable-sandbox --cache-path "$PWD/.build/package-cache" --config-path "$PWD/.build/package-config" --security-path "$PWD/.build/package-security")
swift build "${SWIFT_OPTIONS[@]}" -c release -debug-info-format none
BIN_DIR="$(swift build "${SWIFT_OPTIONS[@]}" -c release --show-bin-path)"
STAGING_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/qingyi-build.XXXXXX")"
APP="$STAGING_ROOT/Qingyi.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Qingyi" "$APP/Contents/MacOS/Qingyi"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi
osacompile -o "$APP/Contents/Resources/NotesArchive.scpt" Resources/NotesArchive.applescript
cp Resources/GoogleTranslate*.png Resources/Dragon.png Resources/Chick.png Resources/NotesArchive.applescript "$APP/Contents/Resources/"
# Freshly created bundles can inherit Finder display metadata from the workspace.
xattr -dr com.apple.FinderInfo "$APP" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "$APP" 2>/dev/null || true
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
mkdir -p "$PWD/dist"
ditto --noextattr --norsrc --noqtn "$APP" "$PWD/dist/Qingyi.app"
# Package the verified staging copy; synced folders may immediately add Finder metadata.
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
ditto -c -k --keepParent --noextattr --norsrc "$APP" "$PWD/dist/Qingyi-${VERSION}.zip"
print "Built: $PWD/dist/Qingyi.app"
print "Signed staging bundle: $APP"
print -r -- "$APP" > "$PWD/.build/signed-app-path.txt"

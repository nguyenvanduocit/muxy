#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(git rev-parse --show-toplevel)"
BUILD_DIR="$PROJECT_ROOT/build"
APP_BUNDLE="$BUILD_DIR/Muxy.app"
INSTALL_PATH="/Applications/Muxy.app"

ARCH="$(uname -m)"
TRIPLE="${ARCH}-apple-macosx14.0"
VERSION="0.0.0-dev"
BUILD_NUMBER="$(git -C "$PROJECT_ROOT" rev-list --count HEAD)"

cd "$PROJECT_ROOT"

echo "==> Building Muxy ($TRIPLE)"
swift build -c release --triple "$TRIPLE"
SPM_BIN="$(swift build -c release --triple "$TRIPLE" --show-bin-path)"

echo "==> Assembling app bundle"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"

cp "$SPM_BIN/Muxy" "$APP_BUNDLE/Contents/MacOS/Muxy"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP_BUNDLE/Contents/MacOS/Muxy"

if [[ -d "$SPM_BIN/Muxy_Muxy.bundle" ]]; then
  cp -R "$SPM_BIN/Muxy_Muxy.bundle" "$APP_BUNDLE/Contents/Resources/Muxy_Muxy.bundle"
fi

cp "$PROJECT_ROOT/Muxy/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_BUNDLE/Contents/Info.plist"

"$PROJECT_ROOT/scripts/create-icns.sh" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

SPARKLE_FRAMEWORK="$PROJECT_ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [[ ! -d "$SPARKLE_FRAMEWORK" ]]; then
  echo "error: Sparkle.framework not found at $SPARKLE_FRAMEWORK" >&2
  exit 1
fi
cp -R "$SPARKLE_FRAMEWORK" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"

echo "==> Ad-hoc signing"
codesign --force --deep \
  --entitlements "$PROJECT_ROOT/Muxy/Muxy.entitlements" \
  --sign - "$APP_BUNDLE"

echo "==> Installing to $INSTALL_PATH"
pkill -x Muxy 2>/dev/null || true
rm -rf "$INSTALL_PATH"
cp -R "$APP_BUNDLE" "$INSTALL_PATH"

echo "done: installed Muxy $VERSION (build $BUILD_NUMBER) to $INSTALL_PATH"

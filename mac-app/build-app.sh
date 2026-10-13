#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${TC002_APP_OUTPUT_DIR:-$ROOT/mac-app/dist}"
case "$OUTPUT_DIR" in /*) ;; *) printf 'TC002_APP_OUTPUT_DIR 必须是绝对路径\n' >&2; exit 2 ;; esac
[ "$OUTPUT_DIR" != / ] || { printf '不能把根目录用作 App 构建目录\n' >&2; exit 2; }
APP_DIR="$OUTPUT_DIR/TC002FocusCompanion.app"
BUILD_DIR="$(mktemp -d /tmp/tc002-focus-swift.XXXXXX)"
cleanup() { rm -rf "$BUILD_DIR"; }
trap cleanup EXIT
SDK="$(xcrun --sdk macosx --show-sdk-path)"
SWIFTC="$(xcrun --find swiftc)"
SWIFT_FEATURE_FLAGS=()
# Older SDKs can still build the compatibility material; modern SDKs include native Liquid Glass.
if [ -f "$SDK/System/Library/Frameworks/AppKit.framework/Headers/NSGlassEffectView.h" ]; then
  SWIFT_FEATURE_FLAGS+=(-D TC002_NATIVE_GLASS)
  SDK_MAJOR="$(xcrun --sdk macosx --show-sdk-version)"; SDK_MAJOR="${SDK_MAJOR%%.*}"
  if [ "$SDK_MAJOR" -ge 27 ]; then SWIFT_FEATURE_FLAGS+=(-D TC002_GLASS_INTERACTION); fi
fi

bash "$ROOT/companion/verify-runtime-bundle.sh" >/dev/null

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources/tc002-repo/device/TC002_Focus_Probe"
for ARCH in arm64 x86_64; do
  mkdir -p "$BUILD_DIR/$ARCH-module-cache" "$BUILD_DIR/$ARCH-clang-cache"
  SWIFT_MODULECACHE_PATH="$BUILD_DIR/$ARCH-module-cache" "$SWIFTC" \
    -parse-as-library \
    -Xcc -fmodules-cache-path="$BUILD_DIR/$ARCH-clang-cache" \
    -sdk "$SDK" -target "$ARCH-apple-macosx13.0" \
    -framework AppKit \
    ${SWIFT_FEATURE_FLAGS[@]+"${SWIFT_FEATURE_FLAGS[@]}"} \
    "$ROOT"/mac-app/Sources/*.swift \
    -o "$BUILD_DIR/TC002FocusCompanion-$ARCH"
done
lipo -create "$BUILD_DIR/TC002FocusCompanion-arm64" "$BUILD_DIR/TC002FocusCompanion-x86_64" \
  -output "$APP_DIR/Contents/MacOS/TC002FocusCompanion"

cp "$ROOT/mac-app/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT/mac-app/Assets/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp "$ROOT/mac-app/Assets/AppIcon.png" "$APP_DIR/Contents/Resources/AppIcon.png"
cp "$ROOT/mac-app/Assets/OakTexture.png" "$APP_DIR/Contents/Resources/OakTexture.png"
cp -R "$ROOT/bridge" "$ROOT/companion" "$ROOT/probes" "$APP_DIR/Contents/Resources/tc002-repo/"
cp -R "$ROOT/device/TC002_Focus_Probe/TemporaryFocusRelease" "$APP_DIR/Contents/Resources/tc002-repo/device/TC002_Focus_Probe/"
chmod +x "$APP_DIR/Contents/MacOS/TC002FocusCompanion"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_DIR/Contents/Info.plist")"
SIGNING_IDENTITY="${TC002_CODESIGN_IDENTITY:--}"
/usr/bin/codesign --force --sign "$SIGNING_IDENTITY" --identifier "$BUNDLE_ID" "$APP_DIR"
/usr/bin/codesign --verify --strict "$APP_DIR"
printf '已生成 %s\n' "$APP_DIR"

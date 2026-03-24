#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/AudioPro.xcodeproj"
SCHEME="AudioPro"
CONFIGURATION="Release"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/AudioPro-release-build}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist}"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/AudioPro.app"
HELPERS_DIR="$APP_PATH/Contents/Helpers"
ARM64_HELPER="$HELPERS_DIR/ffmpeg-binary-arm64"
X86_64_HELPER="$HELPERS_DIR/ffmpeg-binary-x86_64"

echo "==> Building $SCHEME ($CONFIGURATION)"
/usr/bin/xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: Built app not found at $APP_PATH" >&2
  exit 1
fi

echo "==> Verifying packaged helpers"
for helper in "$ARM64_HELPER" "$X86_64_HELPER"; do
  if [[ ! -f "$helper" ]]; then
    echo "error: Missing packaged helper $helper" >&2
    exit 1
  fi

  if [[ ! -x "$helper" ]]; then
    echo "error: Helper is not executable: $helper" >&2
    exit 1
  fi

  /usr/bin/codesign --verify --strict --verbose=2 "$helper"
done

echo "==> Verifying app signature"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_PATH/Contents/Info.plist")"
ZIP_NAME="AudioPro-${VERSION}-macOS.zip"
ZIP_PATH="$OUTPUT_DIR/$ZIP_NAME"
CHECKSUMS_PATH="$OUTPUT_DIR/SHA256SUMS.txt"

mkdir -p "$OUTPUT_DIR"
rm -f "$ZIP_PATH" "$CHECKSUMS_PATH"

echo "==> Creating release archive $ZIP_NAME"
/usr/bin/ditto -c -k --keepParent --sequesterRsrc "$APP_PATH" "$ZIP_PATH"

echo "==> Writing checksums"
(
  cd "$OUTPUT_DIR"
  /usr/bin/shasum -a 256 "$ZIP_NAME" > "$CHECKSUMS_PATH"
)

echo
echo "Release ready"
echo "Version      : $VERSION ($BUILD_NUMBER)"
echo "App          : $APP_PATH"
echo "Archive      : $ZIP_PATH"
echo "Checksums    : $CHECKSUMS_PATH"
echo
echo "Next steps:"
echo "1. Smoke-test the built app locally."
echo "2. Upload the ZIP and SHA256SUMS.txt to a GitHub Release."
echo "3. In release notes, remind users to open the app via right-click > Open on first launch."

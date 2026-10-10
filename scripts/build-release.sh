#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/.derivedData/release}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist}"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release/AudioPro.app"

build_arguments=(
  -project "$ROOT_DIR/AudioPro.xcodeproj"
  -scheme AudioPro
  -configuration Release
  -destination 'generic/platform=macOS'
  -derivedDataPath "$DERIVED_DATA_PATH"
  'ARCHS=arm64 x86_64'
  ONLY_ACTIVE_ARCH=NO
  INCLUDE_LOCAL_WHISPER_MODEL=NO
  CODE_SIGNING_ALLOWED=NO
  CODE_SIGNING_REQUIRED=NO
)
if [[ -n "${RELEASE_VERSION:-}" ]]; then
  if [[ ! "$RELEASE_VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    print -u2 'error: RELEASE_VERSION must have the form 2.1.0'
    exit 1
  fi
  build_arguments+=("MARKETING_VERSION=$RELEASE_VERSION")
fi

/usr/bin/xcodebuild "${build_arguments[@]}" build
[[ -d "$APP_PATH" ]] || { print -u2 "error: Missing app: $APP_PATH"; exit 1; }
[[ ! -e "$APP_PATH/Contents/Resources/WhisperModels" ]] || {
  print -u2 'error: Public releases must not contain Whisper model weights'
  exit 1
}

for architecture in arm64 x86_64; do
  /usr/bin/lipo "$APP_PATH/Contents/MacOS/AudioPro" -verify_arch "$architecture"
done

# A Personal Team cannot issue a Developer ID certificate. Ad-hoc signatures
# seal the app and its sandboxed helpers; first launch still needs Open Anyway.
while IFS= read -r code_path; do
  /usr/bin/codesign --force --sign - --timestamp=none "$code_path"
done < <(/usr/bin/find "$APP_PATH/Contents" -depth \( -name '*.framework' -o -name '*.dylib' \))

for architecture in arm64 x86_64; do
  helper="$APP_PATH/Contents/Helpers/ffmpeg-binary-$architecture"
  [[ -x "$helper" ]] || { print -u2 "error: Missing executable helper: $helper"; exit 1; }
  /usr/bin/lipo "$helper" -verify_arch "$architecture"
  /usr/bin/codesign --force --sign - --timestamp=none \
    --entitlements "$ROOT_DIR/AudioPro/FFmpegHelper.entitlements" \
    --identifier "com.michelemazza.AudioPro.ffmpeg-binary-$architecture" "$helper"
  /usr/bin/codesign --verify --strict "$helper"
done
/usr/bin/codesign --force --sign - --timestamp=none \
  --entitlements "$ROOT_DIR/AudioPro/AudioPro.entitlements" "$APP_PATH"
/usr/bin/codesign --verify --deep --strict "$APP_PATH"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
archive_name="AudioPro-$version-macOS.zip"
mkdir -p "$OUTPUT_DIR"
/usr/bin/ditto -c -k --keepParent "$APP_PATH" "$OUTPUT_DIR/$archive_name"
if /usr/bin/unzip -Z1 "$OUTPUT_DIR/$archive_name" | /usr/bin/grep -q '/WhisperModels/'; then
  print -u2 'error: Release archive unexpectedly contains Whisper model weights'
  exit 1
fi
(
  cd "$OUTPUT_DIR"
  /usr/bin/shasum -a 256 "$archive_name" > SHA256SUMS.txt
)
print "App: $APP_PATH"
print "Archive: $OUTPUT_DIR/$archive_name"
print "Checksums: $OUTPUT_DIR/SHA256SUMS.txt"

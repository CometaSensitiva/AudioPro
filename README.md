# AudioPro

AudioPro is a macOS app for importing audio or video files, inspecting compression settings, and exporting optimized audio output.

## Project Structure

- `AudioPro/`: app source files
- `AudioProTests/`: test target
- `AudioPro.xcodeproj/`: Xcode project

## Development

Open `AudioPro.xcodeproj` in Xcode and run the `AudioPro` scheme.

## Bundled FFmpeg

The app ships with two vendored `ffmpeg` helpers inside `AudioPro/`:

- `ffmpeg-binary-arm64`
- `ffmpeg-binary-x86_64`

The Xcode build phase verifies the SHA-256 of both source binaries before copying them into `AudioPro.app/Contents/Helpers/`.
At runtime the app launches the packaged helper only if it is executable and its code signature is valid.

Expected source SHA-256:

- `ffmpeg-binary-arm64`: `3b586ff896c0339e8fd574c143aaccac23c80789341e22d4202f8013a133d3a4`
- `ffmpeg-binary-x86_64`: `26b3ff92f64950f16be16eed88fe29064c2df516efdfac66cb8fa9abed030bdf`

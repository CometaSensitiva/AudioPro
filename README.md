# AudioPro

AudioPro is a macOS app for importing audio or video files, inspecting compression settings, and exporting optimized audio output.

## Project Structure

- `AudioPro/`: app source files
- `AudioProTests/`: test target
- `AudioPro.xcodeproj/`: Xcode project

## Development

Open `AudioPro.xcodeproj` in Xcode and run the `AudioPro` scheme.

## Bundled FFmpeg

The app currently ships with a vendored `ffmpeg-binary` executable inside `AudioPro/`.
At runtime the app verifies its SHA-256 before launching it.

Expected SHA-256:

`26b3ff92f64950f16be16eed88fe29064c2df516efdfac66cb8fa9abed030bdf`

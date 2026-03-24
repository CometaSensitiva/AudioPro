# AudioPro

AudioPro is a macOS app for importing audio or video files, previewing export settings, and producing either optimized audio output or a compressed video export preset for lecture recordings.

AudioPro keeps its current Tahoe-style visual language through a compatibility design layer, while targeting `macOS 14+`.

## Download and install

GitHub Releases are the supported distribution channel for end users.

1. Download the latest `AudioPro-<version>-macOS.zip` asset from the Releases page.
2. Unzip the archive and move `AudioPro.app` to `/Applications`.
3. On first launch, use `right click > Open` on the app.
4. If macOS still blocks the app, open `System Settings > Privacy & Security` and allow it manually.

The app is currently distributed without notarization, so the first launch requires the standard Gatekeeper override flow for non-notarized apps.

## Architecture

The technical architecture is documented in [docs/architecture.md](docs/architecture.md).

```mermaid
flowchart LR
    UI["SwiftUI Views"] --> AppState["AudioAppState"]
    AppState --> Preview["ExportPreview"]
    Preview --> Job["ExportJob"]
    AppState --> Processor["AudioProcessor"]
    AppState --> Notify["NotificationManager"]
    Processor --> Builder["FFmpegCommandBuilder"]
    Processor --> Verifier["FFmpegBinaryVerifier"]
    Processor --> Runner["FFmpegProcessRunner"]
    Runner --> Helper["Bundled ffmpeg helper"]
```

## Project Structure

- `AudioPro/`: app source files
- `AudioProTests/`: test target
- `AudioPro.xcodeproj/`: Xcode project
- `docs/`: technical documentation and architecture diagrams
- `scripts/`: local release utilities

## Development

Open `AudioPro.xcodeproj` in Xcode and run the `AudioPro` scheme.

Minimum supported OS: `macOS 14.0`.

## GitHub Releases

Official release archives are built locally on macOS and then uploaded manually to GitHub Releases.

To produce a release archive locally:

```bash
./scripts/build-release.sh
```

The script builds the `Release` configuration, verifies the packaged `ffmpeg` helpers, creates a versioned ZIP archive, and writes `SHA256SUMS.txt`.

CI is used only for validation and does not publish end-user artifacts.

## Bundled FFmpeg

The app ships with two vendored `ffmpeg` helpers inside `AudioPro/`:

- `ffmpeg-binary-arm64`
- `ffmpeg-binary-x86_64`

The Xcode build phase verifies the SHA-256 of both source binaries before copying them into `AudioPro.app/Contents/Helpers/`.
At runtime the app launches the packaged helper only if it is executable and its code signature is valid.

Expected source SHA-256:

- `ffmpeg-binary-arm64`: `3b586ff896c0339e8fd574c143aaccac23c80789341e22d4202f8013a133d3a4`
- `ffmpeg-binary-x86_64`: `26b3ff92f64950f16be16eed88fe29064c2df516efdfac66cb8fa9abed030bdf`

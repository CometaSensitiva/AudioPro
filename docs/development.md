# Development and releases

Use the shared `AudioPro` scheme in Xcode 26 or later on macOS 26. Tests also compile with Xcode 27. The project resolves the official `argmaxinc/argmax-oss-swift` package exactly at `1.0.0`, with revisions recorded in `Package.resolved`.

## Model storage

Public releases use `INCLUDE_LOCAL_WHISPER_MODEL=NO`. The app offers a model download from Trascrizione and stores it in the app's sandbox, under `Library/Application Support/AudioPro/ModelCache/`. Recordings are processed locally; network access is used to download the model and tokenizer.

For personal builds, `INCLUDE_LOCAL_WHISPER_MODEL=YES` also copies these optional folders into the app bundle:

```text
~/Library/Application Support/AudioPro/LocalModels/
├── openai_whisper-large-v3-v20240930/
└── whisper-large-v3-tokenizer/
```

A missing local folder does not prevent the build. A sandboxed runtime does not automatically gain access to the host folder; it uses the bundled copy or its own cache.

## Package a release

```sh
./scripts/build-release.sh
```

`DERIVED_DATA_PATH` and `OUTPUT_DIR` can override the default `.derivedData/release` and `dist` directories. `RELEASE_VERSION=2.1.0` overrides the marketing version for a tag build.

The script builds both `arm64` and `x86_64`, checks their presence, signs the app and sandboxed FFmpeg helpers ad hoc, verifies their signatures, excludes model weights, then creates a ZIP and its SHA-256 checksum. This does not produce a Developer ID signature or notarization.

The current Xcode account has a Personal Team. Developer ID distribution requires an [Apple Developer Program team](https://developer.apple.com/developer-id/). If a paid team becomes available, replace the ad-hoc signing stage with Developer ID signing and notarization before distributing that build. Credentials belong in repository secrets, never in source control.

The Release workflow runs on `macos-26`. A manual run builds and retains artifacts without creating a release. Pushing a `v*` tag publishes the release after its test and packaging steps succeed; release notes come from `docs/releases/<tag>.md` when present. Review and approve the source, tag and notes before pushing the tag.

## FFmpeg

The build verifies the SHA-256 of the two vendored binaries before packaging. Runtime code checks the packaged helper's signature before launching it. Original source hashes:

- `ffmpeg-binary-arm64`: `3b586ff896c0339e8fd574c143aaccac23c80789341e22d4202f8013a133d3a4`
- `ffmpeg-binary-x86_64`: `26b3ff92f64950f16be16eed88fe29064c2df516efdfac66cb8fa9abed030bdf`

WhisperKit license notices are included in `AudioPro/Resources/ThirdPartyNotices/` and copied into the app.

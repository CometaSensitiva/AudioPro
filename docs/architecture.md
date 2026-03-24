# AudioPro Architecture

AudioPro is a sandboxed macOS app built around a small set of focused layers:

- SwiftUI views render the Tahoe-style interface and route user actions.
- `AudioAppState` owns UI state, file selection, export orchestration, and progress propagation.
- `ExportPreview` derives export feasibility and the final `ExportJob`.
- `AudioProcessor` orchestrates ffmpeg resolution, command building, helper verification, and process execution.
- A bundled `ffmpeg` helper performs the actual media transformation.

## High-level component map

```mermaid
flowchart TD
    subgraph UI["SwiftUI layer"]
        Sidebar["SidebarView"]
        Detail["DetailView"]
        Inspector["CompressionInspectorView"]
    end

    subgraph State["State and domain"]
        AppState["AudioAppState"]
        Preview["ExportPreview"]
        AudioFile["AudioFile"]
        Job["ExportJob"]
    end

    subgraph Processing["Processing layer"]
        Processor["AudioProcessor"]
        Builder["FFmpegCommandBuilder"]
        Verifier["FFmpegBinaryVerifier"]
        Runner["FFmpegProcessRunner"]
    end

    subgraph Runtime["External runtime"]
        Helper["Bundled ffmpeg helper"]
        Notify["NotificationManager"]
        Files["User-selected files"]
    end

    Sidebar --> AppState
    Detail --> AppState
    Inspector --> AppState
    AppState --> AudioFile
    AppState --> Preview
    Preview --> Job
    AppState --> Processor
    AppState --> Notify
    Processor --> Builder
    Processor --> Verifier
    Processor --> Runner
    Runner --> Helper
    AudioFile --> Files
```

## Simplified UML / type relationships

```mermaid
classDiagram
    class AudioFile {
        +UUID id
        +URL url
        +TimeInterval? duration
        +Int64? fileSize
        +String? codec
        +MetadataState metadataState
        +Bool isVideo
    }

    class AudioAppState {
        +[AudioFile] audioFiles
        +AudioFile? selectedFile
        +CompressionSettings compression
        +ProcessingState processingState
        +ExportPreview exportPreview
        +startExport(outputURL)
        +cancelExport()
        +rename(file, newName)
    }

    class ExportPreview {
        +ExportValidation validation
        +ExportJob? exportJob
        +ExportMode effectiveExportMode
        +Bool isVideoCompressionEligible
        +String compressionSummary
        +make(files, compression) ExportPreview
    }

    class ExportJob {
        <<enumeration>>
        audio
        videoCompressed
    }

    class AudioProcessor {
        <<actor>>
        +process(fileURLs, outputURL, job, estimatedTotalDuration, progressCallback)
        +cancel()
    }

    class FFmpegCommandBuilder {
        +makeArguments(fileURLs, outputURL, job) [String]
    }

    class FFmpegBinaryVerifier {
        +verifyRuntimeBinary(path, bundleURL) Bool
        +verifyVendoredBinary(path) Bool
    }

    class FFmpegProcessRunner {
        <<actor>>
        +run(path, arguments, inputCount, estimatedTotalDuration, progressCallback)
        +cancel()
    }

    class NotificationManager {
        +notifyExportFinished(outputURL)
        +configure()
    }

    AudioAppState --> AudioFile
    AudioAppState --> ExportPreview
    ExportPreview --> ExportJob
    AudioAppState --> AudioProcessor
    AudioAppState --> NotificationManager
    AudioProcessor --> FFmpegCommandBuilder
    AudioProcessor --> FFmpegBinaryVerifier
    AudioProcessor --> FFmpegProcessRunner
```

## Export sequence

```mermaid
sequenceDiagram
    actor User
    participant DetailView
    participant AudioAppState
    participant ExportPreview
    participant AudioProcessor
    participant FFmpegBinaryVerifier
    participant FFmpegCommandBuilder
    participant FFmpegProcessRunner
    participant ffmpeg
    participant NotificationManager

    User->>DetailView: Click Export
    DetailView->>AudioAppState: startExport(outputURL)
    AudioAppState->>ExportPreview: make(files, compression)
    ExportPreview-->>AudioAppState: ExportJob + validation
    AudioAppState->>AudioProcessor: process(fileURLs, outputURL, job, totalDuration)
    AudioProcessor->>FFmpegBinaryVerifier: verifyRuntimeBinary(...)
    AudioProcessor->>FFmpegCommandBuilder: makeArguments(...)
    AudioProcessor->>FFmpegProcessRunner: run(path, arguments, ...)
    FFmpegProcessRunner->>ffmpeg: Launch Process
    ffmpeg-->>FFmpegProcessRunner: stdout/stderr progress
    FFmpegProcessRunner-->>AudioAppState: progressCallback(progress)
    FFmpegProcessRunner-->>AudioProcessor: success / failure
    AudioProcessor-->>AudioAppState: Result
    AudioAppState->>NotificationManager: notifyExportFinished(outputURL)
```

## Processing state machine

```mermaid
stateDiagram-v2
    [*] --> idle
    idle --> running: startExport
    running --> completed: export success
    running --> failed: export failure
    running --> idle: cancelExport
    completed --> idle: settings/files change
    failed --> idle: settings/files change
```

## Sandbox and file access notes

- The app runs with App Sandbox enabled.
- The main app entitlement grants `com.apple.security.files.user-selected.read-write`.
- Imported files can be security-scoped; `AudioFile` currently keeps that capability alive for the lifetime of the model object.
- The bundled `ffmpeg` helper inherits the sandbox and is packaged inside `AudioPro.app/Contents/Helpers/`.

## Export pipeline details

- `AudioFile` loads metadata asynchronously with AVFoundation and exposes duration, size, codec, and `isVideo`.
- `ExportPreview` is the decision layer:
  - validates the current selection,
  - computes bitrate and size estimates for audio exports,
  - resolves the effective export mode,
  - emits an `ExportJob`.
- `AudioProcessor` does not decide *what* to export; it executes a precomputed `ExportJob`.
- `FFmpegCommandBuilder` keeps argument generation deterministic and separately testable.
- `FFmpegProcessRunner` owns `Process`, progress parsing, cancellation, and bounded stderr/stdout retention through `ProcessLogTail`.

## ffmpeg helper trust model

- Two vendored helpers are stored in the repository:
  - `ffmpeg-binary-arm64`
  - `ffmpeg-binary-x86_64`
- The Xcode build phase verifies their SHA-256 values before copying them into the app bundle.
- Runtime verification accepts:
  - vendored source binaries only if the SHA-256 matches;
  - packaged helpers only if the code signature is valid.
- This is sufficient for a GitHub-distributed personal project, but it is not a substitute for notarization or a full release-signing pipeline.

## Local release pipeline

```mermaid
flowchart LR
    Code["Committed source"] --> Build["./scripts/build-release.sh"]
    Build --> ReleaseApp["Release build of AudioPro.app"]
    ReleaseApp --> Verify["Verify app and ffmpeg helper signatures"]
    Verify --> Zip["Create AudioPro-<version>-macOS.zip"]
    Zip --> Checksums["Generate SHA256SUMS.txt"]
    Checksums --> Upload["Upload assets to GitHub Releases"]
```

## Distribution constraints

- Releases are built locally on macOS, then uploaded manually to GitHub Releases.
- CI validates build and tests only; it does not publish end-user artifacts.
- Without Apple Developer notarization, end users must use the standard Gatekeeper override flow on first launch.

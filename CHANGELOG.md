# Changelog

All notable changes to this project will be documented in this file.

## [2.1.0] - 2026-10-10

- Download Whisper Large v3 from the app on first use; public archives contain no model weights.
- Preserve existing destinations until exports and transcript files finish successfully, and clean up cancelled work.
- Restrict FFmpeg inputs to local files and improve cancellation and error reporting.
- Align the export and transcription queues, settings and progress bars; keep transcript space beside the video player.
- Fix the layout loop at the start of export and transcription on macOS 26.
- Drag recordings straight from Voice Memos or Finder onto any section; drop a recording and its SRT together in the player.
- Use the system window background and native sidebar, distinct section icons and consistent add buttons.
- Build universal Apple Silicon/Intel ZIP archives and checksums through the GitHub release workflow.

## [2.0.0] - 2026-06-11

- **Breaking**: raised the minimum supported OS to `macOS 26` and removed the Material compatibility layer; the design system is native Liquid Glass only.
- Merged TranscriptPlayer into the AudioPro app as the `Trascrizione` sidebar section; the standalone target, scheme and CI steps were removed.
- New unified navigation: sections sidebar with the export file queue, active search filter, playback that survives section switches (`PlayerModel`).
- Replaced the always-on animated waveform background with a static `MeshGradient` ambient backdrop plus a state-driven waveform (animates only during playback/export, respects Reduce Motion, ~0% idle CPU).
- Glass now lives only on the functional layer: morphing player transport bar and floating export status capsule; content uses materials and tint fills.
- Moved the Space transport shortcut to a window-level key equivalent so it works regardless of sidebar focus.
- Added a clear button to the Trascrizione section: unloads media and transcript in one gesture (the transport bar morphs back to the invite capsule).
- The video player now sizes itself on the track's real aspect ratio (rotation-aware) up to 480pt tall, instead of a fixed 260pt strip.
- Moved search to the top of the sidebar (`SearchFieldPlacement.sidebar`, the documented placement when search filters sidebar content); the inspector toggle is now the trailing-most toolbar item, adjacent to the panel it opens.
- Output size and savings estimates now cover the `Video compresso` mode (deterministic from the fixed HEVC 1500 kbps preset).
- Transport bar gains 5-second skip buttons and a native playback-speed menu (0.5×–2.5× via `AVPlayer.defaultRate`, pitch-corrected speech with the spectral algorithm).
- Word search in the transcript with ⌘F: Enter cycles matches and seeks to the cue moment, matches are highlighted in the list.
- Theatre treatment for the video canvas: 24pt continuous corners (fixed radius, stable while resizing) and a two-layer ambient/contact shadow.

## [1.0.0] - 2026-03-24

- Added a dedicated `Video compresso` export mode for single video sources.
- Preserved the audio-only workflow for both audio files and video-to-audio extraction.
- Split ffmpeg execution into dedicated processing components with improved testability.
- Added helper verification, bounded process log retention, and CI validation.
- Lowered the deployment target to `macOS 14+` while preserving the Tahoe-style UI through the compatibility layer.
- Added release documentation, architecture diagrams, screenshots, and a local release script for GitHub Releases.

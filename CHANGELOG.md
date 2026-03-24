# Changelog

All notable changes to this project will be documented in this file.

## [1.0.0] - 2026-03-24

- Added a dedicated `Video compresso` export mode for single video sources.
- Preserved the audio-only workflow for both audio files and video-to-audio extraction.
- Split ffmpeg execution into dedicated processing components with improved testability.
- Added helper verification, bounded process log retention, and CI validation.
- Lowered the deployment target to `macOS 14+` while preserving the Tahoe-style UI through the compatibility layer.
- Added release documentation, architecture diagrams, screenshots, and a local release script for GitHub Releases.

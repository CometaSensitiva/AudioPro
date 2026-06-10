# Decision Log

## 2026-06-11 — Transcript player as a separate app target

**Context**
The SRT viewer prototype should become a native macOS tool without adding playback and transcript state to AudioPro.

**Options**
- Add transcript playback inside AudioPro.
- Create a second application target in the existing Xcode project.
- Create a separate repository.

**Decision**
Create `TranscriptPlayer` as an independent target in `AudioPro.xcodeproj`, sharing only `LiquidGlassDesignSystem.swift`.

**Reason**
The apps keep separate responsibilities while reusing the established visual language and existing CI workspace.

**Trade-off**
The project file and CI contain additional targets, and the shared source is linked explicitly.

**Status**
Accepted

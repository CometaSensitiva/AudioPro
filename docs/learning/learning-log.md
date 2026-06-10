# Learning Log

## 2026-06-11 — Multiple macOS targets and synchronized folders

- Xcode synchronized folders automatically supply a target's own sources, while a source outside that folder needs an explicit `PBXFileReference` and Sources build entry.
- `membershipExceptions` removes files from a synchronized target; it is not a mechanism for including one external source.
- A parser-only logic test can compile the production parser sources directly and avoid launching an application test host.
- Sandboxed file import has two lifetimes: SRT access is released after reading, while AVPlayer media access must stay active for the playback session.
- An AVPlayer periodic observer must be installed once and removed during controller cleanup to avoid duplicate callbacks and leaks.

Related concepts: [[Git]], [[Branch]], [[SwiftUI]], [[AVPlayer]], [[App Sandbox]]

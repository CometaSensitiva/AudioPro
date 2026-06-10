# Learning Log

## 2026-06-11 — Multiple macOS targets and synchronized folders

- Xcode synchronized folders automatically supply a target's own sources, while a source outside that folder needs an explicit `PBXFileReference` and Sources build entry.
- `membershipExceptions` removes files from a synchronized target; it is not a mechanism for including one external source.
- A parser-only logic test can compile the production parser sources directly and avoid launching an application test host.
- Sandboxed file import has two lifetimes: SRT access is released after reading, while AVPlayer media access must stay active for the playback session.
- An AVPlayer periodic observer must be installed once and removed during controller cleanup to avoid duplicate callbacks and leaks.

Related concepts: [[Git]], [[Branch]], [[SwiftUI]], [[AVPlayer]], [[App Sandbox]]

## 2026-06-11 — Audit of the TranscriptPlayer target

- SwiftUI glass effects are `Material` backgrounds: over a flat window they render gray; they need a colored backdrop underneath to look like glass.
- `isPlaying` should be derived from `AVPlayer.timeControlStatus` (KVO publisher), never set optimistically in `play()`/`pause()`: a silent load failure would leave the UI stuck on "playing".
- A macOS app icon is an `AppIcon.appiconset` (10 PNG sizes + `Contents.json`) plus the `ASSETCATALOG_COMPILER_APPICON_NAME` build setting; an SVG source kept in `assets/` makes regeneration reproducible with ImageMagick.

Related concepts: [[AVPlayer]], [[SwiftUI]], [[Asset catalog]], [[Code review]]

## 2026-06-11 — Native Liquid Glass and HIG patterns

- Local types that shadow SDK symbols (`Glass`, `glassEffect`) compile silently but block native adoption: renaming the fallback (`LegacyGlass`) makes unqualified names resolve to the real SwiftUI API.
- Native `.glass`/`.glassProminent` are `PrimitiveButtonStyle`, not `ButtonStyle`: an availability branch between the two protocols must live in a `View` extension, not in a `ButtonStyle` static.
- macOS menu-backed shortcuts (HIG) work via `FocusedValues` + `@FocusedValue` in a `Commands` struct: the window publishes its actions with `.focusedSceneValue`, the menu reads them and disables items when no window is key.
- `safeAreaInset(edge: .bottom)` is the idiomatic way to build a Music-style floating player bar that content scrolls behind.

Related concepts: [[SwiftUI]], [[Liquid Glass]], [[HIG]], [[FocusedValues]]

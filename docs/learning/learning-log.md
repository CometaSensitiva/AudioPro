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

## 2026-06-11 — Unified app, ambient backdrop, native-only glass

- Liquid Glass belongs to the *functional layer* (toolbars, floating controls), never to content, and never stacks on other glass: the unsatisfying rendering came from a glass list under a glass bar over a moving background.
- Glass refracts what sits behind it: a rich but *static* backdrop (MeshGradient) renders better than a continuously animated one.
- `TimelineView(.animation(minimumInterval:paused:))` + phase derived from `context.date` replaces per-frame `@State` mutation: pausing freezes the canvas at zero CPU and Reduce Motion falls out naturally.
- With `PBXFileSystemSynchronizedRootGroup`, merging targets is mostly `git mv`: moved files compile automatically; the project file only needs *deletions* (enumerate the doomed object IDs, then strip lines/blocks).
- `GlassEffectContainer` + a shared `.glassEffectID` morphs one glass element between shapes (capsule ↔ transport bar) when the underlying state changes.
- Plain-key menu equivalents (Space, arrows) are checked *after* the first responder: a sidebar `List` can silently eat them. A `.keyboardShortcut` on a window-visible button is a window-level equivalent and wins.
- View-owned `@StateObject` dies with the view: hoisting player state into a root-owned model is what lets audio survive a section switch.

Related concepts: [[Liquid Glass]], [[SwiftUI]], [[TimelineView]], [[MeshGradient]], [[Xcode project format]], [[FocusedValues]]

## 2026-06-11 — Iterazione 3: transport, ricerca, lezioni sulle API nuove

- `ConcentricRectangle` risolve il raggio contro il *contenitore* (la finestra): per una superficie media che fluttua nel contenuto il raggio collassa al ridimensionamento. È pensata per controlli annidati vicino ai bordi; per i media canvas serve un raggio fisso (`RoundedRectangle` continuous).
- Velocità di riproduzione nativa: `AVPlayer.defaultRate` sopravvive a `play()` e ai riavvii; `AVPlayerItem.audioTimePitchAlgorithm = .spectral` mantiene il pitch del parlato corretto alle alte velocità.
- ⌘F come key equivalent *con modificatore* raggiunge il menu indipendentemente dal focus — i tasti nudi (Spazio, frecce) no: vengono consumati dal first responder.
- Una stima di output è derivabile in forma chiusa solo se il preset è fisso: `MB ≈ bitrate_kbps × durata / 8000` (video HEVC 1500 kbps, audio copy trascurabile).
- Le build CLI (`xcodebuild` da terminale) su questa macchina aggiungono `com.apple.provenance` a ogni file e il codesign fallisce con "detritus not allowed"; le build dalla GUI di Xcode non hanno il problema.

Related concepts: [[Liquid Glass]], [[AVPlayer]], [[SwiftUI]], [[Key equivalents]], [[Codesigning]]

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
Superseded (2026-06-11, see "Unified app with sidebar sections")

## 2026-06-11 — TranscriptPlayer visual identity and shared backdrop

**Context**
The first TranscriptPlayer build looked gray and shipped without an app icon.

**Options**
- Restyle with a new backdrop duplicated in the target.
- Share AudioPro's `WaveformBackdrop` and reuse the established look.

**Decision**
Share `WaveformHero.swift` with the TranscriptPlayer target (same mechanism as the design system) and add a dedicated "caption bubble" icon generated from `assets/transcript-player-icon.svg`.

**Reason**
Glass surfaces are Materials and only come alive over a colored backdrop; sharing the existing one guarantees visual coherence with zero duplication.

**Trade-off**
One more explicitly linked shared source in the project file.

**Status**
Superseded (2026-06-11, see "Ambient backdrop with state-driven waveform")

## 2026-06-11 — Native Liquid Glass adoption and HIG layout for TranscriptPlayer

**Context**
The shared design layer was a Material stub whose names shadowed the real macOS 26 APIs, and TranscriptPlayer kept all chrome inside the content view.

**Options**
- Qualify SDK symbols explicitly and keep the stubs.
- Rename live stubs to Legacy*, delete dead ones, branch on availability.

**Decision**
`liquidGlassSurface`/`liquidGlassControl`/`liquidGlassButtonStyle` now use native glass on macOS 26 and the byte-identical Material fallback below; TranscriptPlayer moved to a native toolbar, window title/subtitle, menu-backed shortcuts (⌘O, ⇧⌘O, Space, arrows) and a bottom player bar.

**Reason**
Unqualified names must resolve to real SDK symbols going forward; missing references fail loudly at build time. Both apps gain Tahoe styling from one shared file.

**Trade-off**
Native button metrics differ slightly from the legacy capsule on macOS 26; fallback rendering is unchanged.

**Status**
Accepted

## 2026-06-11 — Remediation della code review xhigh

**Context**
La review a sforzo alto sul branch ha confermato 12 finding: 4 di correttezza (race del seek, cue sovrapposte, trappola transcriptRevision, pannello sbagliato rifocalizzato), più cleanup ed efficienza.

**Options**
- Applicare tutto subito.
- Applicare correttezza + cleanup a basso rischio, rimandare gli interventi infrastrutturali.

**Decision**
Applicati i 4 fix di correttezza e i cleanup (formatTime condivisa, observer legato al media, API morte rimosse). Rimandati esplicitamente: riduzione fps/pausa del WaveformBackdrop (identità visiva di entrambe le app), matrix CI, Swift package per i sorgenti condivisi, isolamento di currentActions dai tick di currentTime (richiede @Observable).

**Reason**
I fix di correttezza sono piccoli e verificabili subito; gli interventi rimandati toccano infrastruttura o estetica condivisa e meritano una decisione dedicata.

**Trade-off**
La pubblicazione di focusedSceneValue resta a ~4 Hz durante la riproduzione (costo accettato e documentato nel codice).

**Status**
Accepted

## 2026-06-11 — Unified app with sidebar sections

**Context**
Two separate apps duplicated maintenance and visual identity work, and the export → re-listen-with-transcript flow crossed app boundaries. The Liquid Glass rendering in TranscriptPlayer was unsatisfying.

**Options**
- Keep two apps and only unify the design system.
- Merge TranscriptPlayer into AudioPro as a secondary window.
- Merge as a sidebar section in a single window (Landmarks-style).

**Decision**
Single AudioPro app with a `NavigationSplitView` sidebar holding two sections (Esportazione, Trascrizione) plus the file queue. Player state lives in `PlayerModel`, owned by the root so playback survives section switches. The TranscriptPlayer target, scheme and CI steps were removed; parser tests moved into `AudioProTests`.

**Reason**
One product to maintain, one design system, natural flow between the two features; `PBXFileSystemSynchronizedRootGroup` made the merge nearly free (only deletions in the project file).

**Trade-off**
TranscriptPlayer no longer exists as an independent app; plain-key menu shortcuts had to move to a window-level equivalent because the sidebar List can consume them (Space now lives on the play/pause button).

**Status**
Accepted

## 2026-06-11 — Ambient backdrop with state-driven waveform

**Context**
`WaveformBackdrop` ran a 30 fps `TimelineView`+`Canvas` loop even when idle (documented battery drain, deferred in the previous review), and glass refracting a continuously moving background rendered poorly.

**Options**
- Keep the animated waveform but pause it when the window is inactive.
- Static backdrop only, no waveform.
- Static ambient backdrop + waveform animated only when meaningful.

**Decision**
`AmbientBackdrop` (static `MeshGradient`, sidebar/detail styles, historical palette) + `ReactiveWaveform` (the 64-bar canvas, `paused:` TimelineView, phase derived from `context.date`, `accessibilityReduceMotion` respected). Active only during playback (Trascrizione) and export (Esportazione).

**Reason**
Idle CPU measured at ~0% after the change (was a continuous 30 fps loop); glass now refracts a rich-but-calm background per Apple guidance; the waveform gains meaning by reflecting actual audio activity.

**Trade-off**
The always-moving visual identity is gone at rest; the waveform is now a feedback element rather than a permanent decoration.

**Status**
Accepted

## 2026-06-11 — macOS 26 minimum, glass only on the functional layer

**Context**
The dual-path design system (native glass + Material fallback for macOS 14–15) doubled every styling decision, and glass was applied to content surfaces (transcript list, cards, sidebar rows), violating Apple's Liquid Glass guidance.

**Options**
- Keep macOS 14+ and replicate every new pattern in the fallback.
- Raise the minimum to macOS 26 and go native-only.

**Decision**
`MACOSX_DEPLOYMENT_TARGET = 26.0`. `LiquidGlassDesignSystem.swift` is tokens-only; glass is applied with native APIs at exactly two functional call sites: the player transport bar (with `GlassEffectContainer` + `glassEffectID` capsule↔bar morphing) and the floating export status capsule. Content uses materials and tint fills.

**Reason**
Glass belongs to the functional layer (toolbars, floating controls), never to content, and never stacks on other glass — the previous list-over-glass-under-glass-bar layout was the source of the unsatisfying rendering. Removing the fallback deleted ~150 lines and unlocked `MeshGradient`, `scrollEdgeEffectStyle`, `ToolbarSpacer` and morphing.

**Trade-off**
The app no longer runs on macOS 14–15 (CHANGELOG 1.0.0 had deliberately lowered the target).

**Status**
Accepted

## 2026-06-11 — Checkpoint 2.0.0 su main

**Context**
Il ciclo overhaul (app unificata, Liquid Glass corretto, sfondo ambient) più tre iterazioni di rifinitura (cestino player, video adattivo, search sidebar, stime video, transport avanzato, ricerca ⌘F) è completo e testato su `feature/unified-liquid-glass-ui`, con storia lineare su `main`.

**Options**
- Continuare ad accumulare feature sul branch.
- Fast-forward merge su main con tag, e pulizia dei branch contenuti.

**Decision**
`main` avanza in fast-forward fino alla punta del branch; tag annotato `v2.0.0`; eliminati i branch ormai contenuti (`feature/unified-liquid-glass-ui`, `feature/transcript-player`, `refactor-quality-hardening`); push su origin.

**Reason**
CHANGELOG e MARKETING_VERSION dicono già 2.0.0; un checkpoint nominato semplifica eventuali rollback e ripulisce la lista branch.

**Trade-off**
La prima run CI su main col deployment target a macOS 26 va osservata (il runner deve avere Xcode 26).

**Status**
Accepted

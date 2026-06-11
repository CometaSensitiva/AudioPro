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
Accepted

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

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
Superseded (2026-06-12, see "Dedicated transcription and playback sections")

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

## 2026-06-11 — Personal local Whisper model packaged at build time

**Context**
AudioPro deve diventare una suite di studio: merge delle registrazioni, trascrizione locale, e player con testo sincronizzato. Il modello WhisperKit/Core ML è già presente sul Mac e non deve entrare in Git.

**Options**
- Richiedere una configurazione manuale del percorso modello.
- Scaricare il modello automaticamente.
- Tenere una cartella locale `LocalModels/` accanto al progetto e copiarla nel bundle durante la build personale.

**Decision**
Usare `~/Library/Application Support/AudioPro/LocalModels/`, fuori dal repository e da iCloud, con `openai_whisper-large-v3-v20240930/` e `whisper-large-v3-tokenizer/`. La build copia i file in `AudioPro.app/Contents/Resources/WhisperModels/` quando presenti; se mancano, la build continua e l'app segnala che il modello non è incluso.

**Reason**
È la soluzione più diretta per un'app personale: niente configurazione runtime, niente download automatici, modello stabile e nessuna sincronizzazione iCloud di asset pesanti.

**Trade-off**
La build personale cresce di circa 1,5 GB. Un altro Mac deve ricreare solo la cartella in Application Support; WhisperKit viene risolto dalla dipendenza ufficiale bloccata nel lockfile. Lo user-script sandboxing è disattivato solo sul target AudioPro perché Xcode autorizza come output soltanto percorsi letterali, mentre `rsync` deve creare ricorsivamente il modello e file temporanei; l'App Sandbox a runtime resta attiva.

**Status**
Accepted

## 2026-06-13 — Official WhisperKit dependency and model-free public releases

**Context**
Il repository deve compilare da GitHub senza una copia locale non tracciata di WhisperKit, mentre il modello Core ML personale non deve essere pubblicato.

**Options**
- Vendorizzare sia package sia modello.
- Mantenere package e modello come dipendenze locali.
- Bloccare il package ufficiale e rendere opzionale solo il modello personale.

**Decision**
Usare `argmaxinc/argmax-oss-swift` esattamente alla versione `1.0.0`, tracciare `Package.resolved` e le note di licenza, mantenere il modello in Application Support e controllarne il packaging con `INCLUDE_LOCAL_WHISPER_MODEL`. Le build normali usano `YES`; `build-release.sh` forza `NO` e rifiuta archivi contenenti `WhisperModels`.

**Reason**
Il codice resta riproducibile e legalmente accompagnato dalle notice, mentre GitHub e le release pubbliche non ricevono il modello da circa 1,5 GB.

**Trade-off**
La trascrizione non è disponibile nelle release pubbliche finché non verrà progettato un download o import esplicito del modello.

**Status**
Accepted

## 2026-06-12 — Dedicated transcription and playback sections

**Context**
Local Whisper processing, output selection, playback, and SRT reading had been placed in the same player model and screen, making progress, cancellation, and the study workflow unclear.

**Options**
- Keep one combined player/transcription section.
- Add a transcription panel inside Esportazione.
- Use three explicit sections coordinated by a root session.

**Decision**
Use Esportazione → Trascrizione → Riproduzione. `AppSession` owns independent export, transcription, and player models. Handoffs are explicit through “Trascrivi output” and “Apri in Riproduzione”.

**Reason**
Each section has one primary task, while long-running transcription and playback survive navigation changes.

**Trade-off**
The app gains a coordinator and a dedicated transcription state machine; v1 intentionally supports only one active transcription and no persistent job history.

**Status**
Accepted

## 2026-06-13 — Native save flow and selectable transcript output

**Context**
The folder picker hid the output name under “Show Options”, and Finder date separators caused the fallback names `Trascrizione.srt` and `Trascrizione.txt`.

**Options**
- Keep the folder picker and custom accessory field.
- Move name and folder controls into the AudioPro screen.
- Use a native save panel with a visible prefilled name and keep format selection in AudioPro.

**Decision**
Use `NSSavePanel`, normalize `/` and `:` to `-`, and offer `SRT + TXT`, `Solo SRT`, and `Solo TXT`. Playback handoff is available only when SRT is generated.

**Reason**
The flow follows the familiar macOS save interaction, keeps the format choice compact, and makes TXT-only output behavior explicit.

**Trade-off**
`TranscriptionResult` and the output writer must support optional files and selected-output conflict handling instead of assuming a fixed pair.

**Status**
Superseded

## 2026-06-13 — Folder authorization before local transcription

**Context**
`NSSavePanel` authorized only the selected output path. AudioPro writes hidden staged files and can produce both SRT and TXT, so App Sandbox denied sibling files in the destination directory after Whisper had already finished.

**Options**
- Write directly to one selected file and give up coordinated SRT/TXT staging.
- Show a separate save panel for every output.
- Edit the shared base name in AudioPro, then use a native folder panel to authorize the destination directory.

**Decision**
Use one `NSOpenPanel` to select the destination folder, show the prefilled output name in an accessory view disclosed by default, and probe write access before loading Whisper.

**Reason**
One folder authorization covers the selected outputs, temporary staging, backup, and rollback. An immediate probe prevents a long transcription from completing before a permission error is discovered.

**Trade-off**
The panel uses an always-visible accessory field because macOS has no save panel that grants directory-wide access while naming multiple sibling files. The multi-file transaction remains reliable under App Sandbox.

**Status**
Accepted

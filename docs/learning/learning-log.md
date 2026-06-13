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
- Con `PBXFileSystemSynchronizedRootGroup`, switch di branch e `git mv` eseguiti mentre Xcode è aperto possono generare copie con suffisso ` 2` che entrano subito in compilazione: chiudere il progetto durante operazioni Git pesanti e ricontrollare `git status` dopo.

Related concepts: [[Liquid Glass]], [[AVPlayer]], [[SwiftUI]], [[Key equivalents]], [[Codesigning]]

## 2026-06-11 — Modelli locali pesanti e build personali

- Un modello ML da ~1,5 GB non va messo nel repository dentro `Documents`: anche se Git lo ignora, iCloud/File Provider può sincronizzarlo e bloccare l'apertura del progetto. `~/Library/Application Support/AudioPro/LocalModels` evita entrambi i problemi.
- Il bundle dell'app è il punto giusto da cui caricare un modello senza configurazione utente: a runtime si usa `Bundle.main.resourceURL`, non un percorso assoluto sul Mac.
- Una build phase può essere tollerante: se `LocalModels/` manca, stampa una nota, pulisce l'output atteso e lascia continuare la build.
- Lo user-script sandbox di Xcode tratta gli output dichiarati come percorsi letterali, non come autorizzazioni ricorsive: non è adatto a `rsync` di un albero ML grande con file temporanei casuali. Disattivarlo sul solo target non disattiva l'App Sandbox dell'app.
- Nei callback `@Sendable`, una cattura `weak self` non va ricatturata direttamente da un `Task` concorrente: prima si crea un riferimento locale stabile, poi lo si invia al `MainActor`.
- Con App Sandbox, selezionare un audio concede accesso al file ma non garantisce la creazione di file fratelli nella stessa cartella. Se un'operazione produce sia `.srt` sia `.txt`, far scegliere la cartella concede esplicitamente l'accesso necessario a entrambi.
- Un package ufficiale bloccato a una versione esatta e accompagnato da `Package.resolved` rende la build riproducibile senza mantenere una copia locale non tracciata.
- Separare formattazione (`SRT/TXT`) da engine Whisper rende testabile la parte deterministica anche senza lanciare il modello.

Related concepts: [[Git ignore]], [[Xcode build phase]], [[Swift Package Manager]], [[Core ML]], [[WhisperKit]]

## 2026-06-12 — Trascrizione come workflow concorrente separato

- Un lavoro lungo deve vivere in un modello posseduto dalla root, non nella view: così continua quando cambia la sezione della sidebar.
- La cancellazione sicura combina `Task.cancel()`, un segnale cooperativo per WhisperKit e lo scaricamento dei modelli Core ML prima di tornare a `idle`.
- Due output correlati non vanno scritti direttamente uno dopo l'altro: staging, backup e rollback evitano coppie SRT/TXT incomplete.
- Un pannello nativo può scegliere una cartella e usare un accessory view per il nome base quando un'operazione produce più file.
- `applicationShouldTerminate` può restituire `.terminateLater` e rispondere solo dopo il cleanup asincrono.

Related concepts: [[Swift Concurrency]], [[App Sandbox]], [[State machine]], [[Transactional files]], [[WhisperKit]]

## 2026-06-13 — Native save panels and optional related outputs

- Finder can display `/` in a filename whose filesystem representation contains `:`; normalizing both separators avoids rejecting valid date-based names.
- `NSSavePanel.nameFieldStringValue` exposes the prefilled name directly, unlike an accessory view that may remain hidden under “Show Options”.
- Independent output choices are easier to model as one finite selection (`SRT + TXT`, `Solo SRT`, `Solo TXT`) than as booleans that could both become false.
- A transactional writer should build staging, conflict, backup, and rollback lists from the selected outputs; unselected sibling files must remain untouched.
- A TXT transcript contains no timestamps, so synchronized playback must require an SRT result.

Related concepts: [[AppKit]], [[App Sandbox]], [[Transactional files]], [[SwiftUI]], [[SRT]]

## 2026-06-13 — Security scope for multi-file output

- A security scope returned by `NSSavePanel` applies to the selected file path, not automatically to hidden staging files or sibling outputs.
- A transaction that may create SRT, TXT, backups, and temporary files needs explicit access to their containing folder.
- Expensive work should begin only after a real write probe succeeds; checking paths or permissions indirectly is not enough under App Sandbox.
- For multi-file output, a practical macOS flow is: show the shared name in an always-disclosed `NSOpenPanel` accessory, select the folder, validate access, then start processing.

Related concepts: [[AppKit]], [[App Sandbox]], [[Security-scoped URLs]], [[Transactional files]]

## 2026-06-13 — Avoiding state publication from SwiftUI updates

- A view callback such as `onReceive` should not turn one observed publication into a second `@Published` mutation while SwiftUI is updating that view.
- The player time and active subtitle belong to the same state layer: `PlayerModel` now subscribes to `PlayerController.currentTime` directly, while `PlayerView` only renders their values.
- Repeated “Publishing changes from within view updates” messages can reveal one feedback path running at timer frequency, not many independent failures.

Related concepts: [[SwiftUI]], [[Combine]], [[ObservableObject]], [[State management]]

## 2026-06-13 — Isolating native video rendering

- A crash whose first framework frames are inside `_AVKit_SwiftUI` can occur while SwiftUI constructs `VideoPlayer`, after AVFoundation has already accepted the media.
- A minimal `NSViewRepresentable` backed by AppKit `AVPlayerView` removes the failing SwiftUI bridge while preserving native inline and full-screen controls.
- Keeping the same `AVPlayer` instance preserves seeking, rate, time observation, subtitle synchronization, and compatibility with AudioPro's lower transport bar.

Related concepts: [[AVFoundation]], [[AVKit]], [[AVPlayerView]], [[NSViewRepresentable]], [[Crash reports]]

## 2026-06-13 — Reproducible WhisperKit and model-free public releases

- Pinning the official Swift package to an exact version and tracking `Package.resolved` separates source reproducibility from the much larger Core ML model.
- `INCLUDE_LOCAL_WHISPER_MODEL=YES` keeps personal builds convenient, while the release script forces `NO` and verifies both the app bundle and ZIP.
- A release check should fail closed: finding `WhisperModels` aborts archive creation instead of relying on a manual inspection.

Related concepts: [[Swift Package Manager]], [[Package.resolved]], [[Build settings]], [[Release engineering]]

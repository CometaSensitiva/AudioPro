import SwiftUI

struct PlayerView: View {
    @ObservedObject private var model: PlayerModel
    // Osservato direttamente: le @Published del controller (currentTime,
    // isPlaying...) invalidano la view senza passare dal modello.
    @ObservedObject private var playerController: PlayerController
    @State private var isScrubbing = false
    @State private var scrubValue: TimeInterval = 0
    @FocusState private var isSearchFieldFocused: Bool
    @Namespace private var glassNamespace

    init(model: PlayerModel) {
        self._model = ObservedObject(wrappedValue: model)
        self._playerController = ObservedObject(wrappedValue: model.playerController)
    }

    var body: some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) { playerBar }
            .toolbar { toolbarContent }
            .navigationSubtitle(playerController.mediaName ?? "Nessun media")
            .frame(minWidth: 460, minHeight: 540)
            .background {
                // Il glass ha bisogno di un fondo colorato dietro di sé;
                // la waveform si muove solo durante la riproduzione.
                ZStack {
                    AmbientBackdrop()
                    ReactiveWaveform(isActive: playerController.isPlaying, intensity: 0.7)
                }
                .ignoresSafeArea()
            }
            .focusedSceneValue(\.playerActions, currentActions)
    }

    private var content: some View {
        VStack(spacing: LiquidGlassDesign.spacing) {
            if model.isTranscriptSearchVisible {
                transcriptSearchBar
            }

            if playerController.hasVideo {
                PlayerVideoView(player: playerController.player)
                    .aspectRatio(playerController.videoAspectRatio ?? 16 / 9, contentMode: .fit)
                    // Il limite d'altezza va PRIMA di clip e ombre: così la view
                    // coincide col video e angoli/ombra cadono sui suoi bordi.
                    // Il centraggio a larghezza piena va DOPO, o riallarga la view.
                    .frame(maxHeight: 480)
                    .clipShape(RoundedRectangle(cornerRadius: LiquidGlassDesign.mediaCornerRadius, style: .continuous))
                    // "Theatre mode": ombra ambientale larga + ombra di
                    // contatto stretta, per staccare il video dallo sfondo.
                    .shadow(color: .black.opacity(0.22), radius: 28, x: 0, y: 14)
                    .shadow(color: .black.opacity(0.10), radius: 6, x: 0, y: 2)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, LiquidGlassDesign.spacing)
            }

            statusArea

            if model.cues.isEmpty {
                emptyTranscript
            } else {
                TranscriptListView(
                    cues: model.cues,
                    activeCueID: model.activeCueID,
                    matchIDs: Set(model.matchIDs),
                    currentMatchID: model.currentMatchID,
                    canSeek: playerController.hasMedia
                ) { cue in
                    playerController.seek(to: cue.start)
                    playerController.play()
                }
                .equatable()
            }
        }
        .padding([.horizontal, .top], LiquidGlassDesign.padding)
        .padding(.bottom, LiquidGlassDesign.spacing)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                model.chooseMedia()
            } label: {
                Label("Apri media", systemImage: "play.rectangle")
            }
            .labelStyle(.iconOnly)
            .help("Apri un file audio o video (⌘O)")

            Button {
                model.chooseSRT()
            } label: {
                Label("Apri SRT", systemImage: "captions.bubble")
            }
            .labelStyle(.iconOnly)
            .help("Apri una trascrizione SRT (⇧⌘O)")

            Button {
                model.startTranscriptSearch()
            } label: {
                Label("Cerca nella trascrizione", systemImage: "magnifyingglass")
            }
            .labelStyle(.iconOnly)
            .help("Cerca nella trascrizione (⌘F)")
            .disabled(model.cues.isEmpty)

            Button(role: .destructive) {
                model.clearAll()
            } label: {
                Label("Svuota", systemImage: "trash")
            }
            .labelStyle(.iconOnly)
            .help("Svuota media e trascrizione")
            .disabled(model.isEmpty)
        }
    }

    /// Campo di ricerca della trascrizione: layer contenuto (material, non
    /// glass). Enter = match successivo con seek; Esc chiude.
    private var transcriptSearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Cerca nella trascrizione…", text: $model.transcriptQuery)
                .textFieldStyle(.plain)
                .focused($isSearchFieldFocused)
                .onSubmit { model.nextMatch() }

            if model.transcriptQuery.isEmpty == false {
                Text(matchCounterLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Button {
                model.previousMatch()
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(model.matchIDs.isEmpty)
            .help("Match precedente")

            Button {
                model.nextMatch()
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(model.matchIDs.isEmpty)
            .help("Match successivo (⏎)")

            Button {
                model.closeTranscriptSearch()
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .help("Chiudi ricerca (Esc)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onExitCommand { model.closeTranscriptSearch() }
        .onAppear { isSearchFieldFocused = true }
    }

    private var matchCounterLabel: String {
        let matches = model.matchIDs
        guard matches.isEmpty == false else { return "0 risultati" }
        if let current = model.currentMatchID, let index = matches.firstIndex(of: current) {
            return "\(index + 1) di \(matches.count)"
        }
        return "\(matches.count) risultati"
    }

    /// Unico elemento glass della sezione: senza media è una capsula di invito,
    /// con media diventa la barra di trasporto (morphing via glassEffectID).
    private var playerBar: some View {
        GlassEffectContainer(spacing: 16) {
            if playerController.hasMedia {
                transportControls
                    .padding(.horizontal, LiquidGlassDesign.padding)
                    .padding(.vertical, 10)
                    .glassEffect(
                        .regular.interactive(),
                        in: .rect(cornerRadius: LiquidGlassDesign.controlCornerRadius, style: .continuous)
                    )
                    .glassEffectID("playerBar", in: glassNamespace)
            } else {
                Button {
                    model.chooseMedia()
                } label: {
                    Label("Apri media", systemImage: "play.rectangle")
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .capsule)
                .glassEffectID("playerBar", in: glassNamespace)
                .help("Apri un file audio o video (⌘O)")
            }
        }
        .padding(.horizontal, LiquidGlassDesign.padding)
        .padding(.bottom, LiquidGlassDesign.spacing)
        .animation(.smooth(duration: 0.35), value: playerController.hasMedia)
    }

    private var transportControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: LiquidGlassDesign.spacing) {
                Button {
                    playerController.seekBy(-5)
                } label: {
                    Image(systemName: "gobackward.5")
                }
                .buttonStyle(.borderless)
                .help("Indietro di 5 secondi (←)")
                .accessibilityLabel("Indietro di 5 secondi")

                Button {
                    playerController.togglePlayback()
                } label: {
                    Image(systemName: playerController.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 18)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                // Equivalente a livello finestra: vince sul first responder
                // (la List in sidebar consuma Spazio prima dei menu).
                .keyboardShortcut(.space, modifiers: [])
                .help(playerController.isPlaying ? "Pausa (Spazio)" : "Riproduci (Spazio)")
                .accessibilityLabel(playerController.isPlaying ? "Pausa" : "Riproduci")

                Button {
                    playerController.seekBy(5)
                } label: {
                    Image(systemName: "goforward.5")
                }
                .buttonStyle(.borderless)
                .help("Avanti di 5 secondi (→)")
                .accessibilityLabel("Avanti di 5 secondi")

                Text(displayTime.playerDisplayString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Slider(
                    value: Binding(
                        get: { displayTime },
                        set: { scrubValue = $0 }
                    ),
                    in: 0...max(playerController.duration, 1),
                    onEditingChanged: { editing in
                        if editing {
                            scrubValue = playerController.currentTime
                            isScrubbing = true
                        } else {
                            isScrubbing = false
                            playerController.seek(to: scrubValue)
                        }
                    }
                )
                .disabled(playerController.duration <= 0)
                .accessibilityLabel("Posizione di riproduzione")
                .accessibilityValue("\(displayTime.playerDisplayString) di \(playerController.duration.playerDisplayString)")

                Text(playerController.duration.playerDisplayString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Menu {
                    Picker("Velocità", selection: Binding(
                        get: { playerController.playbackRate },
                        set: { playerController.setPlaybackRate($0) }
                    )) {
                        ForEach(PlayerController.availableRates, id: \.self) { rate in
                            Text(Self.rateLabel(rate)).tag(rate)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Text(Self.rateLabel(playerController.playbackRate))
                        .font(.caption)
                        .monospacedDigit()
                }
                .fixedSize()
                .help("Velocità di riproduzione")
                .accessibilityLabel("Velocità di riproduzione")
            }

            HStack {
                Text(playerController.mediaName ?? "Nessun media selezionato")
                Spacer()
                Text(model.srtFileName.map { "\($0) · \(model.cues.count) segmenti" } ?? "Nessun SRT selezionato")
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }

    @ViewBuilder
    private var statusArea: some View {
        if let message = playerController.errorMessage ?? model.srtErrorMessage {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if !model.cues.isEmpty && !playerController.hasMedia {
            Text("La trascrizione è pronta. Seleziona un media per abilitare il salto tra i segmenti.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var emptyTranscript: some View {
        ContentUnavailableView {
            Label("Nessuna trascrizione", systemImage: "captions.bubble")
        } description: {
            Text("Apri un file .srt per visualizzare i segmenti sincronizzati.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var displayTime: TimeInterval {
        isScrubbing ? scrubValue : playerController.currentTime
    }

    private static func rateLabel(_ rate: Float) -> String {
        let number = Double(rate).formatted(.number.precision(.fractionLength(0...2)))
        return "\(number)×"
    }

    // Ricreata a ogni body (4×/s in riproduzione, currentTime è @Published su
    // un ObservableObject: l'invalidazione è a livello di oggetto). Isolare la
    // pubblicazione richiederebbe @Observable o uno split del controller —
    // rimandato, vedi decision log. Costo: alloc struct + rivalidazione menu.
    private var currentActions: PlayerActions {
        PlayerActions(
            isPlaying: playerController.isPlaying,
            hasMedia: playerController.hasMedia,
            canSearchTranscript: !model.cues.isEmpty,
            togglePlayback: { playerController.togglePlayback() },
            seekBy: { playerController.seekBy($0) },
            openMedia: { model.chooseMedia() },
            openSRT: { model.chooseSRT() },
            startTranscriptSearch: { model.startTranscriptSearch() }
        )
    }
}

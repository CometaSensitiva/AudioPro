import SwiftUI

struct PlayerView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var model: PlayerModel
    // Osservato direttamente: le @Published del controller (currentTime,
    // isPlaying...) invalidano la view senza passare dal modello.
    @ObservedObject private var playerController: PlayerController
    @State private var isScrubbing = false
    @State private var scrubValue: TimeInterval = 0
    @State private var transcriptSearchFocusRequest = UUID()
    // Il valore viene usato solo quando non esiste ancora una preferenza:
    // le scelte già salvate (incluso Teatro) restano invariate.
    @AppStorage("playerVideoSizeMode") private var videoSizeModeRaw = PlayerVideoSizeMode.medium.rawValue
    @Namespace private var glassNamespace

    init(model: PlayerModel) {
        self._model = ObservedObject(wrappedValue: model)
        self._playerController = ObservedObject(wrappedValue: model.playerController)
    }

    var body: some View {
        content
            .mediaDropDestination(includesTranscripts: true) { files in
                if let media = files.first(where: { $0.isTranscript == false }) {
                    playerController.loadMedia(from: media.url)
                }
                if let transcript = files.first(where: \.isTranscript) {
                    model.handleSRTImport(transcript.url)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { playerBar }
            .toolbar { toolbarContent }
            .navigationTitle("Riproduzione")
            .navigationSubtitle(playerController.mediaName ?? "Nessun file selezionato")
            // Il glass ha bisogno di un fondo colorato dietro di sé;
            // la waveform si muove solo durante la riproduzione.
            .sectionBackground(isActive: playerController.isPlaying, intensity: 0.3)
            .focusedSceneValue(\.audioProCommandContext, commandContext)
            .onAppear {
                if isTheaterMode && model.isTranscriptSearchVisible {
                    model.closeTranscriptSearch()
                }
            }
            .onChange(of: isTheaterMode) { _, isTheaterMode in
                if isTheaterMode && model.isTranscriptSearchVisible {
                    model.closeTranscriptSearch()
                }
            }
    }

    private var content: some View {
        GeometryReader { proxy in
            VStack(spacing: LiquidGlassDesign.spacing) {
                if model.isTranscriptSearchVisible {
                    transcriptSearchBar
                }

                if playerController.hasVideo {
                    videoStage(containerSize: proxy.size)
                }

                statusArea

                // In modalità Teatro il video prende tutta la scena:
                // la zona trascrizione resta nascosta.
                if isTheaterMode == false {
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
            }
            .padding([.horizontal, .top], LiquidGlassDesign.padding)
            .padding(.bottom, LiquidGlassDesign.spacing)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                model.chooseMedia()
            } label: {
                Label("Apri file…", systemImage: "play.rectangle")
            }
            .labelStyle(.iconOnly)
            .help("Apri un file audio o video (⌘O)")

            Button {
                model.chooseSRT()
            } label: {
                Label("Apri SRT…", systemImage: "captions.bubble")
            }
            .labelStyle(.iconOnly)
            .help("Apri un file SRT (⇧⌘O)")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            if playerController.hasVideo {
                videoSizeMenu
            }

            Button {
                startTranscriptSearch()
            } label: {
                Label("Cerca nella trascrizione", systemImage: "magnifyingglass")
            }
            .labelStyle(.iconOnly)
            .help(
                isTheaterMode
                    ? "La ricerca è disponibile fuori dalla modalità Teatro"
                    : "Cerca nella trascrizione (⌘F)"
            )
            .disabled(model.cues.isEmpty || isTheaterMode)

            Button(role: .destructive) {
                model.clearAll()
            } label: {
                Label("Svuota contenuti", systemImage: "trash")
            }
            .labelStyle(.iconOnly)
            .help("Rimuovi il file e la trascrizione")
            .disabled(model.isEmpty)
        }
    }

    private func videoStage(containerSize: CGSize) -> some View {
        let videoFrame = videoSizeMode.frame(
            in: containerSize,
            aspectRatio: playerController.videoAspectRatio ?? 16 / 9,
            // Fuori da Teatro la trascrizione mantiene sempre spazio leggibile.
            reservedHeight: isTheaterMode ? 0 : Self.minimumTranscriptHeight
        )

        return PlayerVideoView(player: playerController.player)
            .frame(width: videoFrame.width, height: videoFrame.height)
            .clipShape(RoundedRectangle(cornerRadius: LiquidGlassDesign.mediaCornerRadius, style: .continuous))
            // "Theatre mode": ombra ambientale larga + ombra di contatto stretta.
            .shadow(color: .black.opacity(0.22), radius: 28, x: 0, y: 14)
            .shadow(color: .black.opacity(0.10), radius: 6, x: 0, y: 2)
            .frame(maxWidth: .infinity)
            .padding(.bottom, LiquidGlassDesign.spacing)
            .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: videoSizeMode)
    }

    /// Dimensione del video come menu nella toolbar: non copre il contenuto
    /// del video e segue lo stesso schema degli altri comandi della sezione.
    private var videoSizeMenu: some View {
        Menu {
            Picker("Dimensione video", selection: Binding(
                get: { videoSizeMode },
                set: { selectVideoSizeMode($0) }
            )) {
                ForEach(PlayerVideoSizeMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label("Dimensione video", systemImage: "aspectratio")
        }
        .labelStyle(.iconOnly)
        .help("Dimensione video: \(videoSizeMode.displayName)")
    }

    private var isTheaterMode: Bool {
        playerController.hasVideo && videoSizeMode == .theater
    }

    /// Campo di ricerca della trascrizione: find bar del livello controllo,
    /// stesso componente glass della ricerca coda file. Enter = match
    /// successivo con seek; Esc chiude.
    private var transcriptSearchBar: some View {
        SearchField(
            placeholder: "Cerca nella trascrizione",
            text: $model.transcriptQuery,
            matchCounter: matchCounterLabel,
            onPrevious: { model.previousMatch() },
            onNext: { model.nextMatch() },
            isNavigationDisabled: model.matchIDs.isEmpty,
            onSubmit: { model.nextMatch() },
            onClose: { model.closeTranscriptSearch() },
            focusesOnAppear: true,
            focusRequest: transcriptSearchFocusRequest
        )
    }

    private func startTranscriptSearch() {
        guard model.cues.isEmpty == false, isTheaterMode == false else { return }
        model.startTranscriptSearch()
        transcriptSearchFocusRequest = UUID()
    }

    private var matchCounterLabel: String {
        let matches = model.matchIDs
        guard matches.isEmpty == false else { return "0 risultati" }
        if let current = model.currentMatchID, let index = matches.firstIndex(of: current) {
            return "\(index + 1) di \(matches.count)"
        }
        return matches.count == 1 ? "1 risultato" : "\(matches.count) risultati"
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
            }
            // Senza media l'azione "Apri file…" vive nell'empty state:
            // nessun secondo pulsante identico in basso.
        }
        .padding(.horizontal, LiquidGlassDesign.padding)
        .padding(.bottom, LiquidGlassDesign.spacing)
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: playerController.hasMedia)
    }

    private var transportControls: some View {
        VStack(spacing: 8) {
            ViewThatFits(in: .horizontal) {
                wideTransportControls
                compactTransportControls
            }

            transportMetadata
        }
    }

    private var wideTransportControls: some View {
        HStack(spacing: LiquidGlassDesign.spacing) {
            playbackButtons
            currentTimeLabel
            playbackSlider
            durationLabel
            playbackRateMenu
        }
        // Impedisce al layout largo di comprimere lo slider fino a sembrare
        // valido: sotto questa misura ViewThatFits sceglie quello compatto.
        .frame(minWidth: 560)
    }

    private var compactTransportControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: LiquidGlassDesign.spacing) {
                playbackButtons
                Spacer(minLength: LiquidGlassDesign.spacing)
                playbackRateMenu
            }

            HStack(spacing: 8) {
                currentTimeLabel
                playbackSlider
                durationLabel
            }
        }
    }

    private var playbackButtons: some View {
        HStack(spacing: LiquidGlassDesign.spacing) {
            Button {
                playerController.seekBy(-5)
            } label: {
                Image(systemName: "gobackward.5")
            }
            .buttonStyle(.borderless)
            .help("Indietro di 5 secondi")
            .accessibilityLabel("Indietro di 5 secondi")

            Button {
                playerController.togglePlayback()
            } label: {
                Image(systemName: playerController.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 18)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .help(playerController.isPlaying ? "Pausa" : "Riproduci")
            .accessibilityLabel(playerController.isPlaying ? "Pausa" : "Riproduci")

            Button {
                playerController.seekBy(5)
            } label: {
                Image(systemName: "goforward.5")
            }
            .buttonStyle(.borderless)
            .help("Avanti di 5 secondi")
            .accessibilityLabel("Avanti di 5 secondi")
        }
    }

    private var currentTimeLabel: some View {
        Text(displayTime.playerDisplayString)
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .fixedSize()
    }

    private var durationLabel: some View {
        Text(playerController.duration.playerDisplayString)
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .fixedSize()
    }

    private var playbackSlider: some View {
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
    }

    private var playbackRateMenu: some View {
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
        .accessibilityValue(Self.rateLabel(playerController.playbackRate))
    }

    private var transportMetadata: some View {
        HStack(spacing: LiquidGlassDesign.spacing) {
            metadataLabel(
                mediaMetadataLabel,
                accessibilityLabel: "File audio o video"
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            metadataLabel(
                transcriptMetadataLabel,
                accessibilityLabel: "File SRT"
            )
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func metadataLabel(_ value: String, accessibilityLabel: String) -> some View {
        Text(value)
            .lineLimit(1)
            .truncationMode(.middle)
            .help(value)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(value)
    }

    @ViewBuilder
    private var statusArea: some View {
        if let message = playerController.errorMessage {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    playerController.dismissError()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .help("Chiudi errore")
                .accessibilityLabel("Chiudi errore di caricamento")
            }
            .font(.caption)
            .foregroundStyle(LiquidGlassStatusColor.failure)
        } else if let message = model.srtErrorMessage {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(LiquidGlassStatusColor.failure)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if !model.cues.isEmpty && !playerController.hasMedia {
            Text("La trascrizione è pronta. Seleziona un file audio o video per abilitare il salto tra i segmenti.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var emptyTranscript: some View {
        if playerController.hasMedia {
            FeatureEmptyState(
                "Nessuna trascrizione",
                systemImage: "captions.bubble",
                message: "Apri un file SRT per seguire la registrazione con i segmenti sincronizzati."
            ) {
                Button("Apri SRT…") {
                    model.chooseSRT()
                }
            }
        } else {
            FeatureEmptyState(
                "Nessun file aperto",
                systemImage: AppSection.player.symbolName,
                message: "Trascina qui una registrazione e il suo file SRT, oppure aprili dai pulsanti."
            ) {
                Button("Apri file…") {
                    model.chooseMedia()
                }
                Button("Apri SRT…") {
                    model.chooseSRT()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private static let minimumTranscriptHeight: CGFloat = 220

    private var displayTime: TimeInterval {
        isScrubbing ? scrubValue : playerController.currentTime
    }

    private var videoSizeMode: PlayerVideoSizeMode {
        PlayerVideoSizeMode.mode(forStoredRawValue: videoSizeModeRaw)
    }

    private var mediaMetadataLabel: String {
        playerController.mediaName ?? "Nessun file selezionato"
    }

    private var transcriptMetadataLabel: String {
        guard let srtFileName = model.srtFileName else {
            return "Nessun file SRT selezionato"
        }
        return "\(srtFileName) · \(segmentCountLabel)"
    }

    private var segmentCountLabel: String {
        model.cues.count == 1 ? "1 segmento" : "\(model.cues.count) segmenti"
    }

    private func selectVideoSizeMode(_ mode: PlayerVideoSizeMode) {
        if mode == .theater && model.isTranscriptSearchVisible {
            model.closeTranscriptSearch()
        }

        if reduceMotion {
            videoSizeModeRaw = mode.rawValue
        } else {
            withAnimation(.smooth(duration: 0.28)) {
                videoSizeModeRaw = mode.rawValue
            }
        }
    }

    private static func rateLabel(_ rate: Float) -> String {
        let number = Double(rate).formatted(.number.precision(.fractionLength(0...2)))
        return "\(number)×"
    }

    private var commandContext: AudioProCommandContext {
        .player(
            openMedia: model.chooseMedia,
            openSRT: model.chooseSRT,
            canSearchTranscript: !model.cues.isEmpty && !isTheaterMode,
            searchTranscript: startTranscriptSearch,
            playback: AudioProCommandContext.Playback(
                isPlaying: playerController.isPlaying,
                hasMedia: playerController.hasMedia,
                togglePlayback: playerController.togglePlayback,
                seekBy: playerController.seekBy
            )
        )
    }
}

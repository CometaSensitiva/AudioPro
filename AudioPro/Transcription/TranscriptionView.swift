import SwiftUI
import UniformTypeIdentifiers

struct TranscriptionView: View {
    @EnvironmentObject private var playbackCommandBridge: PlaybackCommandBridge
    @ObservedObject var model: TranscriptionModel
    let onOpenInPlayback: (TranscriptionResult) -> Void
    @Binding var isInspectorPresented: Bool
    @State private var sourceFile: AudioFile?

    var body: some View {
        Group {
            if model.selectedMediaURL == nil {
                emptyState
            } else {
                // Stessa tabella di Esportazione: il file scelto è una riga,
                // le impostazioni stanno nell'inspector, l'azione nella barra.
                sourceTable
            }
        }
        .mediaDropDestination(isEnabled: model.canAcceptMedia) { files in
            if let file = files.first(where: { $0.isTranscript == false }) {
                model.selectMedia(file.url)
            }
        }
        .sectionBackground(
            isActive: model.state.activatesWaveform || model.modelDownloadState.isBusy,
            intensity: 0.28
        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            actionBar
        }
        .navigationTitle("Trascrizione")
        .navigationSubtitle(model.selectedMediaName ?? "Nessun file selezionato")
        .inspector(isPresented: $isInspectorPresented) {
            TranscriptionInspectorView(model: model)
                .inspectorColumnWidth(
                    min: LiquidGlassDesign.inspectorMinWidth,
                    ideal: LiquidGlassDesign.inspectorIdealWidth,
                    max: LiquidGlassDesign.inspectorMaxWidth
                )
        }
        .focusedSceneValue(\.audioProCommandContext, commandContext)
        .onChange(of: model.selectedMediaURL, initial: true) { _, url in
            sourceFile = url.map { AudioFile(url: $0) }
        }
        .onAppear {
            model.refreshModelAvailability()
            // Se il modello non è pronto, apro l'inspector col download.
            if model.isModelAvailable == false {
                isInspectorPresented = true
            }
        }
        .toolbar {
            // Stessa grammatica delle altre sezioni: a sinistra le azioni
            // per aprire, a destra quelle sul contenuto, poi l'inspector.
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    model.chooseMedia()
                } label: {
                    Label("Scegli file…", systemImage: "plus")
                }
                .labelStyle(.iconOnly)
                .help("Scegli un file audio o video")
                .disabled(model.state.isBusy)
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button(role: .destructive) {
                    model.clearSelection()
                } label: {
                    Label("Rimuovi file", systemImage: "trash")
                }
                .labelStyle(.iconOnly)
                .help("Rimuovi il file selezionato")
                .disabled(model.selectedMediaURL == nil || model.state.isBusy)
            }

            ToolbarSpacer(.flexible, placement: .primaryAction)

            ToolbarItem(placement: .primaryAction) {
                Button {
                    isInspectorPresented.toggle()
                } label: {
                    Label("Impostazioni", systemImage: "sidebar.trailing")
                }
                .labelStyle(.iconOnly)
                .help(isInspectorPresented ? "Nascondi impostazioni" : "Mostra impostazioni")
            }
        }
    }

    /// Empty state come in Esportazione: solo testo + azione, nessuna card.
    private var emptyState: some View {
        FeatureEmptyState(
            "Nessun file selezionato",
            systemImage: AppSection.transcription.symbolName,
            message: "Trascina qui una registrazione da Memo Vocali o dal Finder, oppure sceglila dal pulsante."
        ) {
            Button("Scegli file…") {
                model.chooseMedia()
            }
        }
    }

    private var sourceTable: some View {
        Table(of: AudioFile.self) {
            mediaFileColumns()
        } rows: {
            if let sourceFile {
                TableRow(sourceFile)
            }
        }
        .scrollContentBackground(.hidden)
        .tableStyle(.inset(alternatesRowBackgrounds: false))
    }

    @ViewBuilder
    private var actionBar: some View {
        if shouldShowActionBar {
            AudioProBottomGlassBar(isInteractive: actionBarIsInteractive, verticalPadding: 12) {
                actionBarContent
            }
            // Stessa larghezza della scheda del file: barra e contenuto allineati.
            .contentReadingWidth()
        }
    }

    @ViewBuilder
    private var actionBarContent: some View {
        if showsModelSetupInActionBar {
            modelSetupActionBarContent
        } else {
            transcriptionActionBarContent
        }
    }

    @ViewBuilder
    private var modelSetupActionBarContent: some View {
        switch model.modelDownloadState {
        case .idle, .completed:
            ResponsiveActionRow {
                FeatureNotice(
                    systemImage: "arrow.down.circle",
                    title: "Modello Whisper richiesto",
                    message: model.modelStatusMessage,
                    isSingleLine: true
                )
            } actions: {
                Button("Scarica il modello") {
                    model.startModelDownload()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.canDownloadModel == false)
            }
        case .downloading(let progress):
            ResponsiveActionRow {
                JobProgressLine(
                    title: "Download del modello in corso",
                    progress: progress,
                    systemImage: "arrow.down.circle",
                    message: "Puoi chiudere le impostazioni: il download continuerà in secondo piano."
                )
            } actions: {
                Button("Interrompi", role: .destructive) {
                    model.cancelModelDownload()
                }
                .buttonStyle(.bordered)
            }
        case .cancelling:
            ResponsiveActionRow {
                JobProgressLine(
                    title: "Interruzione del download",
                    progress: nil,
                    systemImage: "xmark.circle",
                    message: "AudioPro attende la chiusura sicura del download."
                )
            } actions: {
                EmptyView()
            }
        case .failed(let message):
            ResponsiveActionRow {
                FeatureNotice(
                    systemImage: "exclamationmark.triangle.fill",
                    title: "Download del modello non riuscito",
                    message: message,
                    tint: LiquidGlassStatusColor.failure,
                    isSingleLine: true
                )
            } actions: {
                Button("Riprova il download") {
                    model.startModelDownload()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.canDownloadModel == false)
            }
        }
    }

    @ViewBuilder
    private var transcriptionActionBarContent: some View {
        switch model.state {
        case .selectingDestination:
            ResponsiveActionRow {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Scegli la destinazione", systemImage: "folder.badge.plus")
                        .font(.callout.weight(.medium))
                    Text("Completa oppure annulla il pannello macOS aperto.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } actions: {
                EmptyView()
            }
        case .loadingModel:
            ResponsiveActionRow {
                JobProgressLine(
                    title: "Caricamento del modello",
                    progress: nil,
                    systemImage: "cpu",
                    message: "La trascrizione inizierà automaticamente appena il modello sarà pronto."
                )
            } actions: {
                Button("Interrompi", role: .destructive) {
                    model.cancel()
                }
                .buttonStyle(.bordered)
            }
        case .transcribing(let progress):
            ResponsiveActionRow {
                JobProgressLine(
                    title: "Trascrizione in corso",
                    progress: progress,
                    systemImage: "waveform.and.mic",
                    message: "Puoi cambiare sezione: il lavoro continuerà in secondo piano."
                )
            } actions: {
                Button("Interrompi", role: .destructive) {
                    model.cancel()
                }
                .buttonStyle(.bordered)
            }
        case .cancelling:
            ResponsiveActionRow {
                JobProgressLine(
                    title: "Interruzione in corso",
                    progress: nil,
                    systemImage: "xmark.circle",
                    message: "AudioPro sta chiudendo il processo e rimuovendo i file temporanei."
                )
            } actions: {
                EmptyView()
            }
        case .completed(let result):
            ResponsiveActionRow {
                Label("Trascrizione completata", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(LiquidGlassStatusColor.success)
            } actions: {
                HStack(spacing: 8) {
                    Button("Mostra nel Finder") {
                        model.showResultInFinder()
                    }
                    .buttonStyle(.bordered)

                    if result.canOpenInPlayback {
                        Button("Apri in Riproduzione") {
                            onOpenInPlayback(result)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        case .idle:
            ResponsiveActionRow {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Pronto per la trascrizione", systemImage: "waveform.and.mic")
                        .font(.callout.weight(.medium))
                    Text("\(model.outputSelection.displayName) · Whisper Large v3 · sul Mac")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } actions: {
                Button("Trascrivi…") {
                    model.startTranscription()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.canStart == false)
            }
        case .failed(let message):
            ResponsiveActionRow {
                FeatureNotice(
                    systemImage: "exclamationmark.triangle.fill",
                    title: "Trascrizione non riuscita",
                    message: message,
                    tint: LiquidGlassStatusColor.failure,
                    isSingleLine: true
                )
            } actions: {
                Button("Riprova…") {
                    model.startTranscription()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.canStart == false)
            }
        }
    }

    private var shouldShowActionBar: Bool {
        if modelSetupNeedsPresentation && isInspectorPresented {
            return false
        }

        return model.selectedMediaURL != nil
            || model.state.isBusy
            || showsModelSetupInActionBar
    }

    private var showsModelSetupInActionBar: Bool {
        modelSetupNeedsPresentation && isInspectorPresented == false
    }

    /// Il download del modello vive nell'inspector quando è aperto e nella
    /// barra inferiore quando è chiuso: non esistono due comandi concorrenti.
    private var modelSetupNeedsPresentation: Bool {
        if model.modelDownloadState.isBusy {
            return true
        }
        guard model.isModelAvailable == false else { return false }
        switch model.state {
        case .idle, .failed:
            return true
        case .selectingDestination, .loadingModel, .transcribing, .cancelling, .completed:
            return false
        }
    }

    private var actionBarIsInteractive: Bool {
        if showsModelSetupInActionBar {
            switch model.modelDownloadState {
            case .downloading:
                return true
            case .idle, .failed:
                return model.canDownloadModel
            case .cancelling, .completed:
                return false
            }
        }

        return switch model.state {
        case .loadingModel, .transcribing, .completed:
            true
        case .idle, .failed:
            model.canStart
        case .selectingDestination, .cancelling:
            false
        }
    }

    private func abbreviatedDirectory(for url: URL) -> String {
        let path = url.deletingLastPathComponent().path(percentEncoded: false)
        // Nella sandbox NSHomeDirectory punta al container dell'app:
        // per abbreviare con ~ serve la home reale dell'utente.
        guard let entry = getpwuid(getuid()), let home = entry.pointee.pw_dir else {
            return path
        }
        let realHome = String(cString: home)
        guard path == realHome || path.hasPrefix(realHome + "/") else { return path }
        return "~" + path.dropFirst(realHome.count)
    }

    private var commandContext: AudioProCommandContext {
        .transcription(
            canChooseMedia: model.state.isBusy == false,
            chooseMedia: model.chooseMedia,
            playback: playbackCommandBridge.commandContext
        )
    }
}

nonisolated enum TranscriptionMediaSymbol {
    static func systemName(for url: URL) -> String {
        let resourceType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
        let extensionType = UTType(filenameExtension: url.pathExtension.lowercased())
        let type = resourceType ?? extensionType

        if type?.conforms(to: .movie) == true {
            return "video.fill"
        }
        return "waveform"
    }
}

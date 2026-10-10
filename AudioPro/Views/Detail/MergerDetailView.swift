import SwiftUI
import UniformTypeIdentifiers
import AppKit
import CoreTransferable

private struct QueueDragPayload: Codable, Transferable {
    let fileIDs: [UUID]

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .audioProQueueItem)
    }
}

private extension UTType {
    nonisolated static let audioProQueueItem = UTType(
        exportedAs: "com.michelemazza.audiopro.queue-item"
    )
}

enum ExportQueueContentState: Equatable {
    case emptyQueue
    case noSearchResults(query: String)
    case files

    init(fileCount: Int, filteredFileCount: Int, searchText: String) {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        if fileCount == 0 {
            self = .emptyQueue
        } else if query.isEmpty == false, filteredFileCount == 0 {
            self = .noSearchResults(query: query)
        } else {
            self = .files
        }
    }
}

struct MergerDetailView: View {
    @EnvironmentObject private var appState: AudioAppState
    @EnvironmentObject private var playbackCommandBridge: PlaybackCommandBridge
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let canTranscribeOutput: Bool
    let onTranscribeOutput: (URL) -> Void
    @State private var isQueueSearchVisible = false
    @State private var queueSearchFocusRequest = UUID()
    @State private var tableSelection = Set<AudioFile.ID>()
    @State private var activeAddFilesPanel: NSOpenPanel?

    var body: some View {
        VStack(spacing: 0) {
            if isQueueSearchVisible {
                queueSearchBar
                    .padding([.horizontal, .top], LiquidGlassDesign.padding)
            }

            detailContent
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: isQueueSearchVisible)
        .sectionBackground(isActive: appState.processingState.isBusy, intensity: 0.32)
        .safeAreaInset(edge: .bottom, spacing: 0) { exportActionBar }
        .navigationTitle("Esportazione")
        .inspector(isPresented: $appState.isInspectorPresented) {
            CompressionInspectorView()
                .inspectorColumnWidth(
                    min: LiquidGlassDesign.inspectorMinWidth,
                    ideal: LiquidGlassDesign.inspectorIdealWidth,
                    max: LiquidGlassDesign.inspectorMaxWidth
                )
        }
        .onDisappear(perform: handleDisappear)
        .focusedSceneValue(\.audioProCommandContext, commandContext)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                addButton
                voiceMemosButton
            }

            ToolbarItemGroup(placement: .primaryAction) {
                searchToggleButton
                clearButton
            }

            // Spinge l'inspector all'estremità destra della toolbar, sopra
            // la colonna dell'inspector, staccato dalla ricerca.
            ToolbarSpacer(.flexible, placement: .primaryAction)

            ToolbarItem(placement: .primaryAction) {
                inspectorToggleButton
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch queueContentState {
        case .emptyQueue:
            emptyState
        case .noSearchResults(let query):
            searchEmptyState(query: query)
        case .files:
            fileQueueTable
        }
    }

    private var queueContentState: ExportQueueContentState {
        ExportQueueContentState(
            fileCount: appState.audioFiles.count,
            filteredFileCount: appState.filteredFiles.count,
            searchText: appState.searchText
        )
    }

    /// Coda file come tabella stile Finder nel contenuto principale
    /// (Nome · Modificato · Dimensione · Tipo), selezione multipla.
    private var fileQueueTable: some View {
        Table(of: AudioFile.self, selection: $tableSelection) {
            mediaFileColumns()
        } rows: {
            ForEach(appState.filteredFiles) { file in
                if canReorderQueue {
                    TableRow(file)
                        .draggable(queueDragPayload(for: file))
                } else {
                    TableRow(file)
                }
            }
            .dropDestination(for: QueueDragPayload.self) { index, payloads in
                guard canReorderQueue else { return }
                appState.moveFiles(
                    withIDs: payloads.flatMap(\.fileIDs),
                    to: index
                )
            }
        }
        // Sfondo tabella trasparente: la waveform ambient resta visibile
        // dietro. Niente righe a colori alternati (zebra) che sporcano la vista.
        .scrollContentBackground(.hidden)
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .contextMenu(forSelectionType: AudioFile.ID.self) { ids in
            Button("Sposta su") {
                appState.moveFiles(withIDs: ids, by: -1)
            }
            .disabled(canMove(ids, by: -1) == false)

            Button("Sposta giù") {
                appState.moveFiles(withIDs: ids, by: 1)
            }
            .disabled(canMove(ids, by: 1) == false)

            Divider()

            Button("Rimuovi dalla coda", role: .destructive) {
                removeFiles(ids)
            }
            .disabled(ids.isEmpty || appState.canModifyQueue == false)
        }
        .onDeleteCommand {
            removeFiles(tableSelection)
        }
        .onChange(of: tableSelection) { _, newValue in
            syncSelection(newValue)
        }
        .onAppear {
            if let selected = appState.selectedFile {
                tableSelection = [selected.id]
            }
        }
    }

    private func syncSelection(_ ids: Set<AudioFile.ID>) {
        if let firstID = ids.first,
           let file = appState.audioFiles.first(where: { $0.id == firstID }) {
            appState.selectedFile = file
        } else if ids.isEmpty {
            appState.selectedFile = appState.audioFiles.first
        }
    }

    private func removeFiles(_ ids: Set<AudioFile.ID>) {
        guard appState.canModifyQueue else { return }
        let visibleIDs = Set(appState.filteredFiles.map(\.id))
        let removableIDs = ids.intersection(visibleIDs)
        let files = appState.audioFiles.filter { removableIDs.contains($0.id) }
        files.forEach { appState.remove($0) }
        tableSelection.subtract(removableIDs)
    }

    private var canReorderQueue: Bool {
        appState.canModifyQueue
            && appState.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func queueDragPayload(for file: AudioFile) -> QueueDragPayload {
        guard tableSelection.contains(file.id) else {
            return QueueDragPayload(fileIDs: [file.id])
        }

        let selectedIDsInQueueOrder = appState.audioFiles.compactMap { queuedFile in
            tableSelection.contains(queuedFile.id) ? queuedFile.id : nil
        }
        return QueueDragPayload(fileIDs: selectedIDsInQueueOrder)
    }

    private func canMove(_ ids: Set<AudioFile.ID>, by offset: Int) -> Bool {
        guard canReorderQueue, ids.isEmpty == false else { return false }
        let selectedIndexes = appState.audioFiles.indices.filter {
            ids.contains(appState.audioFiles[$0].id)
        }
        guard let first = selectedIndexes.first,
              let last = selectedIndexes.last else { return false }
        return offset < 0 ? first > appState.audioFiles.startIndex : last < appState.audioFiles.index(before: appState.audioFiles.endIndex)
    }

    /// Find bar della coda file: stesso componente glass e stessa interazione
    /// (toggle da toolbar) della ricerca trascrizione in Riproduzione.
    private var queueSearchBar: some View {
        SearchField(
            placeholder: "Cerca nella coda file",
            text: $appState.searchText,
            onClose: closeQueueSearch,
            focusesOnAppear: true,
            focusRequest: queueSearchFocusRequest
        )
    }

    private func startQueueSearch() {
        isQueueSearchVisible = true
        queueSearchFocusRequest = UUID()
    }

    private func closeQueueSearch() {
        appState.searchText = ""
        isQueueSearchVisible = false
    }

    private var searchToggleButton: some View {
        Button {
            if isQueueSearchVisible {
                closeQueueSearch()
            } else {
                startQueueSearch()
            }
        } label: {
            Label("Cerca nella coda", systemImage: "magnifyingglass")
        }
        .labelStyle(.iconOnly)
        .help("Cerca nella coda file (⌘F)")
        .disabled(appState.audioFiles.isEmpty)
    }

    private var emptyState: some View {
        FeatureEmptyState(
            "Nessun file in coda",
            systemImage: "waveform",
            message: "Aggiungi uno o più file audio o video per preparare l’esportazione."
        ) {
            Button("Aggiungi file…") {
                addFiles()
            }
        }
    }

    private func searchEmptyState(query: String) -> some View {
        FeatureEmptyState(
            "Nessun file trovato",
            systemImage: "doc.text.magnifyingglass",
            message: "Nessun file in coda corrisponde a “\(query)”."
        ) {
            Button("Cancella ricerca") {
                closeQueueSearch()
            }
        }
    }

    /// Punto stabile dell'azione primaria: prima dell'avvio mostra Esporta,
    /// durante il job mostra progresso e al termine le azioni successive.
    @ViewBuilder
    private var exportActionBar: some View {
        if appState.audioFiles.isEmpty == false || appState.processingState != .idle {
            AudioProBottomGlassBar(isInteractive: exportActionBarIsInteractive, verticalPadding: 12) {
                exportActionBarContent
            }
        }
    }

    @ViewBuilder
    private var exportActionBarContent: some View {
        switch appState.processingState {
        case .idle:
            exportReadyRow
        case .running, .completed, .failed:
            exportStatusRow
        }
    }

    private var exportStatusRow: some View {
        StatusBar(
            state: appState.processingState,
            onCancel: appState.cancelExport,
            onTranscribeOutput: transcribeOutputAction,
            onShowResult: showExportResultAction,
            onRetry: retryExportAction
        )
    }

    private var exportReadyRow: some View {
        ResponsiveActionRow {
            VStack(alignment: .leading, spacing: 3) {
                Label("\(appState.audioFiles.count) file in coda", systemImage: "rectangle.stack")
                    .font(.callout.weight(.medium))

                Text(exportReadyDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        } actions: {
            Button("Esporta…", action: startExportFlow)
                .buttonStyle(.borderedProminent)
                .disabled(appState.isExportActionEnabled == false)
                .help(appState.exportDisabledReason ?? "Scegli nome e cartella del file esportato")
        }
    }

    private var exportReadyDetail: String {
        if appState.isExportActionEnabled == false, let reason = appState.exportDisabledReason {
            return reason
        }
        return appState.exportPreview.compressionSummary
    }

    private var exportActionBarIsInteractive: Bool {
        switch appState.processingState {
        case .running:
            true
        case .completed:
            transcribeOutputAction != nil || showExportResultAction != nil
        case .idle:
            appState.isExportActionEnabled
        case .failed:
            appState.audioFiles.isEmpty == false
        }
    }

    private var addButton: some View {
        Button {
            addFiles()
        } label: {
            Label("Aggiungi file…", systemImage: "rectangle.stack.badge.plus")
        }
        .labelStyle(.iconOnly)
        .help("Aggiungi file audio o video")
        .disabled(canPresentAddFilesPanel == false)
    }

    private var transcribeOutputAction: (() -> Void)? {
        guard canTranscribeOutput,
              let outputURL = appState.lastCompletedOutputURL else { return nil }
        return {
            onTranscribeOutput(outputURL)
        }
    }

    private var showExportResultAction: (() -> Void)? {
        guard let outputURL = appState.lastCompletedOutputURL else { return nil }
        return {
            NSWorkspace.shared.activateFileViewerSelecting([outputURL])
        }
    }

    private var retryExportAction: (() -> Void)? {
        guard appState.audioFiles.isEmpty == false else { return nil }
        return startExportFlow
    }

    private var voiceMemosButton: some View {
        Button {
            openVoiceMemosLibrary()
        } label: {
            Label("Memo Vocali", systemImage: "mic.fill")
        }
        .labelStyle(.iconOnly)
        .help("Apri Memo Vocali")
    }

    private var clearButton: some View {
        Button(role: .destructive) {
            closeQueueSearch()
            appState.clearAll()
        } label: {
            Label("Svuota coda", systemImage: "trash")
        }
        .labelStyle(.iconOnly)
        .help("Rimuovi tutti i file dalla coda")
        .disabled(appState.audioFiles.isEmpty || appState.canModifyQueue == false)
    }

    private var inspectorToggleButton: some View {
        Button {
            appState.isInspectorPresented.toggle()
        } label: {
            Label("Impostazioni", systemImage: "sidebar.trailing")
        }
        .labelStyle(.iconOnly)
        .help(appState.isInspectorPresented ? "Nascondi impostazioni" : "Mostra impostazioni")
    }
    
    private func startExportFlow() {
        guard appState.isExportActionEnabled else { return }
        let defaults = appState.exportDestinationDefaults
        let panel = NSSavePanel()
        panel.allowedContentTypes = defaults.allowedContentTypes
        panel.nameFieldStringValue = defaults.fileName
        panel.message = defaults.message
        panel.title = "Esporta"
        panel.prompt = "Esporta"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                appState.startExport(to: url)
            }
        }
    }
    
    private func addFiles() {
        guard activeAddFilesPanel == nil else {
            activeAddFilesPanel?.makeKeyAndOrderFront(nil)
            return
        }
        guard appState.canModifyQueue else { return }

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.audio, .movie]
        panel.title = "Aggiungi file"
        panel.prompt = "Aggiungi"
        activeAddFilesPanel = panel

        panel.begin { [weak panel] response in
            guard let panel else { return }
            guard activeAddFilesPanel === panel else { return }
            activeAddFilesPanel = nil
            guard response == .OK else { return }

            let newFiles = panel.urls.map { url in
                let securityScopedURL = url.startAccessingSecurityScopedResource() ? url : nil
                return AudioFile(url: url, securityScopedURL: securityScopedURL)
            }
            appState.addFiles(newFiles)
        }
    }

    private var canPresentAddFilesPanel: Bool {
        appState.canModifyQueue && activeAddFilesPanel == nil
    }

    private func handleDisappear() {
        closeQueueSearch()
        activeAddFilesPanel?.cancel(nil)
        activeAddFilesPanel = nil
    }
    
    private func openVoiceMemosLibrary() {
        let url = URL(fileURLWithPath: "/System/Applications/VoiceMemos.app")
        NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
    }

    private var commandContext: AudioProCommandContext {
        .export(
            canAddFiles: canPresentAddFilesPanel,
            addFiles: addFiles,
            canSearchQueue: appState.audioFiles.isEmpty == false,
            searchQueue: startQueueSearch,
            playback: playbackCommandBridge.commandContext
        )
    }
}

struct MergerDetailView_Previews: PreviewProvider {
    @MainActor
    static var previews: some View {
        MergerDetailView(
            canTranscribeOutput: true,
            onTranscribeOutput: { _ in }
        )
            .environmentObject(PreviewSamples.appState())
            .environmentObject(
                PlaybackCommandBridge(playerController: PlayerController())
            )
    }
}

import AppKit
import Combine
import Foundation

@MainActor
final class TranscriptionModel: ObservableObject {
    @Published private(set) var selectedMediaURL: URL?
    @Published private(set) var state: LocalTranscriptionState = .idle
    @Published private(set) var modelDownloadState: WhisperModelDownloadState = .idle
    @Published private(set) var modelAvailability: WhisperModelStore.Availability
    @Published var outputSelection: TranscriptionOutputSelection = .srtAndTxt

    private let engine: any TranscriptionProcessing
    private let outputWriter: any TranscriptionOutputWriting
    private let destinationPicker: any TranscriptionDestinationSelecting
    private let fileSelectionService: FileSelectionService
    private let availabilityProvider: @Sendable () -> WhisperModelStore.Availability
    private let modelDownloader: any WhisperModelDownloading
    private var operationTask: Task<Void, Never>?
    private var modelDownloadTask: Task<Void, Never>?
    private var modelDownloadGeneration: UUID?

    convenience init() {
        self.init(
            engine: WhisperTranscriptionEngine(),
            outputWriter: TranscriptionOutputWriter(),
            destinationPicker: TranscriptionDestinationPicker(),
            fileSelectionService: FileSelectionService(),
            availabilityProvider: { WhisperModelStore.availability() },
            modelDownloader: WhisperModelDownloader()
        )
    }

    init(
        engine: any TranscriptionProcessing,
        outputWriter: any TranscriptionOutputWriting,
        destinationPicker: any TranscriptionDestinationSelecting,
        fileSelectionService: FileSelectionService,
        availabilityProvider: @escaping @Sendable () -> WhisperModelStore.Availability,
        modelDownloader: any WhisperModelDownloading = WhisperModelDownloader()
    ) {
        self.engine = engine
        self.outputWriter = outputWriter
        self.destinationPicker = destinationPicker
        self.fileSelectionService = fileSelectionService
        self.availabilityProvider = availabilityProvider
        self.modelDownloader = modelDownloader
        modelAvailability = availabilityProvider()
    }

    var selectedMediaName: String? {
        selectedMediaURL?.lastPathComponent
    }

    var canStart: Bool {
        selectedMediaURL != nil
            && state.isBusy == false
            && modelDownloadState.isBusy == false
            && isModelAvailable
    }

    /// Indica se una nuova selezione può sostituire quella corrente.
    ///
    /// Il download del modello non blocca la scelta del media; un'operazione
    /// di trascrizione già avviata, invece, deve conservare il proprio input.
    var canAcceptMedia: Bool {
        state.isBusy == false
    }

    var canDownloadModel: Bool {
        isModelAvailable == false
            && state.isBusy == false
            && modelDownloadState.isBusy == false
    }

    var canConfigureOutput: Bool {
        switch state {
        case .idle, .completed, .failed:
            return true
        case .selectingDestination, .loadingModel, .transcribing, .cancelling:
            return false
        }
    }

    var isModelAvailable: Bool {
        if case .available = modelAvailability {
            return true
        }
        return false
    }

    var modelStatusMessage: String {
        if let downloadMessage = modelDownloadState.statusMessage,
           modelDownloadState != .idle {
            return downloadMessage
        }

        switch modelAvailability {
        case .available:
            return "Whisper Large v3 pronto"
        case .missing(let message):
            return message
        }
    }

    func chooseMedia() {
        guard canAcceptMedia else { return }
        Task {
            guard let url = await fileSelectionService.selectMedia() else { return }
            selectMedia(url)
        }
    }

    @discardableResult
    func selectMedia(_ url: URL) -> Bool {
        guard canAcceptMedia else { return false }
        selectedMediaURL = url
        state = .idle
        return true
    }

    func clearSelection() {
        guard state.isBusy == false else { return }
        selectedMediaURL = nil
        state = .idle
    }

    func startTranscription() {
        guard state.isBusy == false,
              modelDownloadState.isBusy == false,
              let mediaURL = selectedMediaURL else { return }
        refreshModelAvailability()
        guard case .available(let modelLocations) = modelAvailability else {
            state = .failed(message: modelStatusMessage)
            return
        }

        state = .selectingDestination
        operationTask = Task { [weak self] in
            guard let self else { return }
            await self.runTranscription(
                mediaURL: mediaURL,
                modelLocations: modelLocations,
                outputSelection: outputSelection
            )
        }
    }

    func startModelDownload() {
        guard state.isBusy == false,
              modelDownloadState.isBusy == false else { return }
        refreshModelAvailability()
        guard canDownloadModel else { return }

        let generation = UUID()
        modelDownloadGeneration = generation
        modelDownloadState = .downloading(progress: nil)
        let downloader = modelDownloader

        modelDownloadTask = Task { [weak self] in
            guard let self else { return }

            do {
                let locations = try await downloader.downloadModel { [weak self] progress in
                    guard let model = self else { return }
                    Task { @MainActor in
                        model.updateModelDownloadProgress(progress, generation: generation)
                    }
                }
                try Task.checkCancellation()

                self.finishModelDownload(
                    generation: generation,
                    outcome: .success(locations)
                )
            } catch {
                self.finishModelDownload(
                    generation: generation,
                    outcome: Self.isCancellation(error) ? .cancelled : .failure(error)
                )
            }
        }
    }

    func cancelModelDownload() {
        guard case .downloading = modelDownloadState,
              let modelDownloadTask else { return }
        modelDownloadState = .cancelling
        modelDownloadTask.cancel()
    }

    func cancelModelDownloadAndWait() async {
        guard let modelDownloadTask else { return }
        if case .downloading = modelDownloadState {
            modelDownloadState = .cancelling
        }
        modelDownloadTask.cancel()
        await modelDownloadTask.value
    }

    func refreshModelAvailability() {
        guard modelDownloadState.isBusy == false else { return }
        modelAvailability = availabilityProvider()
        switch modelAvailability {
        case .available:
            if case .failed = modelDownloadState {
                modelDownloadState = .completed
            }
        case .missing:
            if modelDownloadState == .completed {
                modelDownloadState = .idle
            }
        }
    }

    func cancel() {
        guard state.isBusy else { return }
        state = .cancelling
        destinationPicker.cancelActivePanel()
        operationTask?.cancel()
        Task {
            await engine.cancel()
        }
    }

    func cancelAndWait() async {
        guard state.isBusy else { return }
        state = .cancelling
        destinationPicker.cancelActivePanel()
        let task = operationTask
        task?.cancel()
        await engine.cancel()
        await task?.value
    }

    func cancelAllAndWait() async {
        let transcriptionTask = operationTask
        let downloadTask = modelDownloadTask
        let shouldCancelTranscription = state.isBusy

        if shouldCancelTranscription {
            state = .cancelling
            destinationPicker.cancelActivePanel()
            transcriptionTask?.cancel()
        }
        if case .downloading = modelDownloadState {
            modelDownloadState = .cancelling
        }
        downloadTask?.cancel()

        if shouldCancelTranscription {
            await engine.cancel()
        }
        await transcriptionTask?.value
        await downloadTask?.value
    }

    func showResultInFinder() {
        guard case .completed(let result) = state else { return }
        NSWorkspace.shared.activateFileViewerSelecting(result.generatedURLs)
    }

    private func runTranscription(
        mediaURL: URL,
        modelLocations: WhisperModelStore.BundleModelLocations,
        outputSelection: TranscriptionOutputSelection
    ) async {
        let suggestedBaseName = mediaURL.deletingPathExtension().lastPathComponent
        guard let destination = await destinationPicker.selectDestination(
            suggestedBaseName: suggestedBaseName,
            initialDirectoryURL: mediaURL.deletingLastPathComponent(),
            outputSelection: outputSelection
        ) else {
            state = .idle
            operationTask = nil
            return
        }

        let mediaHasSecurityScope = mediaURL.startAccessingSecurityScopedResource()
        let destinationHasSecurityScope = destination.securityScopeURL.startAccessingSecurityScopedResource()
        defer {
            if mediaHasSecurityScope {
                mediaURL.stopAccessingSecurityScopedResource()
            }
            if destinationHasSecurityScope {
                destination.securityScopeURL.stopAccessingSecurityScopedResource()
            }
            operationTask = nil
        }

        do {
            try Task.checkCancellation()
            do {
                try outputWriter.validateWriteAccess(to: destination)
            } catch {
                state = .failed(
                    message: "Impossibile scrivere nella cartella scelta: \(error.localizedDescription)"
                )
                return
            }
            try Task.checkCancellation()

            let output = try await engine.transcribe(
                mediaURL: mediaURL,
                modelLocations: modelLocations,
                phaseCallback: { [weak self] phase in
                    guard let self, self.state != .cancelling else { return }
                    switch phase {
                    case .loadingModel:
                        self.state = .loadingModel
                    case .transcribing:
                        self.state = .transcribing(progress: 0)
                    }
                },
                progressCallback: { [weak self] progress in
                    self?.updateProgress(progress)
                }
            )
            try Task.checkCancellation()

            let writtenFiles = try outputWriter.write(output, to: destination)

            state = .completed(
                TranscriptionResult(
                    mediaURL: mediaURL,
                    srtURL: writtenFiles.srtURL,
                    txtURL: writtenFiles.txtURL,
                    cues: output.cues
                )
            )
        } catch is CancellationError {
            state = .idle
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }

    private func updateProgress(_ progress: Double) {
        guard state != .cancelling else { return }
        guard progress.isFinite else { return }
        let clamped = min(max(progress, 0), 1)
        if case .transcribing(let current) = state,
           abs(current - clamped) < 0.005,
           clamped < 1 {
            return
        }
        state = .transcribing(progress: clamped)
    }

    private enum ModelDownloadOutcome {
        case success(WhisperModelStore.BundleModelLocations)
        case cancelled
        case failure(Error)
    }

    private func finishModelDownload(
        generation: UUID,
        outcome: ModelDownloadOutcome
    ) {
        guard modelDownloadGeneration == generation else { return }

        defer {
            modelDownloadTask = nil
            modelDownloadGeneration = nil
        }

        switch outcome {
        case .success(let locations):
            modelAvailability = .available(locations)
            modelDownloadState = .completed
        case .cancelled:
            refreshAvailabilityAfterTerminalDownload(defaultState: .idle)
        case .failure(let error):
            refreshAvailabilityAfterTerminalDownload(
                defaultState: .failed(
                    message: error.localizedDescription
                )
            )
        }

        if case .failed = state, isModelAvailable {
            state = .idle
        }
    }

    private func refreshAvailabilityAfterTerminalDownload(
        defaultState: WhisperModelDownloadState
    ) {
        modelAvailability = availabilityProvider()
        if case .available = modelAvailability {
            modelDownloadState = .completed
        } else {
            modelDownloadState = defaultState
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if Task.isCancelled || error is CancellationError {
            return true
        }

        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }

        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    private func updateModelDownloadProgress(_ progress: Double?, generation: UUID) {
        guard modelDownloadGeneration == generation,
              case .downloading = modelDownloadState else { return }
        guard let progress, progress.isFinite else {
            modelDownloadState = .downloading(progress: nil)
            return
        }
        modelDownloadState = .downloading(progress: min(max(progress, 0), 1))
    }
}

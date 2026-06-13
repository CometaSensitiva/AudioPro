import AppKit
import Combine
import Foundation

@MainActor
final class TranscriptionModel: ObservableObject {
    @Published private(set) var selectedMediaURL: URL?
    @Published private(set) var state: LocalTranscriptionState = .idle
    @Published var outputSelection: TranscriptionOutputSelection = .srtAndTxt

    private let engine: any TranscriptionProcessing
    private let outputWriter: any TranscriptionOutputWriting
    private let destinationPicker: any TranscriptionDestinationSelecting
    private let fileSelectionService: FileSelectionService
    private let availabilityProvider: @Sendable () -> WhisperModelStore.Availability
    private var operationTask: Task<Void, Never>?

    convenience init() {
        self.init(
            engine: WhisperTranscriptionEngine(),
            outputWriter: TranscriptionOutputWriter(),
            destinationPicker: TranscriptionDestinationPicker(),
            fileSelectionService: FileSelectionService(),
            availabilityProvider: { WhisperModelStore.availability() }
        )
    }

    init(
        engine: any TranscriptionProcessing,
        outputWriter: any TranscriptionOutputWriting,
        destinationPicker: any TranscriptionDestinationSelecting,
        fileSelectionService: FileSelectionService,
        availabilityProvider: @escaping @Sendable () -> WhisperModelStore.Availability
    ) {
        self.engine = engine
        self.outputWriter = outputWriter
        self.destinationPicker = destinationPicker
        self.fileSelectionService = fileSelectionService
        self.availabilityProvider = availabilityProvider
    }

    var selectedMediaName: String? {
        selectedMediaURL?.lastPathComponent
    }

    var canStart: Bool {
        selectedMediaURL != nil
            && state.isBusy == false
            && isModelAvailable
    }

    var canConfigureOutput: Bool {
        switch state {
        case .idle, .failed:
            return true
        case .selectingDestination, .loadingModel, .transcribing, .cancelling, .completed:
            return false
        }
    }

    var isModelAvailable: Bool {
        if case .available = availabilityProvider() {
            return true
        }
        return false
    }

    var modelStatusMessage: String {
        switch availabilityProvider() {
        case .available:
            return "Whisper Large v3 pronto"
        case .missing(let message):
            return message
        }
    }

    func chooseMedia() {
        guard state.isBusy == false else { return }
        Task {
            guard let url = await fileSelectionService.selectMedia() else { return }
            selectMedia(url)
        }
    }

    func selectMedia(_ url: URL) {
        guard state.isBusy == false else { return }
        selectedMediaURL = url
        state = .idle
    }

    func clearSelection() {
        guard state.isBusy == false else { return }
        selectedMediaURL = nil
        state = .idle
    }

    func startTranscription() {
        guard state.isBusy == false, let mediaURL = selectedMediaURL else { return }
        guard case .available(let modelLocations) = availabilityProvider() else {
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
            state = .failed(message: "Trascrizione non riuscita: \(error.localizedDescription)")
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
}

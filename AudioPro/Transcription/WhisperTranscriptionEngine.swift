import Foundation
import WhisperKit

nonisolated enum TranscriptionEnginePhase: Sendable {
    case loadingModel
    case transcribing
}

typealias TranscriptionPhaseCallback = @MainActor @Sendable (TranscriptionEnginePhase) -> Void
typealias TranscriptionProgressCallback = @MainActor @Sendable (Double) -> Void

nonisolated protocol TranscriptionProcessing: Sendable {
    func transcribe(
        mediaURL: URL,
        modelLocations: WhisperModelStore.BundleModelLocations,
        phaseCallback: TranscriptionPhaseCallback?,
        progressCallback: TranscriptionProgressCallback?
    ) async throws -> TranscriptionOutput

    func cancel() async
}

actor WhisperTranscriptionEngine: TranscriptionProcessing {
    enum TranscriptionError: LocalizedError, Equatable {
        case modelUnavailable(String)
        case emptyResult

        var errorDescription: String? {
            switch self {
            case .modelUnavailable(let message):
                return message
            case .emptyResult:
                return "La trascrizione non ha prodotto segmenti validi."
            }
        }
    }

    private final class CancellationFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false

        var isCancelled: Bool {
            lock.withLock { cancelled }
        }

        func cancel() {
            lock.withLock {
                cancelled = true
            }
        }
    }

    private var activePipeline: WhisperKit?
    private var cancellationFlag: CancellationFlag?

    func transcribe(
        mediaURL: URL,
        modelLocations: WhisperModelStore.BundleModelLocations,
        phaseCallback: TranscriptionPhaseCallback?,
        progressCallback: TranscriptionProgressCallback?
    ) async throws -> TranscriptionOutput {
        let flag = CancellationFlag()
        cancellationFlag = flag

        do {
            await phaseCallback?(.loadingModel)
            let pipeline = try await makePipeline(modelLocations: modelLocations)
            activePipeline = pipeline
            try Task.checkCancellation()
            guard flag.isCancelled == false else { throw CancellationError() }

            await phaseCallback?(.transcribing)
            let progress = pipeline.progress
            let progressMonitor = Task {
                while Task.isCancelled == false && flag.isCancelled == false {
                    await progressCallback?(progress.fractionCompleted)
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
            defer { progressMonitor.cancel() }

            let options = DecodingOptions(
                language: "it",
                usePrefillPrompt: true,
                skipSpecialTokens: true,
                concurrentWorkerCount: 1,
                chunkingStrategy: .vad
            )

            let results = try await pipeline.transcribe(
                audioPath: mediaURL.path,
                decodeOptions: options,
                callback: { _ in
                    flag.isCancelled ? false : nil
                }
            )

            try Task.checkCancellation()
            guard flag.isCancelled == false else { throw CancellationError() }
            await progressCallback?(1)

            let drafts = results
                .flatMap(\.segments)
                .map { segment in
                    TranscriptionCueDraft(
                        start: TimeInterval(segment.start),
                        end: TimeInterval(segment.end),
                        text: segment.text
                    )
                }
            let output = TranscriptionOutputFormatter.makeOutput(from: drafts)
            guard output.cues.isEmpty == false else {
                throw TranscriptionError.emptyResult
            }

            await unloadActivePipeline()
            return output
        } catch {
            await unloadActivePipeline()
            throw error
        }
    }

    func cancel() async {
        cancellationFlag?.cancel()
        activePipeline?.progress.cancel()
    }

    private func makePipeline(
        modelLocations: WhisperModelStore.BundleModelLocations
    ) async throws -> WhisperKit {
        let config = WhisperKitConfig(
            modelFolder: modelLocations.modelFolder.path,
            tokenizerFolder: modelLocations.tokenizerFolder,
            verbose: false,
            logLevel: .error,
            prewarm: false,
            load: false,
            download: false
        )

        let pipeline = try await WhisperKit(config)
        activePipeline = pipeline
        try await pipeline.loadModels()
        return pipeline
    }

    private func unloadActivePipeline() async {
        if let activePipeline {
            await activePipeline.unloadModels()
            activePipeline.clearState()
        }
        activePipeline = nil
        cancellationFlag = nil
    }
}

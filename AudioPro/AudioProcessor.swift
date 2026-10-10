import Foundation

actor AudioProcessor: ExportProcessing {
    #if arch(arm64)
    private nonisolated static let preferredHelperName = "ffmpeg-binary-arm64"
    private nonisolated static let fallbackHelperName = "ffmpeg-binary-x86_64"
    #else
    private nonisolated static let preferredHelperName = "ffmpeg-binary-x86_64"
    private nonisolated static let fallbackHelperName = "ffmpeg-binary-arm64"
    #endif
    private nonisolated static let helperDirectory = "Contents/Helpers"

    private let verifier: FFmpegBinaryVerifier
    private let runner: FFmpegProcessRunner

    init(
        verifier: FFmpegBinaryVerifier,
        runner: FFmpegProcessRunner
    ) {
        self.verifier = verifier
        self.runner = runner
    }

    init() {
        self.verifier = FFmpegBinaryVerifier(helperDirectory: AudioProcessor.helperDirectory)
        self.runner = FFmpegProcessRunner()
    }

    enum ProcessError: LocalizedError {
        case ffmpegNotFound
        case ffmpegNotExecutable
        case ffmpegIntegrityCheckFailed
        case ffmpegFailed(String)
        case exportAlreadyRunning
        case unsupportedCommandConfiguration(String)
        case fileCreationFailed
        case outputPreparationFailed(String)
        case outputCommitFailed(String)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .ffmpegNotFound:
                return "FFmpeg non è disponibile nell’app."
            case .ffmpegNotExecutable:
                return "Il componente FFmpeg incluso nell’app non è eseguibile."
            case .ffmpegIntegrityCheckFailed:
                return "Il componente FFmpeg incluso nell’app non supera il controllo di integrità."
            case .ffmpegFailed:
                return "FFmpeg non è riuscito a completare l’esportazione. Verifica i file sorgente e riprova."
            case .exportAlreadyRunning:
                return "Un’altra esportazione è già in corso."
            case .unsupportedCommandConfiguration(let message):
                return message
            case .fileCreationFailed:
                return "Impossibile creare il file temporaneo."
            case .outputPreparationFailed(let message):
                return "Impossibile preparare l’esportazione: \(message)"
            case .outputCommitFailed(let message):
                return "Impossibile salvare l’esportazione: \(message)"
            case .cancelled:
                return "Operazione annullata."
            }
        }
    }

    func cancel() async {
        await runner.cancel()
    }

    func process(
        fileURLs: [URL],
        outputURL: URL,
        job: ExportJob,
        estimatedTotalDuration: Double? = nil,
        progressCallback: ExportProgressCallback? = nil
    ) async -> Result<Void, ProcessError> {
        guard Task.isCancelled == false else {
            return .failure(.cancelled)
        }

        let ffmpegPath: String
        switch Self.getFFmpegPath(verifier: verifier) {
        case .success(let path):
            ffmpegPath = path
        case .failure(let error):
            return .failure(error)
        }

        let transaction: ExportOutputTransaction
        do {
            transaction = try ExportOutputTransaction(destinationURL: outputURL)
        } catch {
            return .failure(.outputPreparationFailed(error.localizedDescription))
        }
        defer {
            transaction.discard()
        }

        let stagedFileURLs: [URL]
        do {
            stagedFileURLs = try transaction.stageInputs(fileURLs)
        } catch {
            return .failure(.outputPreparationFailed(error.localizedDescription))
        }

        guard Task.isCancelled == false else {
            return .failure(.cancelled)
        }

        let arguments: [String]
        do {
            arguments = try FFmpegCommandBuilder.makeArguments(
                fileURLs: stagedFileURLs,
                outputURL: transaction.stagingURL,
                job: job
            )
        } catch let error as FFmpegCommandBuilder.BuilderError {
            return .failure(.unsupportedCommandConfiguration(error.localizedDescription))
        } catch {
            return .failure(.unsupportedCommandConfiguration(error.localizedDescription))
        }

        guard Task.isCancelled == false else {
            return .failure(.cancelled)
        }

        let result = await runner.run(
            path: ffmpegPath,
            arguments: arguments,
            inputCount: stagedFileURLs.count,
            estimatedTotalDuration: estimatedTotalDuration ?? 0,
            progressCallback: progressCallback
        )

        switch result {
        case .success:
            guard Task.isCancelled == false else {
                return .failure(.cancelled)
            }
            do {
                try transaction.commit()
                return .success(())
            } catch {
                return .failure(.outputCommitFailed(error.localizedDescription))
            }
        case .failure(let error):
            return .failure(error)
        }
    }

    private nonisolated static func getFFmpegPath(
        verifier: FFmpegBinaryVerifier
    ) -> Result<String, ProcessError> {
        let candidatePaths: [String] = [
            Bundle.main.bundleURL
                .appendingPathComponent(Self.helperDirectory)
                .appendingPathComponent(Self.preferredHelperName)
                .path,
            Bundle.main.bundleURL
                .appendingPathComponent(Self.helperDirectory)
                .appendingPathComponent(Self.fallbackHelperName)
                .path,
            Bundle.main.resourceURL?.appendingPathComponent("ffmpeg-binary").path
        ].compactMap { $0 }

        guard let path = candidatePaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            return .failure(.ffmpegNotFound)
        }

        guard FileManager.default.isExecutableFile(atPath: path) else {
            return .failure(.ffmpegNotExecutable)
        }

        guard verifier.verifyRuntimeBinary(atPath: path, bundleURL: Bundle.main.bundleURL) else {
            return .failure(.ffmpegIntegrityCheckFailed)
        }

        return .success(path)
    }
}

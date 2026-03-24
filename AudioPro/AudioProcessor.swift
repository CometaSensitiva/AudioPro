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
        case unsupportedCommandConfiguration(String)
        case fileCreationFailed
        case cancelled

        var errorDescription: String? {
            switch self {
            case .ffmpegNotFound:
                return "ffmpeg non trovato nel bundle dell'app"
            case .ffmpegNotExecutable:
                return "Il binario ffmpeg nel bundle non è eseguibile"
            case .ffmpegIntegrityCheckFailed:
                return "Il binario ffmpeg nel bundle non supera il controllo di integrita"
            case .ffmpegFailed(let message):
                return "Errore ffmpeg: \(message)"
            case .unsupportedCommandConfiguration(let message):
                return message
            case .fileCreationFailed:
                return "Impossibile creare il file temporaneo"
            case .cancelled:
                return "Operazione annullata"
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
        let ffmpegPath: String
        switch Self.getFFmpegPath(verifier: verifier) {
        case .success(let path):
            ffmpegPath = path
        case .failure(let error):
            return .failure(error)
        }

        let arguments: [String]
        do {
            arguments = try FFmpegCommandBuilder.makeArguments(
                fileURLs: fileURLs,
                outputURL: outputURL,
                job: job
            )
        } catch let error as FFmpegCommandBuilder.BuilderError {
            return .failure(.unsupportedCommandConfiguration(error.localizedDescription))
        } catch {
            return .failure(.unsupportedCommandConfiguration(error.localizedDescription))
        }

        return await runner.run(
            path: ffmpegPath,
            arguments: arguments,
            inputCount: fileURLs.count,
            estimatedTotalDuration: estimatedTotalDuration ?? 0,
            progressCallback: progressCallback
        )
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

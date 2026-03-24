import Foundation

typealias ExportProgressCallback = @MainActor @Sendable (Double) -> Void

protocol ExportProcessing: Sendable {
    func cancel() async

    func process(
        fileURLs: [URL],
        outputURL: URL,
        job: ExportJob,
        estimatedTotalDuration: Double?,
        progressCallback: ExportProgressCallback?
    ) async -> Result<Void, AudioProcessor.ProcessError>
}

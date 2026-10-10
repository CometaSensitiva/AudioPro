import Foundation
import WhisperKit

typealias WhisperModelDownloadProgressCallback = @Sendable (Double?) -> Void
typealias WhisperModelCacheRootProvider = @Sendable () throws -> URL

nonisolated protocol WhisperModelDownloading: Sendable {
    func downloadModel(
        progressCallback: WhisperModelDownloadProgressCallback?
    ) async throws -> WhisperModelStore.BundleModelLocations
}

nonisolated protocol WhisperModelArtifactsDownloading: Sendable {
    func downloadModel(
        to cacheRoot: URL,
        progressCallback: WhisperModelDownloadProgressCallback?
    ) async throws -> URL

    func downloadTokenizer(to cacheRoot: URL) async throws
}

private struct WhisperKitModelArtifactsDownloader: WhisperModelArtifactsDownloading {
    func downloadModel(
        to cacheRoot: URL,
        progressCallback: WhisperModelDownloadProgressCallback?
    ) async throws -> URL {
        try await WhisperKit.download(
            variant: WhisperModelStore.downloadVariantName,
            downloadBase: cacheRoot,
            useBackgroundSession: false
        ) { progress in
            progressCallback?(Self.fraction(from: progress))
        }
    }

    func downloadTokenizer(to cacheRoot: URL) async throws {
        _ = try await ModelUtilities.loadTokenizer(
            for: .largev3,
            tokenizerFolder: cacheRoot,
            useBackgroundSession: false
        )
    }

    private static func fraction(from progress: Progress) -> Double? {
        if progress.totalUnitCount > 0 {
            let fraction = Double(progress.completedUnitCount) / Double(progress.totalUnitCount)
            return fraction.isFinite ? min(max(fraction, 0), 1) : nil
        }

        let fraction = progress.fractionCompleted
        return fraction.isFinite ? min(max(fraction, 0), 1) : nil
    }
}

actor WhisperModelDownloader: WhisperModelDownloading {
    enum DownloadError: LocalizedError {
        case validationFailed

        var errorDescription: String? {
            switch self {
            case .validationFailed:
                return "Il modello scaricato non contiene tutti i file richiesti."
            }
        }
    }

    private let artifactsDownloader: any WhisperModelArtifactsDownloading
    private let cacheRootProvider: WhisperModelCacheRootProvider

    init(
        artifactsDownloader: any WhisperModelArtifactsDownloading = WhisperKitModelArtifactsDownloader(),
        cacheRootProvider: @escaping WhisperModelCacheRootProvider = {
            try WhisperModelStore.ensureModelCacheDirectory()
        }
    ) {
        self.artifactsDownloader = artifactsDownloader
        self.cacheRootProvider = cacheRootProvider
    }

    func downloadModel(
        progressCallback: WhisperModelDownloadProgressCallback? = nil
    ) async throws -> WhisperModelStore.BundleModelLocations {
        try Task.checkCancellation()
        let cacheRoot = try cacheRootProvider()
        progressCallback?(0)

        let modelFolder = try await artifactsDownloader.downloadModel(
            to: cacheRoot,
            progressCallback: progressCallback
        )
        try Task.checkCancellation()

        try await artifactsDownloader.downloadTokenizer(to: cacheRoot)
        try Task.checkCancellation()

        guard let tokenizerFolder = WhisperModelStore.downloadedTokenizerFolder(in: cacheRoot) else {
            throw DownloadError.validationFailed
        }

        let locations = WhisperModelStore.BundleModelLocations(
            modelFolder: modelFolder,
            tokenizerFolder: tokenizerFolder
        )
        try WhisperModelStore.registerDownloadedModel(locations, in: cacheRoot)

        guard let registeredLocations = WhisperModelStore.downloadedModelLocations(in: cacheRoot) else {
            throw DownloadError.validationFailed
        }

        progressCallback?(1)
        return registeredLocations
    }
}

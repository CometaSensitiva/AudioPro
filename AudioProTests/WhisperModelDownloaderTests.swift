import XCTest
@testable import AudioPro

final class WhisperModelDownloaderTests: XCTestCase {
    func testPreCancelledTaskDoesNotStartArtifactDownload() async throws {
        let cacheRoot = try makeTemporaryDirectory()
        let modelFolder = try makeValidModelFolder(in: cacheRoot)
        let artifacts = GatedArtifactsDownloader(modelFolder: modelFolder)
        let gate = DownloaderTestGate()
        let downloader = WhisperModelDownloader(
            artifactsDownloader: artifacts,
            cacheRootProvider: { cacheRoot }
        )

        let task = Task {
            await gate.waitUntilOpen()
            return try await downloader.downloadModel(progressCallback: nil)
        }
        task.cancel()
        await gate.open()

        do {
            _ = try await task.value
            XCTFail("Un task già cancellato non deve iniziare il download.")
        } catch is CancellationError {
            // Expected.
        }

        let modelDownloadStarted = await artifacts.modelDownloadStarted
        XCTAssertFalse(modelDownloadStarted)
    }

    func testSuccessfulDownloadCommitsBothArtifactsBeforeFinalProgress() async throws {
        let cacheRoot = try makeTemporaryDirectory()
        let locations = try makeDownloadedLocations(in: cacheRoot)
        let artifacts = ImmediateArtifactsDownloader(
            modelFolder: locations.modelFolder,
            tokenizerError: nil
        )
        let recorder = DownloadProgressRecorder()
        let downloader = WhisperModelDownloader(
            artifactsDownloader: artifacts,
            cacheRootProvider: { cacheRoot }
        )

        let downloadedLocations = try await downloader.downloadModel { progress in
            recorder.record(
                progress,
                modelWasCommitted: WhisperModelStore.downloadedModelLocations(in: cacheRoot) != nil
            )
        }

        XCTAssertEqual(downloadedLocations, WhisperModelStore.downloadedModelLocations(in: cacheRoot))
        XCTAssertEqual(recorder.values.first, 0)
        XCTAssertEqual(recorder.values.last, 1)
        XCTAssertTrue(recorder.wasCommittedAtFinalProgress)
    }

    func testTokenizerFailureLeavesCompletedModelInvisible() async throws {
        let cacheRoot = try makeTemporaryDirectory()
        let modelFolder = try makeValidModelFolder(in: cacheRoot)
        let artifacts = ImmediateArtifactsDownloader(
            modelFolder: modelFolder,
            tokenizerError: TestDownloadError.tokenizerFailed
        )
        let downloader = WhisperModelDownloader(
            artifactsDownloader: artifacts,
            cacheRootProvider: { cacheRoot }
        )

        do {
            _ = try await downloader.downloadModel(progressCallback: nil)
            XCTFail("Il download doveva fallire durante il tokenizer.")
        } catch let error as TestDownloadError {
            XCTAssertEqual(error, .tokenizerFailed)
        }

        XCTAssertNil(WhisperModelStore.downloadedModelLocations(in: cacheRoot))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: cacheRoot
                    .appendingPathComponent(WhisperModelStore.downloadedModelMarkerFileName)
                    .path
            )
        )
    }

    func testCancellationAfterModelStopsBeforeTokenizerAndCommit() async throws {
        let cacheRoot = try makeTemporaryDirectory()
        let modelFolder = try makeValidModelFolder(in: cacheRoot)
        let artifacts = GatedArtifactsDownloader(modelFolder: modelFolder)
        let downloader = WhisperModelDownloader(
            artifactsDownloader: artifacts,
            cacheRootProvider: { cacheRoot }
        )

        let task = Task {
            try await downloader.downloadModel(progressCallback: nil)
        }
        await waitUntilModelDownloadStarts(artifacts)

        task.cancel()
        await artifacts.releaseModelDownload()

        do {
            _ = try await task.value
            XCTFail("Il task cancellato non deve raggiungere il commit.")
        } catch is CancellationError {
            // Expected.
        }

        let tokenizerCallCount = await artifacts.tokenizerCallCount
        XCTAssertEqual(tokenizerCallCount, 0)
        XCTAssertNil(WhisperModelStore.downloadedModelLocations(in: cacheRoot))
    }

    func testInvalidTokenizerFilesCannotBeCommitted() async throws {
        let cacheRoot = try makeTemporaryDirectory()
        let locations = try makeDownloadedLocations(in: cacheRoot)
        try Data().write(to: locations.tokenizerFolder.appendingPathComponent("tokenizer.json"))
        let artifacts = ImmediateArtifactsDownloader(
            modelFolder: locations.modelFolder,
            tokenizerError: nil
        )
        let downloader = WhisperModelDownloader(
            artifactsDownloader: artifacts,
            cacheRootProvider: { cacheRoot }
        )

        do {
            _ = try await downloader.downloadModel(progressCallback: nil)
            XCTFail("Un tokenizer vuoto non deve essere pubblicato.")
        } catch let error as WhisperModelDownloader.DownloadError {
            XCTAssertNotNil(error.errorDescription)
        }

        XCTAssertNil(WhisperModelStore.downloadedModelLocations(in: cacheRoot))
    }

    private func waitUntilModelDownloadStarts(_ artifacts: GatedArtifactsDownloader) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while ContinuousClock.now < deadline {
            if await artifacts.modelDownloadStarted {
                return
            }
            await Task.yield()
        }
        XCTFail("Il backend non ha iniziato il download del modello.")
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func makeDownloadedLocations(
        in cacheRoot: URL
    ) throws -> WhisperModelStore.BundleModelLocations {
        let modelFolder = try makeValidModelFolder(in: cacheRoot)
        let tokenizerFolder = cacheRoot.appendingPathComponent(
            WhisperModelStore.downloadedTokenizerRelativePath,
            isDirectory: true
        )
        try makeValidTokenizerFolder(at: tokenizerFolder)
        return WhisperModelStore.BundleModelLocations(
            modelFolder: modelFolder,
            tokenizerFolder: tokenizerFolder
        )
    }

    private func makeValidModelFolder(in cacheRoot: URL) throws -> URL {
        let modelFolder = cacheRoot
            .appendingPathComponent("models/argmaxinc/whisperkit-coreml", isDirectory: true)
            .appendingPathComponent(WhisperModelStore.modelDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: modelFolder, withIntermediateDirectories: true)
        for directory in ["AudioEncoder.mlmodelc", "MelSpectrogram.mlmodelc", "TextDecoder.mlmodelc"] {
            let compiledModel = modelFolder.appendingPathComponent(directory, isDirectory: true)
            try FileManager.default.createDirectory(
                at: compiledModel,
                withIntermediateDirectories: true
            )
            try Data("model".utf8).write(to: compiledModel.appendingPathComponent("model.mil"))
        }
        for file in ["config.json", "generation_config.json"] {
            try Data("{}".utf8).write(to: modelFolder.appendingPathComponent(file))
        }
        return modelFolder
    }

    private func makeValidTokenizerFolder(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for file in ["tokenizer.json", "config.json"] {
            try Data("{}".utf8).write(to: url.appendingPathComponent(file))
        }
    }
}

private enum TestDownloadError: Error, Equatable {
    case tokenizerFailed
}

private actor ImmediateArtifactsDownloader: WhisperModelArtifactsDownloading {
    let modelFolder: URL
    let tokenizerError: TestDownloadError?

    init(modelFolder: URL, tokenizerError: TestDownloadError?) {
        self.modelFolder = modelFolder
        self.tokenizerError = tokenizerError
    }

    func downloadModel(
        to cacheRoot: URL,
        progressCallback: WhisperModelDownloadProgressCallback?
    ) async throws -> URL {
        progressCallback?(0.5)
        return modelFolder
    }

    func downloadTokenizer(to cacheRoot: URL) async throws {
        if let tokenizerError {
            throw tokenizerError
        }
    }
}

private actor GatedArtifactsDownloader: WhisperModelArtifactsDownloading {
    let modelFolder: URL
    private var modelContinuation: CheckedContinuation<Void, Never>?
    private(set) var modelDownloadStarted = false
    private(set) var tokenizerCallCount = 0

    init(modelFolder: URL) {
        self.modelFolder = modelFolder
    }

    func downloadModel(
        to cacheRoot: URL,
        progressCallback: WhisperModelDownloadProgressCallback?
    ) async throws -> URL {
        modelDownloadStarted = true
        await withCheckedContinuation { continuation in
            modelContinuation = continuation
        }
        return modelFolder
    }

    func downloadTokenizer(to cacheRoot: URL) async throws {
        tokenizerCallCount += 1
    }

    func releaseModelDownload() {
        modelContinuation?.resume()
        modelContinuation = nil
    }
}

private actor DownloaderTestGate {
    private var isOpen = false

    func waitUntilOpen() async {
        while isOpen == false {
            await Task.yield()
        }
    }

    func open() {
        isOpen = true
    }
}

private nonisolated final class DownloadProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedValues: [Double] = []
    private var committedAtFinalProgress = false

    var values: [Double] {
        lock.withLock { recordedValues }
    }

    var wasCommittedAtFinalProgress: Bool {
        lock.withLock { committedAtFinalProgress }
    }

    func record(_ value: Double?, modelWasCommitted: Bool) {
        lock.withLock {
            if let value {
                recordedValues.append(value)
            }
            if value == 1 {
                committedAtFinalProgress = modelWasCommitted
            }
        }
    }
}

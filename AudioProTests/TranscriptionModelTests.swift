import XCTest
@testable import AudioPro

@MainActor
final class TranscriptionModelTests: XCTestCase {
    func testSuccessfulJobPublishesCompletedResult() async throws {
        let directory = try makeTemporaryDirectory()
        let mediaURL = directory.appendingPathComponent("Lezione.m4a")
        try Data("audio".utf8).write(to: mediaURL)
        let destination = TranscriptionDestination(
            directoryURL: directory,
            baseName: "Lezione",
            overwriteExisting: false
        )
        let engine = StubTranscriptionEngine(mode: .success)
        let model = makeModel(
            engine: engine,
            picker: StubDestinationPicker(destination: destination)
        )

        model.selectMedia(mediaURL)
        model.startTranscription()
        await waitUntilFinished(model)

        guard case .completed(let result) = model.state else {
            return XCTFail("Stato atteso: completed, ottenuto: \(model.state)")
        }
        XCTAssertEqual(result.mediaURL, mediaURL)
        XCTAssertEqual(result.srtURL, destination.srtURL)
        XCTAssertEqual(result.txtURL, destination.txtURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.srtURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.txtURL.path))
    }

    func testSelectMediaRejectsReplacementWhileTranscriptionIsBusy() async throws {
        let directory = try makeTemporaryDirectory()
        let initialMediaURL = directory.appendingPathComponent("Lezione.m4a")
        let replacementMediaURL = directory.appendingPathComponent("Esportazione.m4a")
        try Data("audio".utf8).write(to: initialMediaURL)
        try Data("replacement".utf8).write(to: replacementMediaURL)
        let destination = TranscriptionDestination(
            directoryURL: directory,
            baseName: "Lezione",
            overwriteExisting: false
        )
        let model = makeModel(
            engine: StubTranscriptionEngine(mode: .waitForCancellation),
            picker: StubDestinationPicker(destination: destination)
        )

        XCTAssertTrue(model.selectMedia(initialMediaURL))
        model.startTranscription()
        await waitUntilTranscribing(model)

        XCTAssertFalse(model.canAcceptMedia)
        XCTAssertFalse(model.selectMedia(replacementMediaURL))
        XCTAssertEqual(model.selectedMediaURL, initialMediaURL)

        await model.cancelAndWait()
        XCTAssertTrue(model.canAcceptMedia)
    }

    func testCanConfigureOutputMatchesTranscriptionLifecycle() async throws {
        let directory = try makeTemporaryDirectory()
        let mediaURL = directory.appendingPathComponent("Lezione.m4a")
        try Data("audio".utf8).write(to: mediaURL)
        let destination = TranscriptionDestination(
            directoryURL: directory,
            baseName: "Lezione",
            overwriteExisting: false
        )

        let busyModel = makeModel(
            engine: StubTranscriptionEngine(mode: .waitForCancellation),
            picker: StubDestinationPicker(destination: destination)
        )
        XCTAssertTrue(busyModel.canConfigureOutput)
        busyModel.selectMedia(mediaURL)
        busyModel.startTranscription()
        await waitUntilTranscribing(busyModel)
        XCTAssertFalse(busyModel.canConfigureOutput)
        await busyModel.cancelAndWait()

        let completedModel = makeModel(
            engine: StubTranscriptionEngine(mode: .success),
            picker: StubDestinationPicker(destination: destination)
        )
        completedModel.selectMedia(mediaURL)
        completedModel.startTranscription()
        await waitUntilFinished(completedModel)
        guard case .completed = completedModel.state else {
            return XCTFail("Stato atteso: completed, ottenuto: \(completedModel.state)")
        }
        XCTAssertTrue(completedModel.canConfigureOutput)

        let failedModel = makeModel(
            engine: StubTranscriptionEngine(mode: .success),
            picker: StubDestinationPicker(destination: destination),
            outputWriter: PermissionDeniedOutputWriter()
        )
        failedModel.selectMedia(mediaURL)
        failedModel.startTranscription()
        await waitUntilFinished(failedModel)
        guard case .failed = failedModel.state else {
            return XCTFail("Stato atteso: failed, ottenuto: \(failedModel.state)")
        }
        XCTAssertTrue(failedModel.canConfigureOutput)
    }

    func testSessionRoutesToTranscriptionOnlyWhenExportedFileIsAccepted() async throws {
        let directory = try makeTemporaryDirectory()
        let exportedMediaURL = directory.appendingPathComponent("Esportazione.m4a")
        try Data("audio".utf8).write(to: exportedMediaURL)
        let destination = TranscriptionDestination(
            directoryURL: directory,
            baseName: "Esportazione",
            overwriteExisting: false
        )
        let model = makeModel(
            engine: StubTranscriptionEngine(mode: .success),
            picker: StubDestinationPicker(destination: destination)
        )
        let session = AppSession(
            appState: AudioAppState(),
            transcriptionModel: model,
            playerModel: PlayerModel()
        )

        XCTAssertTrue(session.canTranscribeExportedFile)
        XCTAssertTrue(session.transcribeExportedFile(exportedMediaURL))
        XCTAssertEqual(session.section, .transcription)
        XCTAssertEqual(model.selectedMediaURL, exportedMediaURL)
    }

    func testSessionKeepsCurrentSectionWhenTranscriptionRejectsExportedFile() async throws {
        let directory = try makeTemporaryDirectory()
        let initialMediaURL = directory.appendingPathComponent("Lezione.m4a")
        let exportedMediaURL = directory.appendingPathComponent("Esportazione.m4a")
        try Data("audio".utf8).write(to: initialMediaURL)
        try Data("replacement".utf8).write(to: exportedMediaURL)
        let destination = TranscriptionDestination(
            directoryURL: directory,
            baseName: "Lezione",
            overwriteExisting: false
        )
        let model = makeModel(
            engine: StubTranscriptionEngine(mode: .waitForCancellation),
            picker: StubDestinationPicker(destination: destination)
        )
        let session = AppSession(
            appState: AudioAppState(),
            transcriptionModel: model,
            playerModel: PlayerModel()
        )
        session.section = .merger

        XCTAssertTrue(model.selectMedia(initialMediaURL))
        model.startTranscription()
        await waitUntilTranscribing(model)

        XCTAssertFalse(session.canTranscribeExportedFile)
        XCTAssertFalse(session.transcribeExportedFile(exportedMediaURL))
        XCTAssertEqual(session.section, .merger)
        XCTAssertEqual(model.selectedMediaURL, initialMediaURL)

        await model.cancelAndWait()
    }

    func testTXTOnlyResultDoesNotSupportSynchronizedPlayback() async throws {
        let directory = try makeTemporaryDirectory()
        let mediaURL = directory.appendingPathComponent("Lezione.m4a")
        try Data("audio".utf8).write(to: mediaURL)
        let destination = TranscriptionDestination(
            directoryURL: directory,
            baseName: "Lezione",
            outputSelection: .txtOnly,
            overwriteExisting: false
        )
        let model = makeModel(
            engine: StubTranscriptionEngine(mode: .success),
            picker: StubDestinationPicker(destination: destination)
        )
        model.outputSelection = .txtOnly

        model.selectMedia(mediaURL)
        model.startTranscription()
        await waitUntilFinished(model)

        guard case .completed(let result) = model.state else {
            return XCTFail("Stato atteso: completed, ottenuto: \(model.state)")
        }
        XCTAssertNil(result.srtURL)
        XCTAssertEqual(result.txtURL, destination.txtURL)
        XCTAssertFalse(result.canOpenInPlayback)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.srtURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.txtURL.path))
    }

    func testCancellationReturnsToIdleWithoutPublishingFiles() async throws {
        let directory = try makeTemporaryDirectory()
        let mediaURL = directory.appendingPathComponent("Lezione.m4a")
        try Data("audio".utf8).write(to: mediaURL)
        let destination = TranscriptionDestination(
            directoryURL: directory,
            baseName: "Lezione",
            overwriteExisting: false
        )
        let engine = StubTranscriptionEngine(mode: .waitForCancellation)
        let model = makeModel(
            engine: engine,
            picker: StubDestinationPicker(destination: destination)
        )

        model.selectMedia(mediaURL)
        model.startTranscription()
        await waitUntilTranscribing(model)
        await model.cancelAndWait()

        XCTAssertEqual(model.state, .idle)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.srtURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.txtURL.path))
        let wasCancelled = await engine.wasCancelled
        XCTAssertTrue(wasCancelled)
    }

    func testWritePermissionIsValidatedBeforeWhisperStarts() async throws {
        let directory = try makeTemporaryDirectory()
        let mediaURL = directory.appendingPathComponent("Lezione.m4a")
        try Data("audio".utf8).write(to: mediaURL)
        let destination = TranscriptionDestination(
            directoryURL: directory,
            baseName: "Lezione",
            outputSelection: .txtOnly,
            overwriteExisting: false
        )
        let engine = StubTranscriptionEngine(mode: .success)
        let model = makeModel(
            engine: engine,
            picker: StubDestinationPicker(destination: destination),
            outputWriter: PermissionDeniedOutputWriter()
        )

        model.selectMedia(mediaURL)
        model.startTranscription()
        await waitUntilFinished(model)

        guard case .failed(let message) = model.state else {
            return XCTFail("Stato atteso: failed, ottenuto: \(model.state)")
        }
        XCTAssertTrue(message.contains("Impossibile scrivere nella cartella scelta"))
        let transcribeCallCount = await engine.transcribeCallCount
        XCTAssertEqual(transcribeCallCount, 0)
    }

    func testEngineFailurePublishesOnlyTheCauseForTheErrorView() async throws {
        let directory = try makeTemporaryDirectory()
        let mediaURL = directory.appendingPathComponent("Lezione.m4a")
        try Data("audio".utf8).write(to: mediaURL)
        let destination = TranscriptionDestination(
            directoryURL: directory,
            baseName: "Lezione",
            overwriteExisting: false
        )
        let model = makeModel(
            engine: StubTranscriptionEngine(mode: .failure),
            picker: StubDestinationPicker(destination: destination)
        )

        model.selectMedia(mediaURL)
        model.startTranscription()
        await waitUntilFinished(model)

        XCTAssertEqual(model.state, .failed(message: "Errore di trascrizione test"))
    }

    func testMissingModelDisablesAndRejectsTranscription() throws {
        let directory = try makeTemporaryDirectory()
        let mediaURL = directory.appendingPathComponent("Lezione.m4a")
        try Data("audio".utf8).write(to: mediaURL)
        let destination = TranscriptionDestination(
            directoryURL: directory,
            baseName: "Lezione",
            overwriteExisting: false
        )
        let message = "Whisper Large v3 non rilevato."
        let engine = StubTranscriptionEngine(mode: .success)
        let model = TranscriptionModel(
            engine: engine,
            outputWriter: TranscriptionOutputWriter(),
            destinationPicker: StubDestinationPicker(destination: destination),
            fileSelectionService: FileSelectionService(),
            availabilityProvider: { .missing(message) }
        )

        model.selectMedia(mediaURL)

        XCTAssertFalse(model.isModelAvailable)
        XCTAssertFalse(model.canStart)
        XCTAssertTrue(model.canDownloadModel)
        XCTAssertEqual(model.modelStatusMessage, message)

        model.startTranscription()

        XCTAssertEqual(model.state, .failed(message: message))
    }

    func testModelDownloadPublishesProgressAndEnablesTranscription() async throws {
        let directory = try makeTemporaryDirectory()
        let destination = TranscriptionDestination(
            directoryURL: directory,
            baseName: "Lezione",
            overwriteExisting: false
        )
        let locations = WhisperModelStore.BundleModelLocations(
            modelFolder: directory.appendingPathComponent("model", isDirectory: true),
            tokenizerFolder: directory.appendingPathComponent("tokenizer", isDirectory: true)
        )
        let availability = AvailabilityProbe(.missing("Whisper Large v3 non rilevato."))
        let model = TranscriptionModel(
            engine: StubTranscriptionEngine(mode: .success),
            outputWriter: TranscriptionOutputWriter(),
            destinationPicker: StubDestinationPicker(destination: destination),
            fileSelectionService: FileSelectionService(),
            availabilityProvider: { availability.read() },
            modelDownloader: StubModelDownloader(mode: .success(locations))
        )

        XCTAssertTrue(model.canDownloadModel)

        model.startModelDownload()
        await waitUntilModelDownloadFinished(model)

        XCTAssertEqual(model.modelDownloadState, .completed)
        XCTAssertTrue(model.isModelAvailable)
        XCTAssertEqual(model.modelStatusMessage, "Whisper Large v3 pronto")
    }

    func testAvailabilityIsCachedAcrossDerivedPropertyReads() throws {
        let directory = try makeTemporaryDirectory()
        let destination = TranscriptionDestination(
            directoryURL: directory,
            baseName: "Lezione",
            overwriteExisting: false
        )
        let availability = AvailabilityProbe(.missing("Whisper Large v3 non rilevato."))
        let model = TranscriptionModel(
            engine: StubTranscriptionEngine(mode: .success),
            outputWriter: TranscriptionOutputWriter(),
            destinationPicker: StubDestinationPicker(destination: destination),
            fileSelectionService: FileSelectionService(),
            availabilityProvider: { availability.read() },
            modelDownloader: StubModelDownloader(mode: .failure(TestModelDownloadError.failed))
        )

        XCTAssertEqual(availability.readCount, 1)
        for _ in 0..<20 {
            _ = model.isModelAvailable
            _ = model.canDownloadModel
            _ = model.canStart
            _ = model.modelStatusMessage
        }
        XCTAssertEqual(availability.readCount, 1)

        model.refreshModelAvailability()
        XCTAssertEqual(availability.readCount, 2)
    }

    func testCancelKeepsDownloadBusyUntilUnderlyingTaskTerminates() async throws {
        let harness = try makeControlledDownloadHarness()
        let model = harness.model

        model.startModelDownload()
        await waitUntilRequestCount(1, downloader: harness.downloader)
        model.cancelModelDownload()

        XCTAssertEqual(model.modelDownloadState, .cancelling)
        XCTAssertFalse(model.canDownloadModel)

        model.startModelDownload()
        await Task.yield()
        let requestCount = await harness.downloader.requestCount
        XCTAssertEqual(requestCount, 1)

        await harness.downloader.failRequest(at: 0, with: URLError(.cancelled))
        await waitUntilModelDownloadReturnsToIdle(model)

        XCTAssertEqual(model.modelDownloadState, .idle)
        XCTAssertTrue(model.canDownloadModel)
    }

    func testRetryIgnoresStaleProgressFromCancelledGeneration() async throws {
        let harness = try makeControlledDownloadHarness()
        let model = harness.model

        model.startModelDownload()
        await waitUntilRequestCount(1, downloader: harness.downloader)
        model.cancelModelDownload()
        await harness.downloader.failRequest(at: 0, with: CancellationError())
        await waitUntilModelDownloadReturnsToIdle(model)

        model.startModelDownload()
        await waitUntilRequestCount(2, downloader: harness.downloader)
        await harness.downloader.emitProgress(0.2, forRequestAt: 1)
        await waitUntilDownloadProgress(0.2, model: model)

        await harness.downloader.emitProgress(0.9, forRequestAt: 0)
        await Task.yield()
        XCTAssertEqual(model.modelDownloadState, .downloading(progress: 0.2))

        await harness.downloader.succeedRequest(at: 1, with: harness.locations)
        await waitUntilModelDownloadFinished(model)
        XCTAssertEqual(model.modelDownloadState, .completed)
        XCTAssertEqual(model.modelAvailability, .available(harness.locations))
    }

    func testCancelModelDownloadAndWaitWaitsForRealTermination() async throws {
        let harness = try makeControlledDownloadHarness()
        let model = harness.model

        model.startModelDownload()
        await waitUntilRequestCount(1, downloader: harness.downloader)
        let cancellation = Task { @MainActor in
            await model.cancelModelDownloadAndWait()
        }
        await Task.yield()

        XCTAssertEqual(model.modelDownloadState, .cancelling)
        await harness.downloader.failRequest(at: 0, with: CancellationError())
        await cancellation.value

        XCTAssertEqual(model.modelDownloadState, .idle)
    }

    func testRealDownloadFailureAllowsRetry() async throws {
        let harness = try makeControlledDownloadHarness()
        let model = harness.model

        model.startModelDownload()
        await waitUntilRequestCount(1, downloader: harness.downloader)
        await harness.downloader.failRequest(at: 0, with: TestModelDownloadError.failed)
        await waitUntilModelDownloadFinished(model)

        guard case .failed(let message) = model.modelDownloadState else {
            return XCTFail("Stato download atteso: failed")
        }
        XCTAssertEqual(message, "Errore test")
        XCTAssertTrue(model.canDownloadModel)

        model.startModelDownload()
        await waitUntilRequestCount(2, downloader: harness.downloader)
    }

    private func makeModel(
        engine: StubTranscriptionEngine,
        picker: StubDestinationPicker,
        outputWriter: any TranscriptionOutputWriting = TranscriptionOutputWriter()
    ) -> TranscriptionModel {
        let locations = WhisperModelStore.BundleModelLocations(
            modelFolder: URL(fileURLWithPath: "/tmp/model"),
            tokenizerFolder: URL(fileURLWithPath: "/tmp/tokenizer")
        )
        return TranscriptionModel(
            engine: engine,
            outputWriter: outputWriter,
            destinationPicker: picker,
            fileSelectionService: FileSelectionService(),
            availabilityProvider: { .available(locations) }
        )
    }

    private func makeControlledDownloadHarness() throws -> ControlledDownloadHarness {
        let directory = try makeTemporaryDirectory()
        let destination = TranscriptionDestination(
            directoryURL: directory,
            baseName: "Lezione",
            overwriteExisting: false
        )
        let locations = WhisperModelStore.BundleModelLocations(
            modelFolder: directory.appendingPathComponent("model", isDirectory: true),
            tokenizerFolder: directory.appendingPathComponent("tokenizer", isDirectory: true)
        )
        let availability = AvailabilityProbe(.missing("Whisper Large v3 non rilevato."))
        let downloader = ControlledModelDownloader()
        let model = TranscriptionModel(
            engine: StubTranscriptionEngine(mode: .success),
            outputWriter: TranscriptionOutputWriter(),
            destinationPicker: StubDestinationPicker(destination: destination),
            fileSelectionService: FileSelectionService(),
            availabilityProvider: { availability.read() },
            modelDownloader: downloader
        )
        return ControlledDownloadHarness(
            model: model,
            downloader: downloader,
            locations: locations
        )
    }

    private func waitUntilModelDownloadFinished(_ model: TranscriptionModel) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while ContinuousClock.now < deadline {
            if model.modelDownloadState.isBusy == false, model.modelDownloadState != .idle {
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Il download del modello non ha raggiunto uno stato terminale.")
    }

    private func waitUntilModelDownloadReturnsToIdle(_ model: TranscriptionModel) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while ContinuousClock.now < deadline {
            if model.modelDownloadState == .idle {
                return
            }
            await Task.yield()
        }
        XCTFail("Il download cancellato non è tornato idle.")
    }

    private func waitUntilRequestCount(
        _ expectedCount: Int,
        downloader: ControlledModelDownloader
    ) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while ContinuousClock.now < deadline {
            if await downloader.requestCount == expectedCount {
                return
            }
            await Task.yield()
        }
        XCTFail("Numero richieste download atteso: \(expectedCount).")
    }

    private func waitUntilDownloadProgress(_ expected: Double, model: TranscriptionModel) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while ContinuousClock.now < deadline {
            if model.modelDownloadState == .downloading(progress: expected) {
                return
            }
            await Task.yield()
        }
        XCTFail("Il progress download non ha raggiunto \(expected).")
    }

    private func waitUntilTranscribing(_ model: TranscriptionModel) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while ContinuousClock.now < deadline {
            if case .transcribing = model.state {
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("La trascrizione non è entrata nello stato running.")
    }

    private func waitUntilFinished(_ model: TranscriptionModel) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while ContinuousClock.now < deadline {
            if model.state.isBusy == false, model.state != .idle {
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("La trascrizione non ha raggiunto uno stato terminale.")
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
}

private actor StubTranscriptionEngine: TranscriptionProcessing {
    enum Mode {
        case success
        case failure
        case waitForCancellation
    }

    let mode: Mode
    private(set) var wasCancelled = false
    private(set) var transcribeCallCount = 0

    init(mode: Mode) {
        self.mode = mode
    }

    func transcribe(
        mediaURL: URL,
        modelLocations: WhisperModelStore.BundleModelLocations,
        phaseCallback: TranscriptionPhaseCallback?,
        progressCallback: TranscriptionProgressCallback?
    ) async throws -> TranscriptionOutput {
        transcribeCallCount += 1
        await phaseCallback?(.loadingModel)
        await phaseCallback?(.transcribing)
        await progressCallback?(0.42)

        if mode == .waitForCancellation {
            while true {
                try await Task.sleep(for: .seconds(1))
            }
        }
        if mode == .failure {
            throw TestTranscriptionError.failed
        }

        return TranscriptionOutputFormatter.makeOutput(
            from: [TranscriptionCueDraft(start: 0, end: 1, text: "Ciao")]
        )
    }

    func cancel() {
        wasCancelled = true
    }
}

private actor StubModelDownloader: WhisperModelDownloading {
    enum Mode {
        case success(WhisperModelStore.BundleModelLocations)
        case failure(Error)
    }

    let mode: Mode

    init(mode: Mode) {
        self.mode = mode
    }

    func downloadModel(
        progressCallback: WhisperModelDownloadProgressCallback?
    ) async throws -> WhisperModelStore.BundleModelLocations {
        progressCallback?(0.25)

        switch mode {
        case .success(let locations):
            progressCallback?(1)
            return locations
        case .failure(let error):
            throw error
        }
    }
}

private actor ControlledModelDownloader: WhisperModelDownloading {
    private struct Request {
        let progressCallback: WhisperModelDownloadProgressCallback?
        var continuation: CheckedContinuation<WhisperModelStore.BundleModelLocations, Error>?
    }

    private var requests: [Request] = []

    var requestCount: Int {
        requests.count
    }

    func downloadModel(
        progressCallback: WhisperModelDownloadProgressCallback?
    ) async throws -> WhisperModelStore.BundleModelLocations {
        try await withCheckedThrowingContinuation { continuation in
            requests.append(
                Request(
                    progressCallback: progressCallback,
                    continuation: continuation
                )
            )
        }
    }

    func emitProgress(_ progress: Double?, forRequestAt index: Int) {
        requests[index].progressCallback?(progress)
    }

    func succeedRequest(
        at index: Int,
        with locations: WhisperModelStore.BundleModelLocations
    ) {
        let continuation = requests[index].continuation
        requests[index].continuation = nil
        continuation?.resume(returning: locations)
    }

    func failRequest(at index: Int, with error: Error) {
        let continuation = requests[index].continuation
        requests[index].continuation = nil
        continuation?.resume(throwing: error)
    }
}

@MainActor
private struct ControlledDownloadHarness {
    let model: TranscriptionModel
    let downloader: ControlledModelDownloader
    let locations: WhisperModelStore.BundleModelLocations
}

private enum TestModelDownloadError: LocalizedError {
    case failed

    var errorDescription: String? {
        "Errore test"
    }
}

private enum TestTranscriptionError: LocalizedError {
    case failed

    var errorDescription: String? {
        "Errore di trascrizione test"
    }
}

final class TranscriptionMediaSymbolTests: XCTestCase {
    func testMP4UsesVideoSymbol() {
        XCTAssertEqual(
            TranscriptionMediaSymbol.systemName(
                for: URL(fileURLWithPath: "/tmp/Lezione.MP4")
            ),
            "video.fill"
        )
    }

    func testM4AUsesAudioSymbol() {
        XCTAssertEqual(
            TranscriptionMediaSymbol.systemName(
                for: URL(fileURLWithPath: "/tmp/Lezione.m4a")
            ),
            "waveform"
        )
    }
}

private nonisolated final class AvailabilityProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var availability: WhisperModelStore.Availability
    private var reads = 0

    init(_ availability: WhisperModelStore.Availability) {
        self.availability = availability
    }

    var readCount: Int {
        lock.withLock { reads }
    }

    func read() -> WhisperModelStore.Availability {
        lock.withLock {
            reads += 1
            return availability
        }
    }
}

@MainActor
private final class StubDestinationPicker: TranscriptionDestinationSelecting {
    let destination: TranscriptionDestination

    init(destination: TranscriptionDestination) {
        self.destination = destination
    }

    func selectDestination(
        suggestedBaseName: String,
        initialDirectoryURL: URL?,
        outputSelection: TranscriptionOutputSelection
    ) async -> TranscriptionDestination? {
        destination
    }

    func cancelActivePanel() {}
}

private struct PermissionDeniedOutputWriter: TranscriptionOutputWriting {
    func validateWriteAccess(to destination: TranscriptionDestination) throws {
        throw CocoaError(.fileWriteNoPermission)
    }

    func write(
        _ output: TranscriptionOutput,
        to destination: TranscriptionDestination
    ) throws -> TranscriptionWrittenFiles {
        XCTFail("La scrittura non deve iniziare senza il permesso alla cartella.")
        return TranscriptionWrittenFiles(srtURL: nil, txtURL: nil)
    }
}

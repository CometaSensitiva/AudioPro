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

    func testMissingModelDisablesAndRejectsTranscription() throws {
        let directory = try makeTemporaryDirectory()
        let mediaURL = directory.appendingPathComponent("Lezione.m4a")
        try Data("audio".utf8).write(to: mediaURL)
        let destination = TranscriptionDestination(
            directoryURL: directory,
            baseName: "Lezione",
            overwriteExisting: false
        )
        let message = "Whisper Large v3 non disponibile in questa build."
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
        XCTAssertEqual(model.modelStatusMessage, message)

        model.startTranscription()

        XCTAssertEqual(model.state, .failed(message: message))
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

        return TranscriptionOutputFormatter.makeOutput(
            from: [TranscriptionCueDraft(start: 0, end: 1, text: "Ciao")]
        )
    }

    func cancel() {
        wasCancelled = true
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

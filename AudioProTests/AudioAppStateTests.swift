import XCTest
import Combine
@testable import AudioPro

@MainActor
final class AudioAppStateTests: XCTestCase {
    private actor StubProcessor: ExportProcessing {
        let result: Result<Void, AudioProcessor.ProcessError>
        private(set) var processedFileURLs: [URL] = []

        init(result: Result<Void, AudioProcessor.ProcessError>) {
            self.result = result
        }

        func cancel() async {}

        func process(
            fileURLs: [URL],
            outputURL: URL,
            job: ExportJob,
            estimatedTotalDuration: Double?,
            progressCallback: ExportProgressCallback?
        ) async -> Result<Void, AudioProcessor.ProcessError> {
            processedFileURLs = fileURLs
            return result
        }
    }

    private actor BlockingProcessor: ExportProcessing {
        private var continuation: CheckedContinuation<Result<Void, AudioProcessor.ProcessError>, Never>?
        private var hasStarted = false

        func cancel() async {
            let continuation = self.continuation
            self.continuation = nil
            continuation?.resume(returning: .failure(.cancelled))
        }

        func process(
            fileURLs: [URL],
            outputURL: URL,
            job: ExportJob,
            estimatedTotalDuration: Double?,
            progressCallback: ExportProgressCallback?
        ) async -> Result<Void, AudioProcessor.ProcessError> {
            hasStarted = true
            return await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        }

        func waitUntilStarted() async {
            while hasStarted == false {
                await Task.yield()
            }
        }
    }

    private actor CancellationAwareProcessor: ExportProcessing {
        func cancel() async {}

        func process(
            fileURLs: [URL],
            outputURL: URL,
            job: ExportJob,
            estimatedTotalDuration: Double?,
            progressCallback: ExportProgressCallback?
        ) async -> Result<Void, AudioProcessor.ProcessError> {
            Task.isCancelled ? .failure(.cancelled) : .success(())
        }
    }

    private final class SpyNotifier: ExportNotifying {
        private(set) var notifiedURL: URL?

        func notifyExportFinished(outputURL: URL) {
            notifiedURL = outputURL
        }
    }

    private var cancellables: Set<AnyCancellable> = []

    func testMoveFilesMovesItemForward() throws {
        let state = AudioAppState()
        let files = mockFiles(names: ["a.m4a", "b.m4a", "c.m4a"])
        state.addFiles(files)
        
        state.moveFiles(from: IndexSet(integer: 0), to: 3)
        
        XCTAssertEqual(state.audioFiles.map(\.name), ["b.m4a", "c.m4a", "a.m4a"])
    }
    
    func testMoveFilesMovesItemBackward() throws {
        let state = AudioAppState()
        let files = mockFiles(names: ["a.m4a", "b.m4a", "c.m4a"])
        state.addFiles(files)
        
        state.moveFiles(from: IndexSet(integer: 2), to: 0)
        
        XCTAssertEqual(state.audioFiles.map(\.name), ["c.m4a", "a.m4a", "b.m4a"])
    }
    
    func testMoveFilesMarksReadyForNextExport() throws {
        let state = AudioAppState()
        state.addFiles(mockFiles(names: ["a.m4a", "b.m4a"]))
        state.processingState = .completed
        
        state.moveFiles(from: IndexSet(integer: 0), to: 1)
        
        XCTAssertEqual(state.processingState, .idle)
    }

    func testMoveFilesWithStableIDsPreservesRelativeOrder() {
        let state = AudioAppState()
        let files = mockFiles(names: ["a.m4a", "b.m4a", "c.m4a", "d.m4a"])
        state.addFiles(files)

        state.moveFiles(withIDs: [files[1].id, files[3].id], to: 0)

        XCTAssertEqual(state.audioFiles.map(\.name), ["b.m4a", "d.m4a", "a.m4a", "c.m4a"])
    }

    func testMoveFilesWithStableIDsMovesSelectionTowardEnd() {
        let state = AudioAppState()
        let files = mockFiles(names: ["a.m4a", "b.m4a", "c.m4a", "d.m4a"])
        state.addFiles(files)

        state.moveFiles(withIDs: [files[1].id, files[2].id], to: 4)

        XCTAssertEqual(state.audioFiles.map(\.name), ["a.m4a", "d.m4a", "b.m4a", "c.m4a"])
    }

    func testMoveFilesByOnePreservesSelectedBlockOrder() {
        let state = AudioAppState()
        let files = mockFiles(names: ["a.m4a", "b.m4a", "c.m4a", "d.m4a"])
        state.addFiles(files)

        state.moveFiles(withIDs: [files[1].id, files[2].id], by: 1)

        XCTAssertEqual(state.audioFiles.map(\.name), ["a.m4a", "d.m4a", "b.m4a", "c.m4a"])
    }

    func testMoveFilesWithUnknownIDsLeavesQueueUnchanged() {
        let state = AudioAppState()
        state.addFiles(mockFiles(names: ["a.m4a", "b.m4a"]))

        state.moveFiles(withIDs: [UUID()], to: 0)

        XCTAssertEqual(state.audioFiles.map(\.name), ["a.m4a", "b.m4a"])
    }

    func testRenameRejectsPathTraversalLikeNames() throws {
        let state = AudioAppState()
        let (file, originalURL, directoryURL) = try makeTemporaryAudioFile(named: "source.m4a")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        state.rename(file, to: "../evil")

        XCTAssertEqual(file.url.standardizedFileURL, originalURL.standardizedFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directoryURL.deletingLastPathComponent().appendingPathComponent("evil.m4a").path))
    }

    func testRenamePreservesExtensionWithinOriginalDirectory() throws {
        let state = AudioAppState()
        let (file, _, directoryURL) = try makeTemporaryAudioFile(named: "voice.m4a")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        state.rename(file, to: "renamed")

        XCTAssertEqual(file.url.lastPathComponent, "renamed.m4a")
        XCTAssertEqual(file.url.deletingLastPathComponent().standardizedFileURL, directoryURL.standardizedFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.url.path))
    }

    func testCompressionSettingsUseTargetSizeWhenAvailable() {
        var settings = CompressionSettings.medium
        settings.maxOutputSizeMB = 200

        let resolvedBitrate = settings.resolvedBitrateKbps(for: 7_200)

        XCTAssertEqual(Int(resolvedBitrate.rounded()), 222)
    }

    func testCompressionSettingsFallBackToPresetWhenTargetSizeMissing() {
        let settings = CompressionSettings.medium

        XCTAssertEqual(Int(settings.resolvedBitrateKbps(for: nil).rounded()), 96)
    }

    func testExportPreviewBlocksExportWhenTargetNeedsMetadata() {
        let state = AudioAppState()
        let file = AudioFile(url: URL(fileURLWithPath: "/tmp/loading.m4a"), loadMetadata: false)
        file.metadataState = .loading
        state.addFiles([file])

        state.compression.maxOutputSizeMB = 50

        XCTAssertFalse(state.exportPreview.canExport)
        XCTAssertEqual(
            state.exportPreview.validation,
            .loadingMetadata(message: "Attendi il completamento dell’analisi dei file per calcolare la dimensione massima.")
        )
    }

    func testExportPreviewUpdatesWhenMetadataArrive() {
        let state = AudioAppState()
        let file = AudioFile(url: URL(fileURLWithPath: "/tmp/ready.m4a"), loadMetadata: false)
        file.metadataState = .loading
        state.addFiles([file])
        state.compression.maxOutputSizeMB = 120

        file.duration = 600
        file.fileSize = 10_000_000
        file.codec = "aac "
        file.metadataState = .ready

        XCTAssertTrue(state.exportPreview.canExport)
        XCTAssertEqual(state.exportPreview.totalDuration, 600)
        XCTAssertEqual(Int(state.exportPreview.resolvedBitrateKbps?.rounded() ?? 0), 1600)
    }

    func testAudioAppStateForwardsChildObjectWillChange() {
        let state = AudioAppState()
        let file = AudioFile(url: URL(fileURLWithPath: "/tmp/child.m4a"), loadMetadata: false)
        state.addFiles([file])

        let expectation = expectation(description: "AudioAppState forwards child changes")
        state.objectWillChange
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)

        file.duration = 42

        wait(for: [expectation], timeout: 1.0)
    }

    func testVideoExportModeResetsToAudioOnlyWhenSelectionChanges() {
        let state = AudioAppState()
        let video = AudioFile(url: URL(fileURLWithPath: "/tmp/lesson.mp4"), loadMetadata: false)
        let audio = AudioFile(url: URL(fileURLWithPath: "/tmp/notes.m4a"), loadMetadata: false)
        state.addFiles([video])
        state.compression.exportMode = .videoCompressed

        state.addFiles([audio])

        XCTAssertEqual(state.compression.exportMode, .audioOnly)
    }

    func testExportModeSwitchPreservesAudioSettings() {
        let state = AudioAppState()
        state.compression.codec = .opus
        state.compression.sampleRate = .s48000
        state.compression.quality = 0.85
        state.compression.maxOutputSizeMB = 90

        state.compression.exportMode = .videoCompressed
        state.compression.exportMode = .audioOnly

        XCTAssertEqual(state.compression.codec, .opus)
        XCTAssertEqual(state.compression.sampleRate, .s48000)
        XCTAssertEqual(state.compression.quality, 0.85)
        XCTAssertEqual(state.compression.maxOutputSizeMB, 90)
    }

    func testExportDestinationDefaultsFollowEffectiveExportMode() {
        let state = AudioAppState()
        let video = AudioFile(url: URL(fileURLWithPath: "/tmp/lesson.mp4"), loadMetadata: false)
        state.addFiles([video])
        state.compression.exportMode = .videoCompressed

        XCTAssertEqual(state.exportDestinationDefaults.fileName, "lesson esportato.mp4")
        XCTAssertEqual(state.exportDestinationDefaults.allowedContentTypes, [.mpeg4Movie])

        state.compression.exportMode = .audioOnly

        XCTAssertEqual(state.exportDestinationDefaults.fileName, "lesson esportato.m4a")
        XCTAssertEqual(state.exportDestinationDefaults.allowedContentTypes, [.mpeg4Audio])
    }

    func testExportDestinationDefaultsFollowCodecAndCopyContainer() {
        let opusState = AudioAppState()
        opusState.addFiles(mockFiles(names: ["voice.wav"]))
        opusState.compression.codec = .opus

        XCTAssertEqual(opusState.exportDestinationDefaults.fileName, "voice esportato.opus")
        XCTAssertEqual(opusState.exportDestinationDefaults.allowedContentTypes, [.audio])

        let copyState = AudioAppState()
        copyState.addFiles(mockFiles(names: ["voice.wav"]))
        copyState.compression.codec = .copy

        XCTAssertEqual(copyState.exportDestinationDefaults.fileName, "voice esportato.wav")
        XCTAssertEqual(
            copyState.exportDestinationDefaults.allowedContentTypes.first?.preferredFilenameExtension,
            "wav"
        )
    }

    func testQueueMutationsAreFrozenUntilCancelledExportFinishes() async {
        let processor = BlockingProcessor()
        let notifier = SpyNotifier()
        let state = AudioAppState(processor: processor, notifier: notifier)
        let (realFile, originalURL, directoryURL) = try! makeTemporaryAudioFile(named: "a.m4a")
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let files = [realFile, mockFiles(names: ["b.m4a"])[0]]
        files.forEach { $0.metadataState = .ready }
        state.addFiles(files)

        state.startExport(to: URL(fileURLWithPath: "/tmp/frozen-export.m4a"))
        await processor.waitUntilStarted()

        state.moveFiles(withIDs: [files[0].id], to: 2)
        state.remove(files[0])
        state.addFiles(mockFiles(names: ["c.m4a"]))
        state.clearAll()
        state.rename(files[0], to: "renamed")

        XCTAssertEqual(state.audioFiles.map(\.name), ["a.m4a", "b.m4a"])
        XCTAssertEqual(realFile.url, originalURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalURL.path))
        XCTAssertTrue(state.canModifyQueue == false)

        await state.cancelExportAndWait()

        XCTAssertEqual(state.processingState, .idle)
        XCTAssertTrue(state.canModifyQueue)
        XCTAssertNil(notifier.notifiedURL)
    }

    func testImmediateCancellationStopsExportBeforeProcessorLaunch() async {
        let notifier = SpyNotifier()
        let state = AudioAppState(
            processor: CancellationAwareProcessor(),
            notifier: notifier
        )
        let file = AudioFile(
            url: URL(fileURLWithPath: "/tmp/immediate-cancel.m4a"),
            loadMetadata: false
        )
        file.metadataState = .ready
        state.addFiles([file])

        state.startExport(to: URL(fileURLWithPath: "/tmp/immediate-output.m4a"))
        await state.cancelExportAndWait()

        XCTAssertEqual(state.processingState, .idle)
        XCTAssertNil(state.lastCompletedOutputURL)
        XCTAssertNil(notifier.notifiedURL)
    }

    func testStartExportUsesInjectedProcessorAndNotifier() async {
        let processor = StubProcessor(result: .success(()))
        let notifier = SpyNotifier()
        let state = AudioAppState(processor: processor, notifier: notifier)
        let file = AudioFile(url: URL(fileURLWithPath: "/tmp/voice.m4a"), loadMetadata: false)
        file.metadataState = .ready
        state.addFiles([file])

        let outputURL = URL(fileURLWithPath: "/tmp/export.m4a")
        state.startExport(to: outputURL)

        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while ContinuousClock.now < deadline,
              state.processingState != .completed {
            try? await Task.sleep(for: .milliseconds(10))
        }

        let processedFileURLs = await processor.processedFileURLs
        XCTAssertEqual(processedFileURLs, [file.url])
        XCTAssertEqual(notifier.notifiedURL, outputURL)
        XCTAssertEqual(state.processingState, .completed)
        XCTAssertEqual(state.lastCompletedOutputURL, outputURL)
    }
    
    // MARK: - Helpers
    
    private func mockFiles(names: [String]) -> [AudioFile] {
        names.map { AudioFile(url: URL(fileURLWithPath: "/tmp/\($0)"), loadMetadata: false) }
    }

    private func makeTemporaryAudioFile(named name: String) throws -> (AudioFile, URL, URL) {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let fileURL = directoryURL.appendingPathComponent(name)
        try Data("test".utf8).write(to: fileURL)
        return (AudioFile(url: fileURL, loadMetadata: false), fileURL, directoryURL)
    }
}

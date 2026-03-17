import XCTest
import Combine
@testable import AudioPro

@MainActor
final class AudioAppStateTests: XCTestCase {
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
            .loadingMetadata(message: "Attendi il completamento dell'analisi file per calcolare il target in MB.")
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

import XCTest
@testable import AudioPro

@MainActor
final class AudioFileTests: XCTestCase {
    func testFinderPresentationMetadataRemainsCachedAfterSourceRemoval() async throws {
        let directory = try makeTemporaryDirectory()
        let fileURL = directory.appendingPathComponent("lezione.wav")
        try makeMinimalWAVData().write(to: fileURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_577_836_800)],
            ofItemAtPath: fileURL.path
        )
        let file = AudioFile(url: fileURL)

        await waitForMetadata(of: file)

        let cachedDate = file.formattedModifiedDate
        let cachedKind = file.kindLabel
        XCTAssertNotEqual(cachedDate, "—")
        XCTAssertFalse(cachedKind.isEmpty)

        try FileManager.default.removeItem(at: fileURL)

        XCTAssertEqual(file.formattedModifiedDate, cachedDate)
        XCTAssertEqual(file.kindLabel, cachedKind)
        XCTAssertFalse(file.isVideo)
    }

    func testChangingURLReloadsFinderPresentationMetadata() async throws {
        let directory = try makeTemporaryDirectory()
        let firstURL = directory.appendingPathComponent("prima.wav")
        let secondURL = directory.appendingPathComponent("seconda.wav")
        try makeMinimalWAVData().write(to: firstURL)
        try makeMinimalWAVData().write(to: secondURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_577_836_800)],
            ofItemAtPath: firstURL.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_735_689_600)],
            ofItemAtPath: secondURL.path
        )
        let file = AudioFile(url: firstURL)
        await waitForMetadata(of: file)
        let firstDate = file.formattedModifiedDate

        file.url = secondURL
        XCTAssertTrue(file.metadataState.isLoading)
        await waitForMetadata(of: file)

        XCTAssertNotEqual(file.formattedModifiedDate, "—")
        XCTAssertNotEqual(file.formattedModifiedDate, firstDate)
    }

    func testLoadMetadataFalseUsesExtensionFallbackWithoutFilesystemReads() {
        let missingVideoURL = URL(fileURLWithPath: "/path/that/does/not/exist/lezione.mp4")
        let file = AudioFile(url: missingVideoURL, loadMetadata: false)

        XCTAssertEqual(file.metadataState, .ready)
        XCTAssertTrue(file.isVideo)
        XCTAssertEqual(file.hasAudioTrack, true)
        XCTAssertEqual(file.hasVideoTrack, true)
        XCTAssertFalse(file.kindLabel.isEmpty)
        XCTAssertEqual(file.formattedModifiedDate, "—")

        file.url = URL(fileURLWithPath: "/another/missing/path/lezione.m4a")

        XCTAssertEqual(file.metadataState, .ready)
        XCTAssertFalse(file.isVideo)
        XCTAssertEqual(file.hasAudioTrack, true)
        XCTAssertEqual(file.hasVideoTrack, false)
        XCTAssertFalse(file.kindLabel.isEmpty)
        XCTAssertEqual(file.formattedModifiedDate, "—")
    }

    func testVideoClassificationUsesExtensionWhileMetadataIsLoading() {
        let video = AudioFile(
            url: URL(fileURLWithPath: "/path/that/does/not/exist/lezione.mp4")
        )
        let audio = AudioFile(
            url: URL(fileURLWithPath: "/path/that/does/not/exist/lezione.m4a")
        )

        XCTAssertEqual(video.metadataState, .loading)
        XCTAssertTrue(video.isVideo)
        XCTAssertFalse(video.kindLabel.isEmpty)
        XCTAssertEqual(audio.metadataState, .loading)
        XCTAssertFalse(audio.isVideo)
    }

    func testLoadedTrackMetadataOverridesExtensionInference() {
        let file = AudioFile(
            url: URL(fileURLWithPath: "/path/that/does/not/exist/audio-only.mp4"),
            loadMetadata: false
        )

        file.hasVideoTrack = false

        XCTAssertFalse(file.isVideo)
    }

    private func waitForMetadata(of file: AudioFile) async {
        for _ in 0..<200 {
            if file.metadataState.isLoading == false {
                return
            }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Il caricamento metadata non è terminato entro il timeout del test.")
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

    private func makeMinimalWAVData() -> Data {
        var data = Data()

        func appendASCII(_ value: String) {
            data.append(contentsOf: value.utf8)
        }

        func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
            var littleEndianValue = value.littleEndian
            withUnsafeBytes(of: &littleEndianValue) { bytes in
                data.append(contentsOf: bytes)
            }
        }

        appendASCII("RIFF")
        appendLittleEndian(UInt32(38))
        appendASCII("WAVE")
        appendASCII("fmt ")
        appendLittleEndian(UInt32(16))
        appendLittleEndian(UInt16(1))
        appendLittleEndian(UInt16(1))
        appendLittleEndian(UInt32(8_000))
        appendLittleEndian(UInt32(16_000))
        appendLittleEndian(UInt16(2))
        appendLittleEndian(UInt16(16))
        appendASCII("data")
        appendLittleEndian(UInt32(2))
        appendLittleEndian(UInt16(0))
        return data
    }
}

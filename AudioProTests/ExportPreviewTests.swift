import XCTest
@testable import AudioPro

@MainActor
final class ExportPreviewTests: XCTestCase {
    func testPresetPreviewUsesBaseBitrateForSingleFile() {
        let file = mockFile(name: "single.m4a", duration: 120, size: 5_000_000, codec: "aac ")
        let preview = ExportPreview.make(files: [file], compression: .medium)

        XCTAssertEqual(preview.validation, .ready)
        XCTAssertEqual(Int(preview.resolvedBitrateKbps?.rounded() ?? 0), 96)
        XCTAssertEqual(preview.bitrateLabel, "96 kbps")
    }

    func testTargetSizeUsesDurationBasedBitrate() {
        var settings = CompressionSettings.medium
        settings.maxOutputSizeMB = 200

        let file = mockFile(name: "long.m4a", duration: 7_200, size: 600_000_000, codec: "aac ")
        let preview = ExportPreview.make(files: [file], compression: settings)

        XCTAssertEqual(preview.validation, .ready)
        XCTAssertEqual(Int(preview.resolvedBitrateKbps?.rounded() ?? 0), 222)
    }

    func testCopyModeKeepsOriginalSizeEstimate() {
        var settings = CompressionSettings.medium
        settings.codec = .copy

        let file = mockFile(name: "copy.m4a", duration: 90, size: 8_500_000, codec: "aac ")
        let preview = ExportPreview.make(files: [file], compression: settings)

        XCTAssertEqual(preview.effectiveCodec, .copy)
        XCTAssertEqual(preview.bitrateLabel, "Originale")
        XCTAssertNotNil(preview.estimatedOutputSizeMB)
        XCTAssertEqual(preview.estimatedOutputSizeMB ?? 0, 8.5, accuracy: 0.001)
    }

    func testMultipleFilesAggregateDurationAndSize() {
        let files = [
            mockFile(name: "a.m4a", duration: 60, size: 2_000_000, codec: "aac "),
            mockFile(name: "b.m4a", duration: 120, size: 4_000_000, codec: "aac ")
        ]

        let preview = ExportPreview.make(files: files, compression: .medium)

        XCTAssertEqual(preview.totalDuration, 180)
        XCTAssertEqual(preview.totalFileSize, 6_000_000)
    }

    func testCopyModeFallsBackToAACForMultipleFiles() {
        var settings = CompressionSettings.medium
        settings.codec = .copy

        let files = [
            mockFile(name: "a.m4a", duration: 60, size: 2_000_000, codec: "aac "),
            mockFile(name: "b.m4a", duration: 60, size: 2_000_000, codec: "aac ")
        ]

        let preview = ExportPreview.make(files: files, compression: settings)

        XCTAssertEqual(preview.effectiveCodec, .aac)
        XCTAssertTrue(preview.usesMergeReencodeFallback)
        XCTAssertEqual(preview.bitrateLabel, "96 kbps")
    }

    private func mockFile(name: String, duration: TimeInterval, size: Int64, codec: String) -> AudioFile {
        let file = AudioFile(url: URL(fileURLWithPath: "/tmp/\(name)"), loadMetadata: false)
        file.duration = duration
        file.fileSize = size
        file.codec = codec
        file.metadataState = .ready
        return file
    }
}

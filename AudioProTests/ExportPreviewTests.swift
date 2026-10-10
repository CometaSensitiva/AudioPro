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
        XCTAssertEqual(preview.outputFormat, .source(fileExtension: "m4a"))
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
        XCTAssertEqual(preview.outputFormat, .m4a)
        XCTAssertTrue(preview.usesMergeReencodeFallback)
        XCTAssertEqual(preview.bitrateLabel, "96 kbps")
    }

    func testSingleVideoEnablesCompressedVideoMode() {
        var settings = CompressionSettings.medium
        settings.exportMode = .videoCompressed

        let file = mockFile(name: "lesson.mp4", duration: 2_400, size: 600_000_000, codec: "aac ")
        let preview = ExportPreview.make(files: [file], compression: settings)

        XCTAssertTrue(preview.isVideoCompressionEligible)
        XCTAssertTrue(preview.isVideoModeActive)
        XCTAssertEqual(preview.effectiveExportMode, .videoCompressed)
        XCTAssertEqual(preview.compressionSummary, VideoCompressionPreset.teamsLecture.summary)
        XCTAssertEqual(preview.outputFormat, .mp4)
        // Preset fisso 1500 kbps video + 128 kbps audio AAC.
        XCTAssertEqual(preview.estimatedOutputSizeMB ?? 0, 488.4, accuracy: 0.001)
        XCTAssertEqual(preview.savingsRatio ?? 0, 0.186, accuracy: 0.001)
        XCTAssertEqual(preview.estimatedOutputLabel, "≈488.40 MB")
        XCTAssertEqual(preview.savingsLabel, "≈19%")
    }

    func testVideoModeEstimateNeedsDuration() {
        var settings = CompressionSettings.medium
        settings.exportMode = .videoCompressed

        let file = AudioFile(url: URL(fileURLWithPath: "/tmp/pending.mp4"), loadMetadata: false)
        file.fileSize = 600_000_000
        file.metadataState = .loading

        let preview = ExportPreview.make(files: [file], compression: settings)

        XCTAssertTrue(preview.isVideoModeActive)
        XCTAssertNil(preview.estimatedOutputSizeMB)
        XCTAssertNil(preview.savingsRatio)
    }

    func testVideoModeFallsBackToAudioOnlyForMixedSelection() {
        var settings = CompressionSettings.medium
        settings.exportMode = .videoCompressed

        let files = [
            mockFile(name: "lesson.mp4", duration: 2_400, size: 600_000_000, codec: "aac "),
            mockFile(name: "notes.m4a", duration: 120, size: 4_000_000, codec: "aac ")
        ]

        let preview = ExportPreview.make(files: files, compression: settings)

        XCTAssertFalse(preview.isVideoCompressionEligible)
        XCTAssertFalse(preview.isVideoModeActive)
        XCTAssertEqual(preview.effectiveExportMode, .audioOnly)
        XCTAssertEqual(
            preview.videoModeAvailabilityMessage,
            "La modalità Video compresso è disponibile solo con un singolo file video. Con più file o sorgenti miste, l’esportazione resta solo audio."
        )
    }

    func testAudioOnlyMP4DoesNotEnableVideoCompression() {
        let file = mockFile(
            name: "audio-only.mp4",
            duration: 60,
            size: 4_000_000,
            codec: "aac "
        )
        file.hasAudioTrack = true
        file.hasVideoTrack = false

        let preview = ExportPreview.make(files: [file], compression: .medium)

        XCTAssertFalse(file.isVideo)
        XCTAssertFalse(preview.isVideoCompressionEligible)
        XCTAssertEqual(preview.effectiveExportMode, .audioOnly)
        XCTAssertEqual(preview.validation, .ready)
    }

    func testAudioExportRejectsInputWithoutAudioButVideoModeAllowsIt() {
        let file = mockFile(
            name: "silent-video.mp4",
            duration: 60,
            size: 8_000_000,
            codec: ""
        )
        file.hasAudioTrack = false
        file.hasVideoTrack = true

        let audioPreview = ExportPreview.make(files: [file], compression: .medium)
        XCTAssertFalse(audioPreview.canExport)
        guard case .failedPreflight(let message) = audioPreview.validation else {
            return XCTFail("Expected missing-audio preflight failure")
        }
        XCTAssertTrue(message.contains("traccia audio"))

        var videoSettings = CompressionSettings.medium
        videoSettings.exportMode = .videoCompressed
        let videoPreview = ExportPreview.make(files: [file], compression: videoSettings)
        XCTAssertTrue(videoPreview.canExport)
        XCTAssertEqual(videoPreview.effectiveExportMode, .videoCompressed)
    }

    func testOpusUsesOpusContainer() {
        var settings = CompressionSettings.medium
        settings.codec = .opus

        let preview = ExportPreview.make(
            files: [mockFile(name: "lesson.wav", duration: 60, size: 8_000_000, codec: "lpcm")],
            compression: settings
        )

        XCTAssertEqual(preview.validation, .ready)
        XCTAssertEqual(preview.outputFormat, .opus)
        guard case .audio(let jobSettings)? = preview.exportJob else {
            return XCTFail("Expected an audio export job")
        }
        XCTAssertEqual(jobSettings.outputFormat, .opus)
        XCTAssertEqual(jobSettings.codec, "libopus")
    }

    func testSingleFileCopyPreservesSourceExtension() {
        var settings = CompressionSettings.medium
        settings.codec = .copy

        let preview = ExportPreview.make(
            files: [mockFile(name: "recording.wav", duration: 60, size: 8_000_000, codec: "lpcm")],
            compression: settings
        )

        XCTAssertEqual(preview.validation, .ready)
        XCTAssertEqual(preview.outputFormat, .source(fileExtension: "wav"))
        guard case .audio(let jobSettings)? = preview.exportJob else {
            return XCTFail("Expected an audio export job")
        }
        XCTAssertEqual(jobSettings.outputFormat, .source(fileExtension: "wav"))
        XCTAssertEqual(jobSettings.codec, "copy")
    }

    func testCopyWithoutSafeSourceExtensionFailsPreflight() {
        var settings = CompressionSettings.medium
        settings.codec = .copy
        let file = mockFile(name: "recording", duration: 60, size: 8_000_000, codec: "lpcm")

        let preview = ExportPreview.make(files: [file], compression: settings)

        XCTAssertFalse(preview.canExport)
        XCTAssertNil(preview.outputFormat)
        XCTAssertNil(preview.exportJob)
        guard case .failedPreflight = preview.validation else {
            return XCTFail("Expected a failed preflight")
        }
    }

    func testALACTargetSizeFailsPreflightInsteadOfAdvertisingLossyBitrate() {
        var settings = CompressionSettings.medium
        settings.codec = .alac
        settings.maxOutputSizeMB = 20

        let preview = ExportPreview.make(
            files: [mockFile(name: "lesson.wav", duration: 60, size: 8_000_000, codec: "lpcm")],
            compression: settings
        )

        XCTAssertFalse(preview.canExport)
        XCTAssertEqual(preview.outputFormat, .m4a)
        XCTAssertNil(preview.resolvedBitrateKbps)
        XCTAssertNil(preview.targetSizeMB)
        XCTAssertNil(preview.exportJob)
        guard case .failedPreflight(let message) = preview.validation else {
            return XCTFail("Expected a failed preflight")
        }
        XCTAssertTrue(message.contains("ALAC"))
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

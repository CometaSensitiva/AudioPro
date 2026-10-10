import XCTest
@testable import AudioPro

final class AudioProcessorCommandBuilderTests: XCTestCase {
    func testAudioCommandBuilderKeepsAudioOnlyPipeline() throws {
        let arguments = try FFmpegCommandBuilder.makeArguments(
            fileURLs: [URL(fileURLWithPath: "/tmp/lesson.mp4")],
            outputURL: URL(fileURLWithPath: "/tmp/output.m4a"),
            job: .audio(
                AudioExportSettings(
                    codec: "copy",
                    bitrate: "",
                    sampleRate: "44100",
                    outputFormat: .source(fileExtension: "m4a")
                )
            )
        )

        XCTAssertEqual(
            arguments,
            [
                "-nostdin",
                "-protocol_whitelist", "file",
                "-i", "/tmp/lesson.mp4",
                "-vn",
                "-c:a", "copy",
                "-n",
                "/tmp/output.m4a"
            ]
        )
    }

    func testVideoCommandBuilderUsesFixedCompressionPreset() throws {
        let arguments = try FFmpegCommandBuilder.makeArguments(
            fileURLs: [URL(fileURLWithPath: "/tmp/lesson.mp4")],
            outputURL: URL(fileURLWithPath: "/tmp/output.mp4"),
            job: .videoCompressed(.teamsLecture)
        )

        XCTAssertEqual(
            arguments,
            [
                "-nostdin",
                "-protocol_whitelist", "file",
                "-i", "/tmp/lesson.mp4",
                "-map", "0:v:0",
                "-map", "0:a?",
                "-c:v", "hevc_videotoolbox",
                "-b:v", "1500k",
                "-tag:v", "hvc1",
                "-vf", "scale=1920:-2,fps=30",
                "-c:a", "aac",
                "-b:a", "128k",
                "-n",
                "/tmp/output.mp4"
            ]
        )
        XCTAssertFalse(arguments.contains("-vn"))
        XCTAssertFalse(arguments.contains("-y"))
    }

    func testALACOmitsBitrateButKeepsSampleRate() throws {
        let arguments = try FFmpegCommandBuilder.makeArguments(
            fileURLs: [URL(fileURLWithPath: "/tmp/lesson.wav")],
            outputURL: URL(fileURLWithPath: "/tmp/output.m4a"),
            job: .audio(
                AudioExportSettings(
                    codec: "alac",
                    bitrate: "96k",
                    sampleRate: "48000",
                    outputFormat: .m4a
                )
            )
        )

        XCTAssertTrue(arguments.contains("alac"))
        XCTAssertFalse(arguments.contains("-b:a"))
        XCTAssertEqual(arguments.suffix(2), ["-n", "/tmp/output.m4a"])
        XCTAssertTrue(arguments.contains("48000"))
    }

    func testEveryMergedInputUsesLocalProtocolWhitelist() throws {
        let arguments = try FFmpegCommandBuilder.makeArguments(
            fileURLs: [
                URL(fileURLWithPath: "/tmp/one.wav"),
                URL(fileURLWithPath: "/tmp/two.wav"),
            ],
            outputURL: URL(fileURLWithPath: "/tmp/output.opus"),
            job: .audio(
                AudioExportSettings(
                    codec: "libopus",
                    bitrate: "96k",
                    sampleRate: "48000",
                    outputFormat: .opus
                )
            )
        )

        let inputIndexes = arguments.indices.filter { arguments[$0] == "-i" }
        XCTAssertEqual(inputIndexes.count, 2)
        for index in inputIndexes {
            XCTAssertGreaterThanOrEqual(index, 2)
            XCTAssertEqual(arguments[index - 2], "-protocol_whitelist")
            XCTAssertEqual(arguments[index - 1], "file")
        }
        XCTAssertFalse(arguments.contains("-y"))
    }

    func testOutputExtensionMustMatchJobContract() {
        XCTAssertThrowsError(
            try FFmpegCommandBuilder.makeArguments(
                fileURLs: [URL(fileURLWithPath: "/tmp/lesson.wav")],
                outputURL: URL(fileURLWithPath: "/tmp/output.m4a"),
                job: .audio(
                    AudioExportSettings(
                        codec: "libopus",
                        bitrate: "96k",
                        sampleRate: "48000",
                        outputFormat: .opus
                    )
                )
            )
        ) { error in
            guard case FFmpegCommandBuilder.BuilderError.outputFormatMismatch = error else {
                return XCTFail("Expected outputFormatMismatch, got \(error)")
            }
        }
    }
}

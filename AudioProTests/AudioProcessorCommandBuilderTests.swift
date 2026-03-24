import XCTest
@testable import AudioPro

final class AudioProcessorCommandBuilderTests: XCTestCase {
    func testAudioCommandBuilderKeepsAudioOnlyPipeline() throws {
        let arguments = try FFmpegCommandBuilder.makeArguments(
            fileURLs: [URL(fileURLWithPath: "/tmp/lesson.mp4")],
            outputURL: URL(fileURLWithPath: "/tmp/output.m4a"),
            job: .audio(AudioExportSettings(codec: "copy", bitrate: "", sampleRate: "44100"))
        )

        XCTAssertEqual(
            arguments,
            [
                "-i", "/tmp/lesson.mp4",
                "-vn",
                "-c:a", "copy",
                "-y",
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
                "-i", "/tmp/lesson.mp4",
                "-map", "0:v:0",
                "-map", "0:a?",
                "-c:v", "hevc_videotoolbox",
                "-b:v", "1500k",
                "-tag:v", "hvc1",
                "-vf", "scale=1920:-2,fps=30",
                "-c:a", "copy",
                "-y",
                "/tmp/output.mp4"
            ]
        )
        XCTAssertFalse(arguments.contains("-vn"))
    }
}

import XCTest
@testable import AudioPro

final class FFmpegBinaryVerifierTests: XCTestCase {
    func testVendoredArm64BinaryMatchesExpectedHash() {
        let verifier = FFmpegBinaryVerifier(helperDirectory: "Contents/Helpers")

        XCTAssertTrue(
            verifier.verifyVendoredBinary(
                atPath: absolutePath("AudioPro/ffmpeg-binary-arm64")
            )
        )
    }

    func testVendoredX8664BinaryMatchesExpectedHash() {
        let verifier = FFmpegBinaryVerifier(helperDirectory: "Contents/Helpers")

        XCTAssertTrue(
            verifier.verifyVendoredBinary(
                atPath: absolutePath("AudioPro/ffmpeg-binary-x86_64")
            )
        )
    }

    func testVerifierRejectsSwappedVariantBinary() throws {
        let verifier = FFmpegBinaryVerifier(helperDirectory: "Contents/Helpers")
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let sourcePath = absolutePath("AudioPro/ffmpeg-binary-arm64")
        let destinationURL = directoryURL.appendingPathComponent("ffmpeg-binary-x86_64")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: sourcePath), to: destinationURL)

        XCTAssertFalse(verifier.verifyVendoredBinary(atPath: destinationURL.path))
    }

    private func absolutePath(_ relativePath: String) -> String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
            .path
    }
}

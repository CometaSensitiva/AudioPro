import XCTest
@testable import AudioPro

final class FFmpegProcessRunnerTests: XCTestCase {
    func testRunCompletesForFastSuccessfulProcess() async {
        let runner = FFmpegProcessRunner()

        let result = await runner.run(
            path: "/usr/bin/true",
            arguments: [],
            inputCount: 0,
            estimatedTotalDuration: 0,
            progressCallback: nil
        )

        switch result {
        case .success:
            break
        case .failure(let error):
            XCTFail("Expected success, got \(error.localizedDescription)")
        }
    }

    func testRunReturnsFailureForFastFailingProcess() async {
        let runner = FFmpegProcessRunner()

        let result = await runner.run(
            path: "/usr/bin/false",
            arguments: [],
            inputCount: 0,
            estimatedTotalDuration: 0,
            progressCallback: nil
        )

        switch result {
        case .success:
            XCTFail("Expected failure for /usr/bin/false")
        case .failure(let error):
            guard case .ffmpegFailed = error else {
                return XCTFail("Expected ffmpegFailed, got \(error)")
            }
        }
    }
}

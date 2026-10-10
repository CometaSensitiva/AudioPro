import XCTest
@testable import AudioPro

@MainActor
final class PlayerControllerTests: XCTestCase {
    func testFailedLoadRestoresEmptyStateAndKeepsDismissibleError() async {
        let controller = PlayerController()
        controller.setPlaybackRate(2)
        controller.updateCurrentTime(42)

        let missingMediaURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        controller.loadMedia(from: missingMediaURL)
        await waitForLoadFailure(controller)

        XCTAssertNotNil(controller.errorMessage)
        XCTAssertFalse(controller.hasMedia)
        XCTAssertFalse(controller.hasVideo)
        XCTAssertNil(controller.videoAspectRatio)
        XCTAssertNil(controller.mediaURL)
        XCTAssertNil(controller.mediaName)
        XCTAssertNil(controller.player.currentItem)
        XCTAssertEqual(controller.currentTime, 0)
        XCTAssertEqual(controller.duration, 0)
        XCTAssertEqual(controller.playbackRate, 1)
        XCTAssertEqual(controller.player.defaultRate, 1)

        controller.dismissError()
        XCTAssertNil(controller.errorMessage)
    }

    private func waitForLoadFailure(_ controller: PlayerController) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if controller.errorMessage != nil {
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Il caricamento non valido non ha prodotto un errore.")
    }
}

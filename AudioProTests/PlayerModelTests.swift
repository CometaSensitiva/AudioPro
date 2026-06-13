import XCTest
@testable import AudioPro

@MainActor
final class PlayerModelTests: XCTestCase {
    func testCurrentTimeUpdatesActiveSubtitleOutsideTheView() {
        let controller = PlayerController()
        let model = PlayerModel(playerController: controller)
        model.cues = [
            SubtitleCue(id: 1, start: 0, end: 2, text: "Prima"),
            SubtitleCue(id: 2, start: 3, end: 5, text: "Seconda"),
        ]

        controller.updateCurrentTime(4)

        XCTAssertEqual(model.activeCueID, 2)
    }
}

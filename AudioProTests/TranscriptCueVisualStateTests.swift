import XCTest
@testable import AudioPro

final class TranscriptCueVisualStateTests: XCTestCase {
    func testActiveCueKeepsCurrentSearchMatchEmphasis() {
        let state = TranscriptCueVisualState(
            cueID: 7,
            activeCueID: 7,
            matchIDs: [7, 9],
            currentMatchID: 7
        )

        XCTAssertTrue(state.showsActiveAccent)
        XCTAssertTrue(state.showsSearchIndicator)
        XCTAssertTrue(state.showsCurrentMatchOutline)
    }

    func testOrdinarySearchMatchDoesNotUseCurrentMatchOutline() {
        let state = TranscriptCueVisualState(
            cueID: 9,
            activeCueID: 7,
            matchIDs: [7, 9],
            currentMatchID: 7
        )

        XCTAssertFalse(state.showsActiveAccent)
        XCTAssertTrue(state.showsSearchIndicator)
        XCTAssertFalse(state.showsCurrentMatchOutline)
    }
}

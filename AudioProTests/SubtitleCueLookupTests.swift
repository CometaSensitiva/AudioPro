import XCTest
@testable import AudioPro

final class SubtitleCueLookupTests: XCTestCase {
    private let cues = [
        SubtitleCue(id: 10, start: 1, end: 3, text: "Prima"),
        SubtitleCue(id: 20, start: 5, end: 7, text: "Seconda"),
        SubtitleCue(id: 30, start: 10, end: 12, text: "Terza")
    ]

    func testReturnsNilForEmptyCueList() {
        XCTAssertNil(SubtitleCueLookup.activeCueID(in: [], at: 1))
    }

    func testFindsFirstAndLastCue() {
        XCTAssertEqual(SubtitleCueLookup.activeCueID(in: cues, at: 2), 10)
        XCTAssertEqual(SubtitleCueLookup.activeCueID(in: cues, at: 11), 30)
    }

    func testReturnsNilBeforeFirstCueAndInsideGap() {
        XCTAssertNil(SubtitleCueLookup.activeCueID(in: cues, at: 0.5))
        XCTAssertNil(SubtitleCueLookup.activeCueID(in: cues, at: 4))
        XCTAssertNil(SubtitleCueLookup.activeCueID(in: cues, at: 8))
    }

    func testIncludesCueStartAndEndBoundaries() {
        XCTAssertEqual(SubtitleCueLookup.activeCueID(in: cues, at: 5), 20)
        XCTAssertEqual(SubtitleCueLookup.activeCueID(in: cues, at: 7), 20)
    }

    func testReturnsNilAfterLastCueAndForNonFiniteTime() {
        XCTAssertNil(SubtitleCueLookup.activeCueID(in: cues, at: 13))
        XCTAssertNil(SubtitleCueLookup.activeCueID(in: cues, at: .infinity))
    }

    func testFindsEnclosingCueWhenCuesOverlap() {
        let overlapping = [
            SubtitleCue(id: 1, start: 0, end: 10, text: "Esterna"),
            SubtitleCue(id: 2, start: 5, end: 8, text: "Interna")
        ]
        XCTAssertEqual(SubtitleCueLookup.activeCueID(in: overlapping, at: 6), 2)
        XCTAssertEqual(SubtitleCueLookup.activeCueID(in: overlapping, at: 9), 1)
        XCTAssertNil(SubtitleCueLookup.activeCueID(in: overlapping, at: 11))
    }
}

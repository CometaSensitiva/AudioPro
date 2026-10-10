import XCTest
@testable import AudioPro

@MainActor
final class ExportQueueContentStateTests: XCTestCase {
    func testEmptyQueueKeepsPrimaryEmptyStateEvenWithStaleSearchText() {
        let state = ExportQueueContentState(
            fileCount: 0,
            filteredFileCount: 0,
            searchText: "lezione"
        )

        XCTAssertEqual(state, .emptyQueue)
    }

    func testNonMatchingFilterUsesContextualSearchEmptyState() {
        let state = ExportQueueContentState(
            fileCount: 3,
            filteredFileCount: 0,
            searchText: "  laboratorio  "
        )

        XCTAssertEqual(state, .noSearchResults(query: "laboratorio"))
    }

    func testBlankOrMatchingFilterKeepsFileTable() {
        XCTAssertEqual(
            ExportQueueContentState(
                fileCount: 3,
                filteredFileCount: 3,
                searchText: "   "
            ),
            .files
        )
        XCTAssertEqual(
            ExportQueueContentState(
                fileCount: 3,
                filteredFileCount: 1,
                searchText: "lezione"
            ),
            .files
        )
    }
}

import XCTest
@testable import AudioPro

final class ProcessLogTailTests: XCTestCase {
    func testAppendWithinCapacityKeepsFullPayload() {
        var tail = ProcessLogTail(maxBytes: 16)
        tail.append(Data("hello".utf8))
        tail.append(Data(" world".utf8))

        XCTAssertEqual(tail.stringValue, "hello world")
    }

    func testAppendBeyondCapacityKeepsSuffix() {
        var tail = ProcessLogTail(maxBytes: 8)
        tail.append(Data("1234567890".utf8))

        XCTAssertEqual(tail.stringValue, "34567890")
    }

    func testMultipleAppendsTrimToLastBytesOnly() {
        var tail = ProcessLogTail(maxBytes: 10)
        tail.append(Data("abc".utf8))
        tail.append(Data("defgh".utf8))
        tail.append(Data("ijklmnop".utf8))

        XCTAssertEqual(tail.stringValue, "ghijklmnop")
    }
}

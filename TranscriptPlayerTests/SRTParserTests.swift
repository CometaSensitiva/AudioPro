import XCTest

final class SRTParserTests: XCTestCase {
    func testParsesCRLFTimestampsAndMultilineText() {
        let source = """
        1\r
        00:00:01,250 --> 00:00:03.500\r
        Prima riga\r
        Seconda riga\r
        \r
        2\r
        00:00:04,000 --> 00:00:05,000\r
        Fine\r
        """

        let cues = SRTParser.parse(source)

        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0].start, 1.25, accuracy: 0.001)
        XCTAssertEqual(cues[0].end, 3.5, accuracy: 0.001)
        XCTAssertEqual(cues[0].text, "Prima riga\nSeconda riga")
    }

    func testParsesCueWithoutNumericIndex() {
        let cues = SRTParser.parse(
            "00:00:02,000 --> 00:00:03,000\nTesto senza indice"
        )

        XCTAssertEqual(cues.count, 1)
        XCTAssertEqual(cues[0].text, "Testo senza indice")
    }

    func testSortsCuesAndAssignsStableIDs() {
        let source = """
        2
        00:00:10,000 --> 00:00:11,000
        Seconda

        1
        00:00:01,000 --> 00:00:02,000
        Prima
        """

        let cues = SRTParser.parse(source)

        XCTAssertEqual(cues.map(\.text), ["Prima", "Seconda"])
        XCTAssertEqual(cues.map(\.id), [0, 1])
    }

    func testDropsMalformedEmptyAndReversedCues() {
        let source = """
        1
        not-a-time --> 00:00:02,000
        Malformata

        2
        00:00:03,000 --> 00:00:02,000
        Invertita

        3
        00:00:04,000 --> 00:00:05,000

        4
        00:00:06,000 --> 00:00:07,000
        Valida

        5
        00:61:00,000 --> 00:62:00,000
        Fuori scala

        6
        01:02 --> 01:03
        Abbreviata
        """

        let cues = SRTParser.parse(source)

        XCTAssertEqual(cues.count, 1)
        XCTAssertEqual(cues[0].text, "Valida")
    }

    func testLoadsLatin1WhenUTF8DecodingFails() throws {
        let source = "1\n00:00:01,000 --> 00:00:02,000\nCaffè"
        let data = try XCTUnwrap(source.data(using: .isoLatin1))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("srt")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let cues = try SRTParser.load(from: url)

        XCTAssertEqual(cues.count, 1)
        XCTAssertEqual(cues[0].text, "Caffè")
    }

    func testStripsUTF8ByteOrderMark() {
        let cues = SRTParser.parse(
            "\u{FEFF}1\n00:00:01,000 --> 00:00:02,000\nTesto"
        )

        XCTAssertEqual(cues.count, 1)
        XCTAssertEqual(cues[0].text, "Testo")
    }
}

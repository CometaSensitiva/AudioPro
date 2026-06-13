import XCTest
@testable import AudioPro

final class TranscriptionOutputFormatterTests: XCTestCase {
    func testBuildsCleanSubtitleCuesFromDrafts() {
        let drafts = [
            TranscriptionCueDraft(
                start: 3.2,
                end: 4.4,
                text: "<|startoftranscript|><|it|> Secondo segmento "
            ),
            TranscriptionCueDraft(
                start: 1.2345,
                end: 2.0,
                text: " Primo segmento "
            ),
            TranscriptionCueDraft(start: 5, end: 4, text: "Invertito"),
            TranscriptionCueDraft(start: 6, end: 7, text: "   ")
        ]

        let output = TranscriptionOutputFormatter.makeOutput(from: drafts)

        XCTAssertEqual(output.cues.count, 2)
        XCTAssertEqual(output.cues.map(\.id), [0, 1])
        XCTAssertEqual(output.cues.map(\.text), ["Primo segmento", "Secondo segmento"])
    }

    func testFormatsSRTWithRoundedMillisecondsAndTrailingNewline() {
        let cues = [
            SubtitleCue(id: 0, start: 1.2345, end: 2, text: "Primo"),
            SubtitleCue(id: 1, start: 3.2, end: 65.6784, text: "Secondo")
        ]

        let srt = TranscriptionOutputFormatter.makeSRT(from: cues)

        XCTAssertEqual(
            srt,
            """
            1
            00:00:01,235 --> 00:00:02,000
            Primo

            2
            00:00:03,200 --> 00:01:05,678
            Secondo

            """
        )
    }

    func testFormatsPlainText() {
        let cues = [
            SubtitleCue(id: 0, start: 1, end: 2, text: "Prima riga"),
            SubtitleCue(id: 1, start: 3, end: 4, text: "Seconda riga")
        ]

        XCTAssertEqual(
            TranscriptionOutputFormatter.makePlainText(from: cues),
            "Prima riga\nSeconda riga\n"
        )
    }
}

import Foundation
import XCTest
@testable import AudioPro

@MainActor
final class AudioProCommandContextTests: XCTestCase {
    func testExportContextUsesQueueSpecificLabelsAndEnablement() {
        var didAddFiles = false
        var didSearch = false
        let context = AudioProCommandContext.export(
            canAddFiles: false,
            addFiles: { didAddFiles = true },
            canSearchQueue: true,
            searchQueue: { didSearch = true }
        )

        XCTAssertEqual(context.primaryFileAction.title, "Aggiungi file…")
        XCTAssertFalse(context.primaryFileAction.isEnabled)
        XCTAssertNil(context.secondaryFileAction)
        XCTAssertEqual(context.searchAction?.title, "Cerca nella coda…")
        XCTAssertEqual(context.searchAction?.isEnabled, true)

        context.primaryFileAction.perform()
        context.searchAction?.perform()
        XCTAssertTrue(didAddFiles)
        XCTAssertTrue(didSearch)
    }

    func testTranscriptionContextOmitsIrrelevantActions() {
        var didChooseMedia = false
        let context = AudioProCommandContext.transcription(
            canChooseMedia: true,
            chooseMedia: { didChooseMedia = true }
        )

        XCTAssertEqual(context.primaryFileAction.title, "Scegli file…")
        XCTAssertTrue(context.primaryFileAction.isEnabled)
        XCTAssertNil(context.secondaryFileAction)
        XCTAssertNil(context.searchAction)
        XCTAssertNil(context.playback)

        context.primaryFileAction.perform()
        XCTAssertTrue(didChooseMedia)
    }

    func testPlayerContextKeepsMediaTranscriptAndPlaybackActionsTogether() {
        var didOpenMedia = false
        var didOpenSRT = false
        var didSearch = false
        var didTogglePlayback = false
        var seekDeltas: [TimeInterval] = []
        let playback = AudioProCommandContext.Playback(
            isPlaying: true,
            hasMedia: true,
            togglePlayback: { didTogglePlayback = true },
            seekBy: { seekDeltas.append($0) }
        )
        let context = AudioProCommandContext.player(
            canOpenMedia: true,
            openMedia: { didOpenMedia = true },
            canOpenSRT: false,
            openSRT: { didOpenSRT = true },
            canSearchTranscript: true,
            searchTranscript: { didSearch = true },
            playback: playback
        )

        XCTAssertEqual(context.primaryFileAction.title, "Apri file…")
        XCTAssertTrue(context.primaryFileAction.isEnabled)
        XCTAssertEqual(context.secondaryFileAction?.title, "Apri SRT…")
        XCTAssertEqual(context.secondaryFileAction?.isEnabled, false)
        XCTAssertEqual(context.searchAction?.title, "Cerca nella trascrizione…")
        XCTAssertEqual(context.searchAction?.isEnabled, true)
        XCTAssertEqual(context.playback?.isPlaying, true)
        XCTAssertEqual(context.playback?.hasMedia, true)

        context.primaryFileAction.perform()
        context.secondaryFileAction?.perform()
        context.searchAction?.perform()
        context.playback?.togglePlayback()
        context.playback?.seekBy(-5)
        context.playback?.seekBy(5)

        XCTAssertTrue(didOpenMedia)
        XCTAssertTrue(didOpenSRT)
        XCTAssertTrue(didSearch)
        XCTAssertTrue(didTogglePlayback)
        XCTAssertEqual(seekDeltas, [-5, 5])
    }
}

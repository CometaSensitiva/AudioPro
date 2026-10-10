import XCTest
@testable import AudioPro

final class TranscriptionOutputWriterTests: XCTestCase {
    func testClassifiesMissingOutputAsMissing() throws {
        let directory = try makeTemporaryDirectory()
        let missingURL = directory.appendingPathComponent("non-esiste.srt")

        XCTAssertEqual(
            TranscriptionOutputPathClassifier.kind(at: missingURL),
            .missing
        )
    }

    func testWritesSRTAndTXTAsOneCompletedPair() throws {
        let directory = try makeTemporaryDirectory()
        let destination = TranscriptionDestination(
            directoryURL: directory,
            baseName: "Lezione 12",
            overwriteExisting: false
        )

        let urls = try TranscriptionOutputWriter().write(sampleOutput, to: destination)

        XCTAssertEqual(
            try String(contentsOf: XCTUnwrap(urls.srtURL), encoding: .utf8),
            sampleOutput.srtText
        )
        XCTAssertEqual(
            try String(contentsOf: XCTUnwrap(urls.txtURL), encoding: .utf8),
            sampleOutput.plainText
        )
        XCTAssertFalse(try directoryContainsTransactionFiles(directory))
    }

    func testWritesOnlySRT() throws {
        let directory = try makeTemporaryDirectory()
        let destination = TranscriptionDestination(
            directoryURL: directory,
            baseName: "Lezione",
            outputSelection: .srtOnly,
            overwriteExisting: false
        )

        let urls = try TranscriptionOutputWriter().write(sampleOutput, to: destination)

        XCTAssertEqual(urls.srtURL, destination.srtURL)
        XCTAssertNil(urls.txtURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.srtURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.txtURL.path))
    }

    func testWritesOnlyTXT() throws {
        let directory = try makeTemporaryDirectory()
        let destination = TranscriptionDestination(
            directoryURL: directory,
            baseName: "Lezione",
            outputSelection: .txtOnly,
            overwriteExisting: false
        )

        let urls = try TranscriptionOutputWriter().write(sampleOutput, to: destination)

        XCTAssertNil(urls.srtURL)
        XCTAssertEqual(urls.txtURL, destination.txtURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.srtURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.txtURL.path))
    }

    func testRefusesExistingOutputWithoutOverwrite() throws {
        let directory = try makeTemporaryDirectory()
        let destination = TranscriptionDestination(
            directoryURL: directory,
            baseName: "Lezione",
            overwriteExisting: false
        )
        try "originale".write(to: destination.srtURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try TranscriptionOutputWriter().write(sampleOutput, to: destination)) { error in
            XCTAssertEqual(error as? TranscriptionOutputWriter.WriteError, .outputAlreadyExists)
        }
        XCTAssertEqual(try String(contentsOf: destination.srtURL, encoding: .utf8), "originale")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.txtURL.path))
    }

    func testOverwritesBothFilesOnlyAfterStagingCompletes() throws {
        let directory = try makeTemporaryDirectory()
        let destination = TranscriptionDestination(
            directoryURL: directory,
            baseName: "Lezione",
            overwriteExisting: true
        )
        try "vecchio srt".write(to: destination.srtURL, atomically: true, encoding: .utf8)
        try "vecchio txt".write(to: destination.txtURL, atomically: true, encoding: .utf8)

        _ = try TranscriptionOutputWriter().write(sampleOutput, to: destination)

        XCTAssertEqual(try String(contentsOf: destination.srtURL, encoding: .utf8), sampleOutput.srtText)
        XCTAssertEqual(try String(contentsOf: destination.txtURL, encoding: .utf8), sampleOutput.plainText)
        XCTAssertFalse(try directoryContainsTransactionFiles(directory))
    }

    func testRejectsDirectoryOutputWithoutDeletingNestedContents() throws {
        let directory = try makeTemporaryDirectory()
        let destination = TranscriptionDestination(
            directoryURL: directory,
            baseName: "Lezione",
            outputSelection: .srtOnly,
            overwriteExisting: true
        )
        try FileManager.default.createDirectory(
            at: destination.srtURL,
            withIntermediateDirectories: true
        )
        let nestedURL = destination.srtURL.appendingPathComponent("appunti.txt")
        try "da conservare".write(to: nestedURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try TranscriptionOutputWriter().write(sampleOutput, to: destination)) { error in
            XCTAssertEqual(
                error as? TranscriptionOutputWriter.WriteError,
                .unsupportedExistingOutput("Lezione.srt")
            )
        }

        XCTAssertEqual(
            TranscriptionOutputPathClassifier.kind(at: destination.srtURL),
            .unsupported
        )
        XCTAssertEqual(try String(contentsOf: nestedURL, encoding: .utf8), "da conservare")
        XCTAssertFalse(try directoryContainsTransactionFiles(directory))
    }

    func testRejectsSymbolicLinkOutputWithoutChangingLinkOrTarget() throws {
        let directory = try makeTemporaryDirectory()
        let destination = TranscriptionDestination(
            directoryURL: directory,
            baseName: "Lezione",
            outputSelection: .srtOnly,
            overwriteExisting: true
        )
        let targetURL = directory.appendingPathComponent("originale.srt")
        try "target invariato".write(to: targetURL, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: destination.srtURL,
            withDestinationURL: targetURL
        )

        XCTAssertThrowsError(try TranscriptionOutputWriter().write(sampleOutput, to: destination)) { error in
            XCTAssertEqual(
                error as? TranscriptionOutputWriter.WriteError,
                .unsupportedExistingOutput("Lezione.srt")
            )
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: destination.srtURL.path)
        XCTAssertEqual(attributes[.type] as? FileAttributeType, .typeSymbolicLink)
        XCTAssertEqual(try String(contentsOf: targetURL, encoding: .utf8), "target invariato")
        XCTAssertFalse(try directoryContainsTransactionFiles(directory))
    }

    func testMixedRegularAndUnsupportedConflictsLeaveBothUntouched() throws {
        let directory = try makeTemporaryDirectory()
        let destination = TranscriptionDestination(
            directoryURL: directory,
            baseName: "Lezione",
            overwriteExisting: true
        )
        try "srt originale".write(to: destination.srtURL, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(
            at: destination.txtURL,
            withIntermediateDirectories: true
        )
        let nestedURL = destination.txtURL.appendingPathComponent("contenuto.txt")
        try "cartella originale".write(to: nestedURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try TranscriptionOutputWriter().write(sampleOutput, to: destination)) { error in
            XCTAssertEqual(
                error as? TranscriptionOutputWriter.WriteError,
                .unsupportedExistingOutput("Lezione.txt")
            )
        }

        XCTAssertEqual(
            try String(contentsOf: destination.srtURL, encoding: .utf8),
            "srt originale"
        )
        XCTAssertEqual(try String(contentsOf: nestedURL, encoding: .utf8), "cartella originale")
        XCTAssertFalse(try directoryContainsTransactionFiles(directory))
    }

    func testUnselectedExistingFileDoesNotConflictOrGetReplaced() throws {
        let directory = try makeTemporaryDirectory()
        let destination = TranscriptionDestination(
            directoryURL: directory,
            baseName: "Lezione",
            outputSelection: .txtOnly,
            overwriteExisting: false
        )
        try "srt esistente".write(to: destination.srtURL, atomically: true, encoding: .utf8)

        _ = try TranscriptionOutputWriter().write(sampleOutput, to: destination)

        XCTAssertEqual(try String(contentsOf: destination.srtURL, encoding: .utf8), "srt esistente")
        XCTAssertEqual(try String(contentsOf: destination.txtURL, encoding: .utf8), sampleOutput.plainText)
    }

    func testSanitizesPrefilledBaseName() {
        XCTAssertEqual(TranscriptionDestinationPicker.sanitizedBaseName(" Lezione 12.srt "), "Lezione 12")
        XCTAssertEqual(TranscriptionDestinationPicker.sanitizedBaseName("Lezione.txt"), "Lezione")
        XCTAssertEqual(
            TranscriptionDestinationPicker.sanitizedBaseName("Audio 18 25/05/2026"),
            "Audio 18 25-05-2026"
        )
        XCTAssertEqual(
            TranscriptionDestinationPicker.sanitizedBaseName("Audio 18 25:05:2026"),
            "Audio 18 25-05-2026"
        )
        XCTAssertEqual(
            TranscriptionDestinationPicker.sanitizedBaseName(" Lezione università... "),
            "Lezione università"
        )
        XCTAssertNil(TranscriptionDestinationPicker.sanitizedBaseName("..."))
    }

    @MainActor
    func testDestinationPanelRequestsFolderAccessBeforeTranscription() {
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
        let panel = TranscriptionDestinationPicker.makePanel(
            baseName: "Audio 18 25-05-2026",
            initialDirectoryURL: directory,
            outputSelection: .srtAndTxt
        )

        XCTAssertTrue(panel.canChooseDirectories)
        XCTAssertFalse(panel.canChooseFiles)
        XCTAssertFalse(panel.allowsMultipleSelection)
        XCTAssertEqual(panel.directoryURL, directory)
        XCTAssertEqual(panel.prompt, "Consenti e avvia")
        XCTAssertTrue(panel.isAccessoryViewDisclosed)
        XCTAssertEqual(
            TranscriptionDestinationPicker.baseName(in: panel),
            "Audio 18 25-05-2026"
        )
        XCTAssertTrue(panel.message.contains("richiede l’accesso"))
        XCTAssertTrue(panel.message.contains(TranscriptionOutputSelection.srtAndTxt.creationDescription))
    }

    func testWriteAccessProbeLeavesNoTemporaryFile() throws {
        let directory = try makeTemporaryDirectory()
        let destination = TranscriptionDestination(
            directoryURL: directory,
            baseName: "Lezione",
            overwriteExisting: false
        )

        try TranscriptionOutputWriter().validateWriteAccess(to: destination)

        XCTAssertFalse(try directoryContainsTransactionFiles(directory))
    }

    private var sampleOutput: TranscriptionOutput {
        TranscriptionOutput(
            cues: [SubtitleCue(id: 0, start: 0, end: 1, text: "Ciao")],
            srtText: "1\n00:00:00,000 --> 00:00:01,000\nCiao\n",
            plainText: "Ciao\n"
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func directoryContainsTransactionFiles(_ directory: URL) throws -> Bool {
        try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .contains { $0.hasPrefix(".audiopro-") }
    }
}

import XCTest
@testable import AudioPro

final class ExportOutputTransactionTests: XCTestCase {
    func testProcessingStagingUsesAppTemporaryWorkspaceAndPreservesExtension() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("Export.OPUS")

        let transaction = try ExportOutputTransaction(destinationURL: destination)
        defer { transaction.discard() }

        XCTAssertEqual(transaction.stagingURL.pathExtension, "OPUS")
        XCTAssertTrue(
            transaction.stagingURL.path.hasPrefix(
                FileManager.default.temporaryDirectory.standardizedFileURL.path
            )
        )
        XCTAssertNotEqual(
            transaction.stagingURL.deletingLastPathComponent(),
            destination.deletingLastPathComponent()
        )
    }

    func testStagesInputsAsRegularFilesInsideWorkspace() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("Lecture.WAV")
        let sourceData = Data("audio input".utf8)
        try sourceData.write(to: source)
        let transaction = try ExportOutputTransaction(
            destinationURL: directory.appendingPathComponent("Export.m4a")
        )
        defer { transaction.discard() }

        let stagedInputs = try transaction.stageInputs([source])

        XCTAssertEqual(stagedInputs.count, 1)
        XCTAssertNotEqual(stagedInputs[0], source)
        XCTAssertEqual(stagedInputs[0].pathExtension, "WAV")
        XCTAssertEqual(try Data(contentsOf: stagedInputs[0]), sourceData)
        XCTAssertEqual(
            stagedInputs[0].deletingLastPathComponent().deletingLastPathComponent(),
            transaction.stagingURL.deletingLastPathComponent()
        )
    }

    func testRejectsSymbolicLinkInput() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.wav")
        try Data("audio".utf8).write(to: source)
        let link = directory.appendingPathComponent("linked.wav")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        let transaction = try ExportOutputTransaction(
            destinationURL: directory.appendingPathComponent("Export.m4a")
        )
        defer { transaction.discard() }

        XCTAssertThrowsError(try transaction.stageInputs([link])) { error in
            XCTAssertEqual(error as? ExportOutputTransaction.TransactionError, .invalidInput)
        }
    }

    func testCommitCreatesNewDestination() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("Export.m4a")
        let transaction = try ExportOutputTransaction(destinationURL: destination)
        defer { transaction.discard() }
        let expected = Data("encoded audio".utf8)
        try expected.write(to: transaction.stagingURL)

        try transaction.commit()

        XCTAssertEqual(try Data(contentsOf: destination), expected)
        XCTAssertFalse(FileManager.default.fileExists(atPath: transaction.stagingURL.path))
    }

    func testDiscardRemovesPrivateProcessingWorkspace() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("Export.m4a")
        let transaction = try ExportOutputTransaction(destinationURL: destination)
        let stagingDirectory = transaction.stagingURL.deletingLastPathComponent()
        try Data("partial".utf8).write(to: transaction.stagingURL)

        transaction.discard()

        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingDirectory.path))
    }

    func testCommitReplacesExistingRegularDestination() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("Export.m4a")
        try Data("original".utf8).write(to: destination)
        let transaction = try ExportOutputTransaction(destinationURL: destination)
        defer { transaction.discard() }
        let replacement = Data("replacement".utf8)
        try replacement.write(to: transaction.stagingURL)

        try transaction.commit()

        XCTAssertEqual(try Data(contentsOf: destination), replacement)
        XCTAssertFalse(FileManager.default.fileExists(atPath: transaction.stagingURL.path))
    }

    func testReplacementFailureRestoresOriginalDestination() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("Export.m4a")
        let original = Data("original".utf8)
        try original.write(to: destination)
        let transaction = try ExportOutputTransaction(
            destinationURL: destination,
            itemReplacer: { fileManager, originalURL, _ in
                let relocatedURL = originalURL
                    .deletingLastPathComponent()
                    .appendingPathComponent("Relocated-\(UUID().uuidString).m4a")
                try fileManager.moveItem(at: originalURL, to: relocatedURL)
                throw NSError(
                    domain: NSCocoaErrorDomain,
                    code: CocoaError.fileWriteUnknown.rawValue,
                    userInfo: ["NSFileOriginalItemLocationKey": relocatedURL]
                )
            }
        )
        defer { transaction.discard() }
        try Data("replacement".utf8).write(to: transaction.stagingURL)

        XCTAssertThrowsError(try transaction.commit())
        XCTAssertEqual(try Data(contentsOf: destination), original)
    }

    func testDiscardRemovesOnlyStagingAndPreservesExistingDestination() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("Export.m4a")
        let original = Data("original".utf8)
        try original.write(to: destination)
        let transaction = try ExportOutputTransaction(destinationURL: destination)
        try Data("partial".utf8).write(to: transaction.stagingURL)

        transaction.discard()

        XCTAssertEqual(try Data(contentsOf: destination), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: transaction.stagingURL.path))
    }

    func testCommitRejectsEmptyStagingAndPreservesExistingDestination() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("Export.m4a")
        let original = Data("original".utf8)
        try original.write(to: destination)
        let transaction = try ExportOutputTransaction(destinationURL: destination)
        defer { transaction.discard() }
        try Data().write(to: transaction.stagingURL)

        XCTAssertThrowsError(try transaction.commit()) { error in
            XCTAssertEqual(
                error as? ExportOutputTransaction.TransactionError,
                .invalidStagingOutput
            )
        }
        XCTAssertEqual(try Data(contentsOf: destination), original)
    }

    func testDirectoryDestinationIsRejected() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("Export.m4a", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)

        XCTAssertThrowsError(try ExportOutputTransaction(destinationURL: destination)) { error in
            XCTAssertEqual(
                error as? ExportOutputTransaction.TransactionError,
                .invalidDestination
            )
        }
    }

    func testSymbolicLinkDestinationIsRejected() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("target.m4a")
        try Data("original".utf8).write(to: target)
        let destination = directory.appendingPathComponent("Export.m4a")
        try FileManager.default.createSymbolicLink(
            at: destination,
            withDestinationURL: target
        )

        XCTAssertThrowsError(try ExportOutputTransaction(destinationURL: destination)) { error in
            XCTAssertEqual(
                error as? ExportOutputTransaction.TransactionError,
                .invalidDestination
            )
        }
        XCTAssertEqual(try Data(contentsOf: target), Data("original".utf8))
    }

    func testBrokenSymbolicLinkDestinationIsRejected() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let missingTarget = directory.appendingPathComponent("missing.m4a")
        let destination = directory.appendingPathComponent("Export.m4a")
        try FileManager.default.createSymbolicLink(
            at: destination,
            withDestinationURL: missingTarget
        )

        XCTAssertThrowsError(try ExportOutputTransaction(destinationURL: destination)) { error in
            XCTAssertEqual(
                error as? ExportOutputTransaction.TransactionError,
                .invalidDestination
            )
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioProTransactionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

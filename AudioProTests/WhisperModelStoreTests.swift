import XCTest
@testable import AudioPro

final class WhisperModelStoreTests: XCTestCase {
    func testValidatesExpectedModelFolderShape() throws {
        let root = try makeTemporaryDirectory()
        let model = root.appendingPathComponent("model", isDirectory: true)
        try makeValidModelFolder(at: model)

        XCTAssertTrue(WhisperModelStore.isValidModelFolder(model))
    }

    func testRejectsIncompleteModelFolder() throws {
        let root = try makeTemporaryDirectory()
        let model = root.appendingPathComponent("model", isDirectory: true)
        try FileManager.default.createDirectory(at: model, withIntermediateDirectories: true)
        try Data().write(to: model.appendingPathComponent("config.json"))

        XCTAssertFalse(WhisperModelStore.isValidModelFolder(model))
    }

    func testValidatesExpectedTokenizerFolderShape() throws {
        let root = try makeTemporaryDirectory()
        let tokenizer = root.appendingPathComponent("tokenizer", isDirectory: true)
        try makeValidTokenizerFolder(at: tokenizer)

        XCTAssertTrue(WhisperModelStore.isValidTokenizerFolder(tokenizer))
    }

    func testRejectsIncompleteTokenizerFolder() throws {
        let root = try makeTemporaryDirectory()
        let tokenizer = root.appendingPathComponent("tokenizer", isDirectory: true)
        try FileManager.default.createDirectory(at: tokenizer, withIntermediateDirectories: true)
        try Data().write(to: tokenizer.appendingPathComponent("tokenizer.json"))

        XCTAssertFalse(WhisperModelStore.isValidTokenizerFolder(tokenizer))
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

    private func makeValidModelFolder(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for directory in ["AudioEncoder.mlmodelc", "MelSpectrogram.mlmodelc", "TextDecoder.mlmodelc"] {
            try FileManager.default.createDirectory(
                at: url.appendingPathComponent(directory, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        for file in ["config.json", "generation_config.json"] {
            try Data().write(to: url.appendingPathComponent(file))
        }
    }

    private func makeValidTokenizerFolder(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for file in ["tokenizer.json", "config.json"] {
            try Data().write(to: url.appendingPathComponent(file))
        }
    }
}

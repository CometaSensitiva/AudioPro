import XCTest
@testable import AudioPro

final class WhisperModelStoreTests: XCTestCase {
    func testValidatesExpectedModelFolderShape() throws {
        let root = try makeTemporaryDirectory()
        let model = root.appendingPathComponent("model", isDirectory: true)
        try makeValidModelFolder(at: model)

        XCTAssertTrue(WhisperModelStore.isValidModelFolder(model))
    }

    func testRejectsIncompleteOrEmptyModelArtifacts() throws {
        let root = try makeTemporaryDirectory()
        let model = root.appendingPathComponent("model", isDirectory: true)
        try makeValidModelFolder(at: model)

        try Data().write(to: model.appendingPathComponent("config.json"))
        XCTAssertFalse(WhisperModelStore.isValidModelFolder(model))

        try Data("{}".utf8).write(to: model.appendingPathComponent("config.json"))
        let decoder = model.appendingPathComponent("TextDecoder.mlmodelc", isDirectory: true)
        try FileManager.default.removeItem(at: decoder.appendingPathComponent("model.mil"))
        XCTAssertFalse(WhisperModelStore.isValidModelFolder(model))
    }

    func testRejectsSymbolicLinksInsideModelArtifacts() throws {
        let root = try makeTemporaryDirectory()
        let model = root.appendingPathComponent("model", isDirectory: true)
        try makeValidModelFolder(at: model)

        let externalConfig = root.appendingPathComponent("external-config.json")
        try Data("{}".utf8).write(to: externalConfig)
        let config = model.appendingPathComponent("config.json")
        try FileManager.default.removeItem(at: config)
        try FileManager.default.createSymbolicLink(at: config, withDestinationURL: externalConfig)

        XCTAssertFalse(WhisperModelStore.isValidModelFolder(model))
    }

    func testValidatesExpectedTokenizerFolderShape() throws {
        let root = try makeTemporaryDirectory()
        let tokenizer = root.appendingPathComponent("tokenizer", isDirectory: true)
        try makeValidTokenizerFolder(at: tokenizer)

        XCTAssertTrue(WhisperModelStore.isValidTokenizerFolder(tokenizer))
    }

    func testRejectsIncompleteOrEmptyTokenizerFolder() throws {
        let root = try makeTemporaryDirectory()
        let tokenizer = root.appendingPathComponent("tokenizer", isDirectory: true)
        try makeValidTokenizerFolder(at: tokenizer)

        try Data().write(to: tokenizer.appendingPathComponent("tokenizer.json"))
        XCTAssertFalse(WhisperModelStore.isValidTokenizerFolder(tokenizer))

        try FileManager.default.removeItem(at: tokenizer.appendingPathComponent("config.json"))
        XCTAssertFalse(WhisperModelStore.isValidTokenizerFolder(tokenizer))
    }

    func testRejectsSymbolicLinksInsideTokenizerArtifacts() throws {
        let root = try makeTemporaryDirectory()
        let tokenizer = root.appendingPathComponent("tokenizer", isDirectory: true)
        try makeValidTokenizerFolder(at: tokenizer)

        let externalConfig = root.appendingPathComponent("external-tokenizer-config.json")
        try Data("{}".utf8).write(to: externalConfig)
        let config = tokenizer.appendingPathComponent("config.json")
        try FileManager.default.removeItem(at: config)
        try FileManager.default.createSymbolicLink(at: config, withDestinationURL: externalConfig)

        XCTAssertFalse(WhisperModelStore.isValidTokenizerFolder(tokenizer))
    }

    func testCompleteArtifactsWithoutMarkerRemainUnavailable() throws {
        let cacheRoot = try makeTemporaryDirectory()
        let locations = try makeDownloadedLocations(in: cacheRoot)

        XCTAssertTrue(WhisperModelStore.isValidModelFolder(locations.modelFolder))
        XCTAssertTrue(WhisperModelStore.isValidTokenizerFolder(locations.tokenizerFolder))
        XCTAssertNil(WhisperModelStore.downloadedModelLocations(in: cacheRoot))
    }

    func testRegistersAndResolvesDownloadedModelWithRelativeManifest() throws {
        let cacheRoot = try makeTemporaryDirectory()
        let locations = try makeDownloadedLocations(in: cacheRoot)

        try WhisperModelStore.registerDownloadedModel(locations, in: cacheRoot)

        let resolved = WhisperModelStore.downloadedModelLocations(in: cacheRoot)
        XCTAssertEqual(
            resolved?.modelFolder,
            locations.modelFolder.standardizedFileURL.resolvingSymlinksInPath()
        )
        XCTAssertEqual(
            resolved?.tokenizerFolder,
            locations.tokenizerFolder.standardizedFileURL.resolvingSymlinksInPath()
        )

        let markerURL = cacheRoot.appendingPathComponent(
            WhisperModelStore.downloadedModelMarkerFileName
        )
        let marker = try String(contentsOf: markerURL, encoding: .utf8)
        XCTAssertTrue(marker.hasPrefix("{"))
        XCTAssertFalse(marker.contains(cacheRoot.path))
    }

    func testInvalidRegistrationDoesNotOverwritePriorValidMarker() throws {
        let cacheRoot = try makeTemporaryDirectory()
        let validLocations = try makeDownloadedLocations(in: cacheRoot)
        try WhisperModelStore.registerDownloadedModel(validLocations, in: cacheRoot)

        let markerURL = cacheRoot.appendingPathComponent(
            WhisperModelStore.downloadedModelMarkerFileName
        )
        let markerBeforeFailure = try Data(contentsOf: markerURL)
        let invalidLocations = WhisperModelStore.BundleModelLocations(
            modelFolder: validLocations.modelFolder,
            tokenizerFolder: cacheRoot.appendingPathComponent("missing-tokenizer", isDirectory: true)
        )

        XCTAssertThrowsError(
            try WhisperModelStore.registerDownloadedModel(invalidLocations, in: cacheRoot)
        )
        XCTAssertEqual(try Data(contentsOf: markerURL), markerBeforeFailure)
        XCTAssertEqual(
            WhisperModelStore.downloadedModelLocations(in: cacheRoot),
            WhisperModelStore.BundleModelLocations(
                modelFolder: validLocations.modelFolder.standardizedFileURL.resolvingSymlinksInPath(),
                tokenizerFolder: validLocations.tokenizerFolder.standardizedFileURL.resolvingSymlinksInPath()
            )
        )
    }

    func testResolvesLegacyAbsoluteMarkerWhenTokenizerIsComplete() throws {
        let cacheRoot = try makeTemporaryDirectory()
        let locations = try makeDownloadedLocations(in: cacheRoot)
        try locations.modelFolder.path.write(
            to: cacheRoot.appendingPathComponent(WhisperModelStore.downloadedModelMarkerFileName),
            atomically: true,
            encoding: .utf8
        )

        let resolved = WhisperModelStore.downloadedModelLocations(in: cacheRoot)

        XCTAssertEqual(
            resolved?.modelFolder,
            locations.modelFolder.standardizedFileURL.resolvingSymlinksInPath()
        )
        XCTAssertEqual(
            resolved?.tokenizerFolder,
            locations.tokenizerFolder.standardizedFileURL.resolvingSymlinksInPath()
        )

        let migratedMarker = try String(
            contentsOf: cacheRoot.appendingPathComponent(
                WhisperModelStore.downloadedModelMarkerFileName
            ),
            encoding: .utf8
        )
        XCTAssertTrue(migratedMarker.hasPrefix("{"))
        XCTAssertFalse(migratedMarker.contains(cacheRoot.path))
    }

    func testLegacyMarkerRequiresTokenizerAndNeverFallsBackToRecursiveSearch() throws {
        let cacheRoot = try makeTemporaryDirectory()
        let model = cacheRoot
            .appendingPathComponent("models/argmaxinc/whisperkit-coreml", isDirectory: true)
            .appendingPathComponent(WhisperModelStore.modelDirectoryName, isDirectory: true)
        try makeValidModelFolder(at: model)
        try model.path.write(
            to: cacheRoot.appendingPathComponent(WhisperModelStore.downloadedModelMarkerFileName),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertNil(WhisperModelStore.downloadedModelLocations(in: cacheRoot))

        try FileManager.default.removeItem(
            at: cacheRoot.appendingPathComponent(WhisperModelStore.downloadedModelMarkerFileName)
        )
        try makeValidTokenizerFolder(
            at: cacheRoot.appendingPathComponent(
                WhisperModelStore.downloadedTokenizerRelativePath,
                isDirectory: true
            )
        )
        XCTAssertNil(WhisperModelStore.downloadedModelLocations(in: cacheRoot))
    }

    func testRejectsLegacyMarkerThatEscapesCacheRootThroughSymlink() throws {
        let root = try makeTemporaryDirectory()
        let cacheRoot = root.appendingPathComponent("cache", isDirectory: true)
        let externalModel = root.appendingPathComponent("external-model", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        try makeValidModelFolder(at: externalModel)
        try makeValidTokenizerFolder(
            at: cacheRoot.appendingPathComponent(
                WhisperModelStore.downloadedTokenizerRelativePath,
                isDirectory: true
            )
        )

        let linkedModel = cacheRoot.appendingPathComponent("linked-model", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: linkedModel, withDestinationURL: externalModel)
        try linkedModel.path.write(
            to: cacheRoot.appendingPathComponent(WhisperModelStore.downloadedModelMarkerFileName),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertNil(WhisperModelStore.downloadedModelLocations(in: cacheRoot))
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

    private func makeDownloadedLocations(
        in cacheRoot: URL
    ) throws -> WhisperModelStore.BundleModelLocations {
        let model = cacheRoot
            .appendingPathComponent("models/argmaxinc/whisperkit-coreml", isDirectory: true)
            .appendingPathComponent(WhisperModelStore.modelDirectoryName, isDirectory: true)
        let tokenizer = cacheRoot.appendingPathComponent(
            WhisperModelStore.downloadedTokenizerRelativePath,
            isDirectory: true
        )
        try makeValidModelFolder(at: model)
        try makeValidTokenizerFolder(at: tokenizer)
        return WhisperModelStore.BundleModelLocations(
            modelFolder: model,
            tokenizerFolder: tokenizer
        )
    }

    private func makeValidModelFolder(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for directory in ["AudioEncoder.mlmodelc", "MelSpectrogram.mlmodelc", "TextDecoder.mlmodelc"] {
            let compiledModel = url.appendingPathComponent(directory, isDirectory: true)
            try FileManager.default.createDirectory(
                at: compiledModel,
                withIntermediateDirectories: true
            )
            try Data("model".utf8).write(to: compiledModel.appendingPathComponent("model.mil"))
        }
        for file in ["config.json", "generation_config.json"] {
            try Data("{}".utf8).write(to: url.appendingPathComponent(file))
        }
    }

    private func makeValidTokenizerFolder(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for file in ["tokenizer.json", "config.json"] {
            try Data("{}".utf8).write(to: url.appendingPathComponent(file))
        }
    }
}

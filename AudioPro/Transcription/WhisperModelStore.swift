import Foundation

nonisolated enum WhisperModelStore {
    static let bundleDirectoryName = "WhisperModels"
    static let modelDirectoryName = "openai_whisper-large-v3-v20240930"
    static let tokenizerDirectoryName = "whisper-large-v3-tokenizer"

    struct BundleModelLocations: Equatable, Sendable {
        let modelFolder: URL
        let tokenizerFolder: URL
    }

    enum Availability: Equatable, Sendable {
        case available(BundleModelLocations)
        case missing(String)
    }

    static func availability(
        in bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) -> Availability {
        guard let locations = bundledModelLocations(in: bundle, fileManager: fileManager) else {
            return .missing("Whisper Large v3 non disponibile in questa build.")
        }
        return .available(locations)
    }

    static func bundledModelLocations(
        in bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) -> BundleModelLocations? {
        guard let resourceURL = bundle.resourceURL else { return nil }

        let root = resourceURL.appendingPathComponent(bundleDirectoryName, isDirectory: true)
        let modelFolder = root.appendingPathComponent(modelDirectoryName, isDirectory: true)
        let tokenizerFolder = root.appendingPathComponent(tokenizerDirectoryName, isDirectory: true)

        guard isValidModelFolder(modelFolder, fileManager: fileManager),
              isValidTokenizerFolder(tokenizerFolder, fileManager: fileManager) else {
            return nil
        }

        return BundleModelLocations(modelFolder: modelFolder, tokenizerFolder: tokenizerFolder)
    }

    static func isValidModelFolder(
        _ url: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return false
        }

        let requiredDirectories = [
            "AudioEncoder.mlmodelc",
            "MelSpectrogram.mlmodelc",
            "TextDecoder.mlmodelc"
        ]
        let requiredFiles = [
            "config.json",
            "generation_config.json"
        ]

        return requiredDirectories.allSatisfy { child in
            let childURL = url.appendingPathComponent(child, isDirectory: true)
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: childURL.path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        } && requiredFiles.allSatisfy { child in
            let childURL = url.appendingPathComponent(child)
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: childURL.path, isDirectory: &isDirectory)
                && isDirectory.boolValue == false
        }
    }

    static func isValidTokenizerFolder(
        _ url: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return false
        }

        return ["tokenizer.json", "config.json"].allSatisfy { child in
            let childURL = url.appendingPathComponent(child)
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: childURL.path, isDirectory: &isDirectory)
                && isDirectory.boolValue == false
        }
    }
}

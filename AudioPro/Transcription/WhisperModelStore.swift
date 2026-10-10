import Foundation

nonisolated enum WhisperModelStore {
    static let bundleDirectoryName = "WhisperModels"
    static let modelDirectoryName = "openai_whisper-large-v3-v20240930"
    static let tokenizerDirectoryName = "whisper-large-v3-tokenizer"
    static let downloadVariantName = modelDirectoryName
    static let localModelsDirectoryName = "LocalModels"
    static let modelCacheDirectoryName = "ModelCache"
    static let downloadedModelMarkerFileName = ".downloaded-whisper-model-path"
    static let downloadedTokenizerRelativePath = "models/openai/whisper-large-v3"

    struct BundleModelLocations: Equatable, Sendable {
        let modelFolder: URL
        let tokenizerFolder: URL
    }

    enum Availability: Equatable, Sendable {
        case available(BundleModelLocations)
        case missing(String)
    }

    private struct DownloadedModelRegistration: Codable {
        static let currentVersion = 1

        let version: Int
        let modelRelativePath: String
        let tokenizerRelativePath: String
    }

    static func availability(
        in bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) -> Availability {
        if let locations = bundledModelLocations(in: bundle, fileManager: fileManager) {
            return .available(locations)
        }

        if let locations = downloadedModelLocations(fileManager: fileManager) {
            return .available(locations)
        }

        if let locations = applicationSupportModelLocations(fileManager: fileManager) {
            return .available(locations)
        }

        return .missing("Whisper Large v3 non rilevato.")
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

    static func applicationSupportModelLocations(
        fileManager: FileManager = .default
    ) -> BundleModelLocations? {
        guard let root = localModelsDirectory(fileManager: fileManager) else { return nil }

        let modelFolder = root.appendingPathComponent(modelDirectoryName, isDirectory: true)
        let tokenizerFolder = root.appendingPathComponent(tokenizerDirectoryName, isDirectory: true)

        guard isValidModelFolder(modelFolder, fileManager: fileManager),
              isValidTokenizerFolder(tokenizerFolder, fileManager: fileManager) else {
            return nil
        }

        return BundleModelLocations(modelFolder: modelFolder, tokenizerFolder: tokenizerFolder)
    }

    static func downloadedModelLocations(
        fileManager: FileManager = .default
    ) -> BundleModelLocations? {
        guard let root = modelCacheDirectory(fileManager: fileManager) else { return nil }
        return downloadedModelLocations(in: root, fileManager: fileManager)
    }

    static func downloadedModelLocations(
        in cacheRoot: URL,
        fileManager: FileManager = .default
    ) -> BundleModelLocations? {
        let markerURL = cacheRoot.appendingPathComponent(downloadedModelMarkerFileName)
        guard let markerData = fileManager.contents(atPath: markerURL.path) else {
            return nil
        }

        if let registration = try? JSONDecoder().decode(
            DownloadedModelRegistration.self,
            from: markerData
        ) {
            guard registration.version == DownloadedModelRegistration.currentVersion,
                  let modelFolder = containedURL(
                    forRelativePath: registration.modelRelativePath,
                    in: cacheRoot
                  ),
                  let tokenizerFolder = containedURL(
                    forRelativePath: registration.tokenizerRelativePath,
                    in: cacheRoot
                  ) else {
                return nil
            }

            return validatedLocations(
                modelFolder: modelFolder,
                tokenizerFolder: tokenizerFolder,
                cacheRoot: cacheRoot,
                fileManager: fileManager
            )
        }

        // Compatibility with the first runtime-download build, whose marker was
        // one absolute model path. Tokenizer lookup remains bounded and never scans.
        guard let legacyPath = String(data: markerData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              legacyPath.isEmpty == false,
              legacyPath.hasPrefix("/"),
              let tokenizerFolder = downloadedTokenizerFolder(
                in: cacheRoot,
                fileManager: fileManager
              ) else {
            return nil
        }

        guard let locations = validatedLocations(
            modelFolder: URL(fileURLWithPath: legacyPath, isDirectory: true),
            tokenizerFolder: tokenizerFolder,
            cacheRoot: cacheRoot,
            fileManager: fileManager
        ) else {
            return nil
        }

        // Migrate a valid legacy absolute marker best-effort. Availability does
        // not depend on the migration write succeeding in a read-only cache.
        try? registerDownloadedModel(locations, in: cacheRoot, fileManager: fileManager)
        return locations
    }

    static func downloadedTokenizerFolder(
        in cacheRoot: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        let candidates = [
            cacheRoot.appendingPathComponent(downloadedTokenizerRelativePath, isDirectory: true),
            cacheRoot
        ]

        return candidates.first { candidate in
            isContained(candidate, in: cacheRoot)
                && isValidTokenizerFolder(candidate, fileManager: fileManager)
        }
    }

    static func ensureModelCacheDirectory(fileManager: FileManager = .default) throws -> URL {
        guard let root = modelCacheDirectory(fileManager: fileManager) else {
            throw CocoaError(.fileNoSuchFile)
        }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func registerDownloadedModel(
        _ locations: BundleModelLocations,
        fileManager: FileManager = .default
    ) throws {
        let root = try ensureModelCacheDirectory(fileManager: fileManager)
        try registerDownloadedModel(locations, in: root, fileManager: fileManager)
    }

    static func registerDownloadedModel(
        _ locations: BundleModelLocations,
        in cacheRoot: URL,
        fileManager: FileManager = .default
    ) throws {
        try fileManager.createDirectory(at: cacheRoot, withIntermediateDirectories: true)

        guard let validated = validatedLocations(
            modelFolder: locations.modelFolder,
            tokenizerFolder: locations.tokenizerFolder,
            cacheRoot: cacheRoot,
            fileManager: fileManager
        ),
              let modelRelativePath = relativePath(of: validated.modelFolder, from: cacheRoot),
              let tokenizerRelativePath = relativePath(of: validated.tokenizerFolder, from: cacheRoot) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let registration = DownloadedModelRegistration(
            version: DownloadedModelRegistration.currentVersion,
            modelRelativePath: modelRelativePath,
            tokenizerRelativePath: tokenizerRelativePath
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(registration)

        // Validation happens before this atomic replacement, so a failed attempt
        // cannot destroy a previously valid completion marker.
        try data.write(
            to: cacheRoot.appendingPathComponent(downloadedModelMarkerFileName),
            options: .atomic
        )
    }

    static func isValidModelFolder(
        _ url: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        guard isDirectory(url, fileManager: fileManager) else {
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
            isNonEmptyDirectory(
                url.appendingPathComponent(child, isDirectory: true),
                fileManager: fileManager
            )
        } && requiredFiles.allSatisfy { child in
            isNonEmptyRegularFile(url.appendingPathComponent(child), fileManager: fileManager)
        }
    }

    static func isValidTokenizerFolder(
        _ url: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        guard isDirectory(url, fileManager: fileManager) else {
            return false
        }

        return ["tokenizer.json", "config.json"].allSatisfy { child in
            isNonEmptyRegularFile(url.appendingPathComponent(child), fileManager: fileManager)
        }
    }

    private static func validatedLocations(
        modelFolder: URL,
        tokenizerFolder: URL,
        cacheRoot: URL,
        fileManager: FileManager
    ) -> BundleModelLocations? {
        let canonicalModelFolder = canonicalURL(modelFolder)
        let canonicalTokenizerFolder = canonicalURL(tokenizerFolder)

        guard isContained(canonicalModelFolder, in: cacheRoot),
              isContained(canonicalTokenizerFolder, in: cacheRoot),
              isValidModelFolder(canonicalModelFolder, fileManager: fileManager),
              isValidTokenizerFolder(canonicalTokenizerFolder, fileManager: fileManager) else {
            return nil
        }

        return BundleModelLocations(
            modelFolder: canonicalModelFolder,
            tokenizerFolder: canonicalTokenizerFolder
        )
    }

    private static func containedURL(forRelativePath path: String, in cacheRoot: URL) -> URL? {
        guard path.isEmpty == false,
              path.hasPrefix("/") == false,
              path.split(separator: "/").contains("..") == false else {
            return nil
        }

        let candidate: URL
        if path == "." {
            candidate = cacheRoot
        } else {
            candidate = cacheRoot.appendingPathComponent(path, isDirectory: true)
        }

        return isContained(candidate, in: cacheRoot) ? canonicalURL(candidate) : nil
    }

    private static func relativePath(of child: URL, from root: URL) -> String? {
        let rootComponents = canonicalURL(root).pathComponents
        let childComponents = canonicalURL(child).pathComponents

        guard childComponents.count >= rootComponents.count,
              Array(childComponents.prefix(rootComponents.count)) == rootComponents else {
            return nil
        }

        let remainder = childComponents.dropFirst(rootComponents.count)
        return remainder.isEmpty ? "." : remainder.joined(separator: "/")
    }

    private static func isContained(_ child: URL, in root: URL) -> Bool {
        let rootComponents = canonicalURL(root).pathComponents
        let childComponents = canonicalURL(child).pathComponents
        return childComponents.count >= rootComponents.count
            && Array(childComponents.prefix(rootComponents.count)) == rootComponents
    }

    private static func canonicalURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    private static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        guard isSymbolicLink(url, fileManager: fileManager) == false,
              let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let type = attributes[.type] as? FileAttributeType else {
            return false
        }
        return type == .typeDirectory
    }

    private static func isNonEmptyDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        guard isDirectory(url, fileManager: fileManager),
              let children = try? fileManager.contentsOfDirectory(atPath: url.path) else {
            return false
        }
        return children.isEmpty == false
    }

    private static func isNonEmptyRegularFile(_ url: URL, fileManager: FileManager) -> Bool {
        guard isSymbolicLink(url, fileManager: fileManager) == false,
              let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let type = attributes[.type] as? FileAttributeType,
              type == .typeRegular,
              let size = attributes[.size] as? NSNumber else {
            return false
        }
        return size.int64Value > 0
    }

    private static func isSymbolicLink(_ url: URL, fileManager: FileManager) -> Bool {
        (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    private static func applicationSupportDirectory(fileManager: FileManager) -> URL? {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("AudioPro", isDirectory: true)
    }

    private static func localModelsDirectory(fileManager: FileManager) -> URL? {
        applicationSupportDirectory(fileManager: fileManager)?
            .appendingPathComponent(localModelsDirectoryName, isDirectory: true)
    }

    private static func modelCacheDirectory(fileManager: FileManager) -> URL? {
        applicationSupportDirectory(fileManager: fileManager)?
            .appendingPathComponent(modelCacheDirectoryName, isDirectory: true)
    }
}

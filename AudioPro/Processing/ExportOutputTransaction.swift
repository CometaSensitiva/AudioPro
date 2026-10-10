import Foundation

/// Owns the parent-app side of an export transaction.
///
/// The ffmpeg helper inherits only static sandbox rights, so it reads and
/// writes exclusively inside this app-container workspace. On commit, the
/// parent app copies the completed output to a same-volume replacement
/// directory and publishes it atomically at the user-selected destination.
nonisolated struct ExportOutputTransaction {
    typealias ItemReplacer = @Sendable (FileManager, URL, URL) throws -> Void

    enum TransactionError: LocalizedError, Equatable {
        case missingOutputExtension
        case invalidInput
        case invalidDestination
        case invalidStagingOutput

        var errorDescription: String? {
            switch self {
            case .missingOutputExtension:
                return "Il file di destinazione non ha un’estensione valida."
            case .invalidInput:
                return "Uno dei file sorgente non è un file regolare oppure è vuoto."
            case .invalidDestination:
                return "La destinazione deve essere un file regolare: non può essere una cartella, un collegamento o un file speciale."
            case .invalidStagingOutput:
                return "FFmpeg non ha prodotto un file valido."
            }
        }
    }

    let destinationURL: URL
    let stagingURL: URL

    private let fileManager: FileManager
    private let itemReplacer: ItemReplacer
    private let workspaceRootURL: URL
    private let workspaceURL: URL

    init(
        destinationURL: URL,
        fileManager: FileManager = .default,
        itemReplacer: ItemReplacer? = nil
    ) throws {
        let destinationURL = destinationURL.standardizedFileURL
        let fileExtension = destinationURL.pathExtension
        guard fileExtension.isEmpty == false else {
            throw TransactionError.missingOutputExtension
        }

        try Self.validateDestination(destinationURL, fileManager: fileManager)

        let workspaceRootURL = fileManager.temporaryDirectory
            .appendingPathComponent("AudioProExports", isDirectory: true)
            .standardizedFileURL
        let workspaceURL = workspaceRootURL
            .appendingPathComponent("Export-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
        try fileManager.createDirectory(
            at: workspaceURL,
            withIntermediateDirectories: true
        )

        self.destinationURL = destinationURL
        self.stagingURL = workspaceURL
            .appendingPathComponent("Output")
            .appendingPathExtension(fileExtension)
        self.fileManager = fileManager
        self.itemReplacer = itemReplacer ?? { fileManager, originalURL, replacementURL in
            _ = try fileManager.replaceItemAt(
                originalURL,
                withItemAt: replacementURL,
                backupItemName: nil,
                options: []
            )
        }
        self.workspaceRootURL = workspaceRootURL
        self.workspaceURL = workspaceURL
    }

    /// Copies user-selected inputs into the app container before the sandboxed
    /// child process starts. Only the parent app needs the Powerbox scopes.
    func stageInputs(_ sourceURLs: [URL]) throws -> [URL] {
        guard sourceURLs.isEmpty == false else {
            throw TransactionError.invalidInput
        }

        let inputDirectoryURL = workspaceURL.appendingPathComponent("Inputs", isDirectory: true)
        try fileManager.createDirectory(
            at: inputDirectoryURL,
            withIntermediateDirectories: false
        )

        return try sourceURLs.enumerated().map { index, sourceURL in
            try Self.validateInput(sourceURL, fileManager: fileManager)

            var stagedURL = inputDirectoryURL
                .appendingPathComponent("Input-\(index)")
            if sourceURL.pathExtension.isEmpty == false {
                stagedURL.appendPathExtension(sourceURL.pathExtension)
            }

            try fileManager.copyItem(at: sourceURL, to: stagedURL)
            try Self.validateInput(stagedURL, fileManager: fileManager)
            return stagedURL
        }
    }

    func commit() throws {
        try Self.validateStagingOutput(stagingURL)
        try Self.validateDestination(destinationURL, fileManager: fileManager)

        // `replaceItemAt` is atomic only on one volume. The parent app can use
        // the Powerbox destination scope to obtain this system-managed folder;
        // the ffmpeg child never sees or writes it.
        let replacementDirectoryURL = try fileManager.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: destinationURL,
            create: true
        ).standardizedFileURL
        let replacementURL = replacementDirectoryURL
            .appendingPathComponent("AudioProCommit-\(UUID().uuidString)")
            .appendingPathExtension(destinationURL.pathExtension)
        defer {
            Self.removeReplacementWorkspace(
                replacementURL: replacementURL,
                directoryURL: replacementDirectoryURL,
                fileManager: fileManager
            )
        }

        try fileManager.copyItem(at: stagingURL, to: replacementURL)
        try Self.validateStagingOutput(replacementURL)
        try Self.validateDestination(destinationURL, fileManager: fileManager)

        if fileManager.fileExists(atPath: destinationURL.path) {
            do {
                try itemReplacer(fileManager, destinationURL, replacementURL)
            } catch {
                try? Self.restoreOriginalAfterReplacementFailure(
                    error: error,
                    destinationURL: destinationURL,
                    fileManager: fileManager
                )
                throw error
            }
        } else {
            try fileManager.moveItem(at: replacementURL, to: destinationURL)
        }

        try? fileManager.removeItem(at: stagingURL)
    }

    func discard() {
        guard workspaceURL.deletingLastPathComponent().standardizedFileURL == workspaceRootURL else {
            return
        }
        try? fileManager.removeItem(at: workspaceURL)

        guard let contents = try? fileManager.contentsOfDirectory(
            at: workspaceRootURL,
            includingPropertiesForKeys: nil
        ), contents.isEmpty else {
            return
        }
        try? fileManager.removeItem(at: workspaceRootURL)
    }

    private static func validateInput(_ url: URL, fileManager: FileManager) throws {
        guard (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) == nil else {
            throw TransactionError.invalidInput
        }
        let values = try url.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
        ])
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              let fileSize = values.fileSize,
              fileSize > 0 else {
            throw TransactionError.invalidInput
        }
    }

    private static func validateDestination(_ url: URL, fileManager: FileManager) throws {
        if (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil {
            throw TransactionError.invalidDestination
        }
        if let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]),
           values.isSymbolicLink == true {
            throw TransactionError.invalidDestination
        }

        guard fileManager.fileExists(atPath: url.path) else { return }
        let values = try url.resourceValues(forKeys: [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ])
        guard values.isDirectory != true,
              values.isSymbolicLink != true,
              values.isRegularFile == true else {
            throw TransactionError.invalidDestination
        }
    }

    private static func validateStagingOutput(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
        ])
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              let fileSize = values.fileSize,
              fileSize > 0 else {
            throw TransactionError.invalidStagingOutput
        }
    }

    private static func removeReplacementWorkspace(
        replacementURL: URL,
        directoryURL: URL,
        fileManager: FileManager
    ) {
        guard replacementURL.deletingLastPathComponent().standardizedFileURL == directoryURL else {
            return
        }
        try? fileManager.removeItem(at: replacementURL)
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ), contents.isEmpty else {
            return
        }
        try? fileManager.removeItem(at: directoryURL)
    }

    private static func restoreOriginalAfterReplacementFailure(
        error: Error,
        destinationURL: URL,
        fileManager: FileManager
    ) throws {
        guard fileManager.fileExists(atPath: destinationURL.path) == false,
              let originalURL = (error as NSError).userInfo["NSFileOriginalItemLocationKey"] as? URL,
              fileManager.fileExists(atPath: originalURL.path) else {
            return
        }

        try validateDestination(originalURL, fileManager: fileManager)
        try validateDestination(destinationURL, fileManager: fileManager)
        try fileManager.moveItem(at: originalURL, to: destinationURL)
    }
}

import Foundation

nonisolated enum TranscriptionOutputPathClassifier {
    enum Kind: Equatable, Sendable {
        case missing
        case regularFile
        case unsupported
    }

    static func kind(
        at url: URL,
        fileManager: FileManager = .default
    ) -> Kind {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            guard let fileType = attributes[.type] as? FileAttributeType else {
                return .unsupported
            }
            return fileType == .typeRegular ? .regularFile : .unsupported
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain,
               [
                   CocoaError.Code.fileNoSuchFile.rawValue,
                   CocoaError.Code.fileReadNoSuchFile.rawValue
               ].contains(nsError.code) {
                return .missing
            }
            // Permission errors and unknown filesystem states fail closed.
            return .unsupported
        }
    }
}

nonisolated protocol TranscriptionOutputWriting {
    func validateWriteAccess(to destination: TranscriptionDestination) throws

    func write(
        _ output: TranscriptionOutput,
        to destination: TranscriptionDestination
    ) throws -> TranscriptionWrittenFiles
}

nonisolated struct TranscriptionWrittenFiles: Equatable, Sendable {
    let srtURL: URL?
    let txtURL: URL?
}

nonisolated struct TranscriptionOutputWriter: TranscriptionOutputWriting {
    enum WriteError: LocalizedError, Equatable {
        case outputAlreadyExists
        case unsupportedExistingOutput(String)

        var errorDescription: String? {
            switch self {
            case .outputAlreadyExists:
                return "Uno dei file di destinazione esiste già."
            case .unsupportedExistingOutput(let name):
                return "\(name) non è un file regolare e non può essere sostituito."
            }
        }
    }

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func validateWriteAccess(to destination: TranscriptionDestination) throws {
        let probeURL = destination.directoryURL
            .appendingPathComponent(".audiopro-permission-\(UUID().uuidString)")

        defer {
            removeRegularFileIfPresent(at: probeURL)
        }

        try Data().write(to: probeURL, options: .withoutOverwriting)
        guard TranscriptionOutputPathClassifier.kind(
            at: probeURL,
            fileManager: fileManager
        ) == .regularFile else {
            throw WriteError.unsupportedExistingOutput(probeURL.lastPathComponent)
        }
        try fileManager.removeItem(at: probeURL)
    }

    func write(
        _ output: TranscriptionOutput,
        to destination: TranscriptionDestination
    ) throws -> TranscriptionWrittenFiles {
        struct PlannedFile {
            let finalURL: URL
            let stagedURL: URL
            let contents: String
        }

        let transactionID = UUID().uuidString
        var plannedFiles: [PlannedFile] = []

        if destination.outputSelection.includesSRT {
            plannedFiles.append(
                PlannedFile(
                    finalURL: destination.srtURL,
                    stagedURL: destination.directoryURL
                        .appendingPathComponent(".audiopro-\(transactionID)")
                        .appendingPathExtension("srt"),
                    contents: output.srtText
                )
            )
        }
        if destination.outputSelection.includesTXT {
            plannedFiles.append(
                PlannedFile(
                    finalURL: destination.txtURL,
                    stagedURL: destination.directoryURL
                        .appendingPathComponent(".audiopro-\(transactionID)")
                        .appendingPathExtension("txt"),
                    contents: output.plainText
                )
            )
        }

        let finalURLs = plannedFiles.map(\.finalURL)
        let initialKinds = finalURLs.map {
            TranscriptionOutputPathClassifier.kind(at: $0, fileManager: fileManager)
        }
        if let unsupportedIndex = initialKinds.firstIndex(of: .unsupported) {
            throw WriteError.unsupportedExistingOutput(finalURLs[unsupportedIndex].lastPathComponent)
        }
        if destination.overwriteExisting == false,
           initialKinds.contains(.regularFile) {
            throw WriteError.outputAlreadyExists
        }

        let stagedURLs = plannedFiles.map(\.stagedURL)
        let backupURLs = finalURLs.map {
            destination.directoryURL
                .appendingPathComponent(".audiopro-backup-\(transactionID)-\($0.lastPathComponent)")
        }

        defer {
            // Never recursively remove a transaction path that another process
            // may have replaced with a directory, link, or special file.
            stagedURLs.forEach { removeRegularFileIfPresent(at: $0) }
        }

        for file in plannedFiles {
            try file.contents.write(to: file.stagedURL, atomically: true, encoding: .utf8)
        }

        var backedUpIndexes: [Int] = []
        var installedIndexes: [Int] = []

        do {
            let commitKinds = finalURLs.map {
                TranscriptionOutputPathClassifier.kind(at: $0, fileManager: fileManager)
            }
            if let unsupportedIndex = commitKinds.firstIndex(of: .unsupported) {
                throw WriteError.unsupportedExistingOutput(finalURLs[unsupportedIndex].lastPathComponent)
            }
            if destination.overwriteExisting == false,
               commitKinds.contains(.regularFile) {
                throw WriteError.outputAlreadyExists
            }

            if destination.overwriteExisting {
                for index in finalURLs.indices {
                    switch TranscriptionOutputPathClassifier.kind(
                        at: finalURLs[index],
                        fileManager: fileManager
                    ) {
                    case .missing:
                        continue
                    case .unsupported:
                        throw WriteError.unsupportedExistingOutput(finalURLs[index].lastPathComponent)
                    case .regularFile:
                        guard TranscriptionOutputPathClassifier.kind(
                            at: backupURLs[index],
                            fileManager: fileManager
                        ) == .missing else {
                            throw CocoaError(.fileWriteFileExists)
                        }

                        try fileManager.moveItem(at: finalURLs[index], to: backupURLs[index])

                        guard TranscriptionOutputPathClassifier.kind(
                            at: backupURLs[index],
                            fileManager: fileManager
                        ) == .regularFile else {
                            restoreBackupIfPossible(
                                from: backupURLs[index],
                                to: finalURLs[index]
                            )
                            throw WriteError.unsupportedExistingOutput(finalURLs[index].lastPathComponent)
                        }
                        backedUpIndexes.append(index)
                    }
                }
            }

            for index in finalURLs.indices {
                guard TranscriptionOutputPathClassifier.kind(
                    at: plannedFiles[index].stagedURL,
                    fileManager: fileManager
                ) == .regularFile else {
                    throw WriteError.unsupportedExistingOutput(
                        plannedFiles[index].stagedURL.lastPathComponent
                    )
                }

                switch TranscriptionOutputPathClassifier.kind(
                    at: finalURLs[index],
                    fileManager: fileManager
                ) {
                case .missing:
                    break
                case .regularFile:
                    throw WriteError.outputAlreadyExists
                case .unsupported:
                    throw WriteError.unsupportedExistingOutput(finalURLs[index].lastPathComponent)
                }

                try fileManager.moveItem(
                    at: plannedFiles[index].stagedURL,
                    to: plannedFiles[index].finalURL
                )
                installedIndexes.append(index)
            }

            for index in backedUpIndexes {
                removeRegularFileIfPresent(at: backupURLs[index])
            }
        } catch {
            for index in installedIndexes.reversed() {
                removeRegularFileIfPresent(at: finalURLs[index])
            }
            for index in backedUpIndexes.reversed() {
                restoreBackupIfPossible(
                    from: backupURLs[index],
                    to: finalURLs[index]
                )
            }
            throw error
        }

        return TranscriptionWrittenFiles(
            srtURL: destination.outputSelection.includesSRT ? destination.srtURL : nil,
            txtURL: destination.outputSelection.includesTXT ? destination.txtURL : nil
        )
    }

    private func removeRegularFileIfPresent(at url: URL) {
        guard TranscriptionOutputPathClassifier.kind(
            at: url,
            fileManager: fileManager
        ) == .regularFile else {
            return
        }
        try? fileManager.removeItem(at: url)
    }

    private func restoreBackupIfPossible(from backupURL: URL, to finalURL: URL) {
        guard TranscriptionOutputPathClassifier.kind(
            at: backupURL,
            fileManager: fileManager
        ) == .regularFile,
        TranscriptionOutputPathClassifier.kind(
            at: finalURL,
            fileManager: fileManager
        ) == .missing else {
            // Preserve the backup when restoring it safely is not possible.
            return
        }
        try? fileManager.moveItem(at: backupURL, to: finalURL)
    }
}

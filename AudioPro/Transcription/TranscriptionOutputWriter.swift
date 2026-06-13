import Foundation

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

        var errorDescription: String? {
            switch self {
            case .outputAlreadyExists:
                return "Uno dei file di destinazione esiste già."
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
            try? fileManager.removeItem(at: probeURL)
        }

        try Data().write(to: probeURL, options: .withoutOverwriting)
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
        if destination.overwriteExisting == false,
           finalURLs.contains(where: { fileManager.fileExists(atPath: $0.path) }) {
            throw WriteError.outputAlreadyExists
        }

        let stagedURLs = plannedFiles.map(\.stagedURL)
        let backupURLs = finalURLs.map {
            destination.directoryURL
                .appendingPathComponent(".audiopro-backup-\(transactionID)-\($0.lastPathComponent)")
        }

        defer {
            (stagedURLs + backupURLs).forEach { try? fileManager.removeItem(at: $0) }
        }

        for file in plannedFiles {
            try file.contents.write(to: file.stagedURL, atomically: true, encoding: .utf8)
        }

        var backedUpIndexes: [Int] = []
        var installedIndexes: [Int] = []

        do {
            for index in finalURLs.indices where fileManager.fileExists(atPath: finalURLs[index].path) {
                try fileManager.moveItem(at: finalURLs[index], to: backupURLs[index])
                backedUpIndexes.append(index)
            }

            for index in finalURLs.indices {
                try fileManager.moveItem(
                    at: plannedFiles[index].stagedURL,
                    to: plannedFiles[index].finalURL
                )
                installedIndexes.append(index)
            }

            for index in backedUpIndexes {
                try? fileManager.removeItem(at: backupURLs[index])
            }
        } catch {
            for index in installedIndexes.reversed() {
                try? fileManager.removeItem(at: finalURLs[index])
            }
            for index in backedUpIndexes.reversed()
                where fileManager.fileExists(atPath: backupURLs[index].path) {
                try? fileManager.moveItem(at: backupURLs[index], to: finalURLs[index])
            }
            throw error
        }

        return TranscriptionWrittenFiles(
            srtURL: destination.outputSelection.includesSRT ? destination.srtURL : nil,
            txtURL: destination.outputSelection.includesTXT ? destination.txtURL : nil
        )
    }
}

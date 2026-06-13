import Foundation

nonisolated enum TranscriptionOutputSelection: String, CaseIterable, Identifiable, Sendable {
    case srtAndTxt
    case srtOnly
    case txtOnly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .srtAndTxt:
            return "SRT + TXT"
        case .srtOnly:
            return "Solo SRT"
        case .txtOnly:
            return "Solo TXT"
        }
    }

    var includesSRT: Bool {
        self != .txtOnly
    }

    var includesTXT: Bool {
        self != .srtOnly
    }

    var creationDescription: String {
        switch self {
        case .srtAndTxt:
            return "Verranno creati un file SRT e un file TXT."
        case .srtOnly:
            return "Verrà creato un file SRT sincronizzato."
        case .txtOnly:
            return "Verrà creato un file TXT senza sincronizzazione."
        }
    }
}

nonisolated struct TranscriptionDestination: Equatable, Sendable {
    let directoryURL: URL
    let baseName: String
    let outputSelection: TranscriptionOutputSelection
    let overwriteExisting: Bool
    let securityScopedURL: URL?

    init(
        directoryURL: URL,
        baseName: String,
        outputSelection: TranscriptionOutputSelection = .srtAndTxt,
        overwriteExisting: Bool,
        securityScopedURL: URL? = nil
    ) {
        self.directoryURL = directoryURL
        self.baseName = baseName
        self.outputSelection = outputSelection
        self.overwriteExisting = overwriteExisting
        self.securityScopedURL = securityScopedURL
    }

    var srtURL: URL {
        directoryURL
            .appendingPathComponent(baseName)
            .appendingPathExtension("srt")
    }

    var txtURL: URL {
        directoryURL
            .appendingPathComponent(baseName)
            .appendingPathExtension("txt")
    }

    var selectedURLs: [URL] {
        var urls: [URL] = []
        if outputSelection.includesSRT {
            urls.append(srtURL)
        }
        if outputSelection.includesTXT {
            urls.append(txtURL)
        }
        return urls
    }

    var securityScopeURL: URL {
        securityScopedURL ?? directoryURL
    }
}

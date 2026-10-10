import SwiftUI
import UniformTypeIdentifiers

/// File ricevuto con un trascinamento, pronto per la coda o per il player.
struct DroppedFile: Sendable {
    let url: URL
    /// Presente quando il file arriva dal Finder con un'estensione sandbox:
    /// va mantenuta finché il file è in uso.
    let securityScopedURL: URL?

    var isTranscript: Bool { url.pathExtension.lowercased() == "srt" }
}

/// Trascinamento condiviso dalle tre sezioni. Gestisce sia i file del Finder
/// (URL già esistente) sia le registrazioni di Memo Vocali, che arrivano come
/// "file promise": il file nasce solo al rilascio, quindi viene copiato in una
/// cartella dell'app prima di usarlo.
enum MediaDrop {
    static let srtType = UTType(filenameExtension: "srt") ?? .plainText

    static func acceptedTypes(includingTranscripts: Bool) -> [UTType] {
        includingTranscripts ? [.audio, .movie, .fileURL, srtType] : [.audio, .movie, .fileURL]
    }

    nonisolated static func load(
        _ providers: [NSItemProvider],
        includingTranscripts: Bool
    ) async -> [DroppedFile] {
        var files: [DroppedFile] = []
        for provider in providers {
            guard let file = await loadFile(from: provider) else { continue }
            if isSupported(file.url, includingTranscripts: includingTranscripts) {
                files.append(file)
            } else if let scoped = file.securityScopedURL {
                scoped.stopAccessingSecurityScopedResource()
            }
        }
        return files
    }

    // MARK: - Caricamento

    private nonisolated static func loadFile(from provider: NSItemProvider) async -> DroppedFile? {
        // 1. Finder: l'URL del file originale, con accesso concesso dal drag.
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let url = await loadURLObject(from: provider) {
            let hasScope = url.startAccessingSecurityScopedResource()
            if FileManager.default.fileExists(atPath: url.path) {
                return DroppedFile(url: url, securityScopedURL: hasScope ? url : nil)
            }
            if hasScope { url.stopAccessingSecurityScopedResource() }
        }

        // 2. Memo Vocali e altre app: rappresentazione del file audio o video.
        guard let typeIdentifier = provider.registeredTypeIdentifiers.first(where: { identifier in
            guard let type = UTType(identifier) else { return false }
            return type.conforms(to: .audio) || type.conforms(to: .movie)
        }) else {
            return nil
        }
        return await copyFileRepresentation(
            from: provider,
            typeIdentifier: typeIdentifier
        ).map { DroppedFile(url: $0, securityScopedURL: nil) }
    }

    private nonisolated static func loadURLObject(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }

    /// Il file temporaneo della rappresentazione viene eliminato al termine
    /// del callback: lo copio subito in una cartella dell'app.
    private nonisolated static func copyFileRepresentation(
        from provider: NSItemProvider,
        typeIdentifier: String
    ) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { temporaryURL, _ in
                guard let temporaryURL else {
                    continuation.resume(returning: nil)
                    return
                }
                let folder = importsFolder().appendingPathComponent(UUID().uuidString, isDirectory: true)
                let name = fileName(suggested: provider.suggestedName, fallback: temporaryURL)
                let destination = folder.appendingPathComponent(name)
                do {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: temporaryURL, to: destination)
                    continuation.resume(returning: destination)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private nonisolated static func importsFolder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Memo Vocali", isDirectory: true)
    }

    private nonisolated static func fileName(suggested: String?, fallback: URL) -> String {
        let fallbackExtension = fallback.pathExtension
        guard var name = suggested?.trimmingCharacters(in: .whitespacesAndNewlines), name.isEmpty == false else {
            return fallback.lastPathComponent
        }
        name = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        if (name as NSString).pathExtension.isEmpty, fallbackExtension.isEmpty == false {
            name += ".\(fallbackExtension)"
        }
        return name
    }

    private nonisolated static func isSupported(_ url: URL, includingTranscripts: Bool) -> Bool {
        if includingTranscripts, url.pathExtension.lowercased() == "srt" { return true }
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
            ?? UTType(filenameExtension: url.pathExtension)
        guard let type else { return false }
        return type.conforms(to: .audio) || type.conforms(to: .movie)
    }
}

/// Destinazione di trascinamento con evidenziazione discreta, uguale in
/// tutte le sezioni.
private struct MediaDropModifier: ViewModifier {
    let isEnabled: Bool
    let includesTranscripts: Bool
    let onDrop: ([DroppedFile]) -> Void
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .onDrop(
                of: MediaDrop.acceptedTypes(includingTranscripts: includesTranscripts),
                isTargeted: $isTargeted
            ) { providers in
                guard isEnabled else { return false }
                let includesTranscripts = includesTranscripts
                Task {
                    let files = await MediaDrop.load(providers, includingTranscripts: includesTranscripts)
                    guard files.isEmpty == false else { return }
                    onDrop(files)
                }
                return true
            }
            .overlay {
                if isTargeted && isEnabled {
                    RoundedRectangle(cornerRadius: LiquidGlassDesign.cardCornerRadius, style: .continuous)
                        .fill(Color.accentColor.opacity(0.06))
                        .strokeBorder(Color.accentColor.opacity(0.8), lineWidth: 2)
                        .padding(8)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.15), value: isTargeted)
    }
}

extension View {
    /// Accetta audio e video trascinati dal Finder o da Memo Vocali
    /// (e, se richiesto, file SRT).
    func mediaDropDestination(
        isEnabled: Bool = true,
        includesTranscripts: Bool = false,
        perform onDrop: @escaping ([DroppedFile]) -> Void
    ) -> some View {
        modifier(MediaDropModifier(
            isEnabled: isEnabled,
            includesTranscripts: includesTranscripts,
            onDrop: onDrop
        ))
    }
}

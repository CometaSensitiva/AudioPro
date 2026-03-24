// ============================================================================
// FILE 2: AudioFile.swift
// Modello per rappresentare un file audio nella lista con metadata
// ============================================================================

import Foundation
import AVFoundation
import Combine
import UniformTypeIdentifiers

enum MetadataState: Equatable, Sendable {
    case loading
    case ready
    case failed(message: String)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var failureMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

@MainActor
class AudioFile: ObservableObject, Identifiable, Equatable, Hashable {
    private struct MetadataSnapshot: Sendable {
        let duration: TimeInterval?
        let fileSize: Int64?
        let codec: String?
        let metadataState: MetadataState
    }

    let id = UUID()
    @Published var url: URL
    private let securityScopedURL: URL?
    
    // Metadata
    @Published var duration: TimeInterval?
    @Published var fileSize: Int64?
    @Published var codec: String?
    @Published var metadataState: MetadataState
    
    var name: String {
        url.lastPathComponent
    }
    
    var formattedDuration: String {
        guard let duration = duration else { return "—" }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var formattedFileSize: String {
        guard let size = fileSize else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    var isVideo: Bool {
        let resourceValues = try? url.resourceValues(forKeys: [.contentTypeKey])
        if let contentType = resourceValues?.contentType {
            return contentType.conforms(to: .movie)
        }

        if let fallbackType = UTType(filenameExtension: url.pathExtension) {
            return fallbackType.conforms(to: .movie)
        }

        let ext = url.pathExtension.lowercased()
        return ["mp4", "mov", "mkv", "avi", "webm"].contains(ext)
    }
    
    /// Inizializza con caricamento automatico metadata
    init(url: URL, securityScopedURL: URL? = nil, loadMetadata: Bool = true) {
        self.url = url
        self.securityScopedURL = securityScopedURL
        self.metadataState = loadMetadata ? .loading : .ready

        guard loadMetadata else { return }
        // Carica metadata fuori dal MainActor e applica solo il risultato finale alla UI.
        Task.detached(priority: .utility) { [url] in
            let metadata = await AudioFile.loadMetadataSnapshot(for: url)
            await MainActor.run { [weak self] in
                guard let self else { return }
                guard self.url == url else { return }
                self.duration = metadata.duration
                self.fileSize = metadata.fileSize
                self.codec = metadata.codec
                self.metadataState = metadata.metadataState
            }
        }
    }

    deinit {
        securityScopedURL?.stopAccessingSecurityScopedResource()
    }
    
    /// Carica i metadata del file audio usando API moderne fuori dal MainActor.
    private nonisolated static func loadMetadataSnapshot(for url: URL) async -> MetadataSnapshot {
        var fileSize: Int64?
        var duration: TimeInterval?
        var codec: String?
        var metadataState: MetadataState = .ready

        // Carica dimensione file
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attributes[.size] as? Int64 {
            fileSize = size
        }
        
        // Carica metadata audio con AVFoundation moderne API
        let asset = AVURLAsset(url: url)
        
        // Carica durata in modo asincrono
        if let loadedDuration = try? await asset.load(.duration) {
            duration = loadedDuration.seconds
        }
        
        // Carica track audio in modo asincrono
        if let tracks = try? await asset.loadTracks(withMediaType: .audio),
           let audioTrack = tracks.first {
            // Carica format descriptions
            if let descriptions = try? await audioTrack.load(.formatDescriptions),
               let description = descriptions.first {
                let mediaSubType = CMFormatDescriptionGetMediaSubType(description)
                codec = fourCCToString(mediaSubType)
            }
        }

        if duration == nil && fileSize == nil && codec == nil {
            metadataState = .failed(message: "Metadata non disponibili")
        }

        return MetadataSnapshot(
            duration: duration,
            fileSize: fileSize,
            codec: codec,
            metadataState: metadataState
        )
    }
    
    /// Converte FourCC code in stringa
    private nonisolated static func fourCCToString(_ code: FourCharCode) -> String {
        let chars: [UInt8] = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF)
        ]
        return String(bytes: chars, encoding: .ascii) ?? "unknown"
    }
    
    static func == (lhs: AudioFile, rhs: AudioFile) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

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
        let hasAudioTrack: Bool?
        let hasVideoTrack: Bool?
        let contentModificationDate: Date?
        let contentTypeIdentifier: String?
        let metadataState: MetadataState
    }

    nonisolated let id = UUID()
    @Published var url: URL {
        didSet {
            guard url != oldValue else { return }
            guard shouldLoadMetadata else {
                let topology = Self.inferredTrackTopology(for: url)
                hasAudioTrack = topology.hasAudio
                hasVideoTrack = topology.hasVideo
                contentModificationDate = nil
                contentTypeIdentifier = nil
                return
            }
            resetMetadataForReload()
            beginMetadataLoad(for: url)
        }
    }
    private let securityScopedURL: URL?
    private let shouldLoadMetadata: Bool
    private var contentModificationDate: Date?
    private var contentTypeIdentifier: String?
    
    // Metadata
    @Published var duration: TimeInterval?
    @Published var fileSize: Int64?
    @Published var codec: String?
    @Published var hasAudioTrack: Bool?
    @Published var hasVideoTrack: Bool?
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

    /// Data di ultima modifica del file (per la colonna tabella stile Finder).
    var formattedModifiedDate: String {
        guard let date = contentModificationDate else { return "—" }
        return date.formatted(
            .dateTime
                .day()
                .month(.abbreviated)
                .year()
                .hour()
                .minute()
                .locale(Locale(identifier: "it_IT"))
        )
    }

    /// Descrizione del tipo di file (colonna "Tipo").
    var kindLabel: String {
        if let contentTypeIdentifier,
           let type = UTType(contentTypeIdentifier) {
            return type.localizedDescription ?? url.pathExtension.uppercased()
        }
        if let type = UTType(filenameExtension: url.pathExtension) {
            return type.localizedDescription ?? url.pathExtension.uppercased()
        }
        return url.pathExtension.uppercased()
    }

    var isVideo: Bool {
        if let hasVideoTrack {
            return hasVideoTrack
        }
        return Self.inferredIsVideo(
            for: url,
            contentTypeIdentifier: contentTypeIdentifier
        )
    }
    
    /// Inizializza con caricamento automatico metadata
    init(url: URL, securityScopedURL: URL? = nil, loadMetadata: Bool = true) {
        self.url = url
        self.securityScopedURL = securityScopedURL
        self.shouldLoadMetadata = loadMetadata
        let inferredTopology = Self.inferredTrackTopology(for: url)
        self.hasAudioTrack = loadMetadata ? nil : inferredTopology.hasAudio
        self.hasVideoTrack = loadMetadata ? nil : inferredTopology.hasVideo
        self.metadataState = loadMetadata ? .loading : .ready

        guard loadMetadata else { return }
        beginMetadataLoad(for: url)
    }

    private func beginMetadataLoad(for url: URL) {
        // Carica metadata fuori dal MainActor e applica solo il risultato finale alla UI.
        Task.detached(priority: .utility) { [url] in
            let metadata = await AudioFile.loadMetadataSnapshot(for: url)
            await MainActor.run { [weak self] in
                guard let self else { return }
                guard self.url == url else { return }
                self.duration = metadata.duration
                self.fileSize = metadata.fileSize
                self.codec = metadata.codec
                self.hasAudioTrack = metadata.hasAudioTrack
                self.hasVideoTrack = metadata.hasVideoTrack
                self.contentModificationDate = metadata.contentModificationDate
                self.contentTypeIdentifier = metadata.contentTypeIdentifier
                self.metadataState = metadata.metadataState
            }
        }
    }

    private func resetMetadataForReload() {
        duration = nil
        fileSize = nil
        codec = nil
        hasAudioTrack = nil
        hasVideoTrack = nil
        contentModificationDate = nil
        contentTypeIdentifier = nil
        metadataState = .loading
    }

    deinit {
        securityScopedURL?.stopAccessingSecurityScopedResource()
    }
    
    /// Carica i metadata del file audio usando API moderne fuori dal MainActor.
    private nonisolated static func loadMetadataSnapshot(for url: URL) async -> MetadataSnapshot {
        var fileSize: Int64?
        var duration: TimeInterval?
        var codec: String?
        var hasAudioTrack: Bool?
        var hasVideoTrack: Bool?
        var metadataState: MetadataState = .ready

        // Carica in un'unica lettura i valori usati dalle colonne Finder-style.
        let resourceValues = try? url.resourceValues(
            forKeys: [.fileSizeKey, .contentModificationDateKey, .contentTypeKey]
        )
        if let size = resourceValues?.fileSize {
            fileSize = Int64(size)
        }
        let contentModificationDate = resourceValues?.contentModificationDate
        let contentTypeIdentifier = resourceValues?.contentType?.identifier
        
        // Carica metadata audio con AVFoundation moderne API
        let asset = AVURLAsset(url: url)
        
        // Carica durata in modo asincrono
        if let loadedDuration = try? await asset.load(.duration) {
            duration = loadedDuration.seconds
        }
        
        // Carica track audio in modo asincrono
        if let audioTracks = try? await asset.loadTracks(withMediaType: .audio) {
            hasAudioTrack = audioTracks.isEmpty == false
            if let audioTrack = audioTracks.first {
                // Carica format descriptions
                if let descriptions = try? await audioTrack.load(.formatDescriptions),
                   let description = descriptions.first {
                    let mediaSubType = CMFormatDescriptionGetMediaSubType(description)
                    codec = fourCCToString(mediaSubType)
                }
            }
        }

        if let videoTracks = try? await asset.loadTracks(withMediaType: .video) {
            hasVideoTrack = videoTracks.isEmpty == false
        }

        if hasAudioTrack == nil || hasVideoTrack == nil {
            metadataState = .failed(message: "Impossibile analizzare le tracce multimediali")
        } else if hasAudioTrack == false && hasVideoTrack == false {
            metadataState = .failed(message: "Nessuna traccia audio o video disponibile")
        }

        return MetadataSnapshot(
            duration: duration,
            fileSize: fileSize,
            codec: codec,
            hasAudioTrack: hasAudioTrack,
            hasVideoTrack: hasVideoTrack,
            contentModificationDate: contentModificationDate,
            contentTypeIdentifier: contentTypeIdentifier,
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

    private nonisolated static func inferredTrackTopology(
        for url: URL
    ) -> (hasAudio: Bool, hasVideo: Bool) {
        guard let type = UTType(filenameExtension: url.pathExtension) else {
            let isVideo = inferredIsVideo(for: url, contentTypeIdentifier: nil)
            return (isVideo, isVideo)
        }
        if type.conforms(to: .movie) {
            // Test/preview-only instances have no AVAsset probe. Assume the
            // common movie topology; production instances replace this with
            // actual track discovery before export becomes available.
            return (true, true)
        }
        if type.conforms(to: .audio) {
            return (true, false)
        }
        return (false, false)
    }

    private nonisolated static func inferredIsVideo(
        for url: URL,
        contentTypeIdentifier: String?
    ) -> Bool {
        if let contentTypeIdentifier,
           let contentType = UTType(contentTypeIdentifier) {
            if contentType.conforms(to: .movie) {
                return true
            }
            if contentType.conforms(to: .audio) {
                return false
            }
        }

        if let fallbackType = UTType(filenameExtension: url.pathExtension) {
            return fallbackType.conforms(to: .movie)
        }

        let fileExtension = url.pathExtension.lowercased()
        return ["mp4", "m4v", "mov", "mkv", "avi", "webm", "mpeg", "mpg"]
            .contains(fileExtension)
    }
    
    nonisolated static func == (lhs: AudioFile, rhs: AudioFile) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

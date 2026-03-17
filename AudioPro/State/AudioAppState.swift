import Foundation
import SwiftUI
import Combine
import AppKit

/// Stato condiviso dell'app: file caricati, selezione, ricerca, impostazioni di compressione e stato di processing.
@MainActor
final class AudioAppState: ObservableObject {
    private static let sharedProcessor = AudioProcessor()

    @Published var audioFiles: [AudioFile] = []
    @Published var selectedFile: AudioFile?
    @Published var searchText: String = ""
    @Published var isInspectorPresented: Bool = false
    @Published var processingState: ProcessingState = .idle
    @Published var compression: CompressionSettings = .medium {
        didSet {
            if oldValue != compression {
                markReadyForNextExport()
            }
        }
    }
    private let processor = sharedProcessor
    private var fileChangeCancellables: [ObjectIdentifier: AnyCancellable] = [:]

    deinit {
        fileChangeCancellables.removeAll()
    }
    
    /// File filtrati in base alla ricerca.
    var filteredFiles: [AudioFile] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return audioFiles }
        return audioFiles.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var exportPreview: ExportPreview {
        ExportPreview.make(files: audioFiles, compression: compression)
    }

    var totalDuration: TimeInterval? {
        exportPreview.totalDuration
    }

    var isExportActionEnabled: Bool {
        guard selectedFile != nil else { return false }
        guard processingState.canStartNewExport else { return false }
        return exportPreview.canExport
    }

    var exportDisabledReason: String? {
        if processingState.isBusy {
            return "Esportazione in corso."
        }
        if audioFiles.isEmpty {
            return "Aggiungi almeno un file per esportare."
        }
        if selectedFile == nil {
            return "Seleziona un file."
        }
        return exportPreview.validation.message
    }
    
    /// Sposta gli elementi nella lista in base alla gesture di reorder.
    func moveFiles(from offsets: IndexSet, to destination: Int) {
        audioFiles.move(fromOffsets: offsets, toOffset: destination)
        markReadyForNextExport()
    }
    
    func clearAll() {
        audioFiles.removeAll()
        fileChangeCancellables.removeAll()
        selectedFile = nil
        markReadyForNextExport()
    }
    
    func addFiles(_ files: [AudioFile]) {
        observe(files)
        audioFiles.append(contentsOf: files)
        if selectedFile == nil {
            selectedFile = files.first
        }
        markReadyForNextExport()
    }
    
    func remove(_ file: AudioFile) {
        audioFiles.removeAll { $0 == file }
        stopObserving(file)
        if selectedFile == file {
            selectedFile = audioFiles.first
        }
        markReadyForNextExport()
    }
    
    func remove(atOffsets offsets: IndexSet) {
        let removedFiles = offsets.map { audioFiles[$0] }
        audioFiles.remove(atOffsets: offsets)
        removedFiles.forEach(stopObserving(_:))
        if let selected = selectedFile, audioFiles.contains(where: { $0 == selected }) == false {
            selectedFile = audioFiles.first
        }
        markReadyForNextExport()
    }
    
    func rename(_ file: AudioFile, to newName: String) {
        let originalURL = file.url
        let ext = originalURL.pathExtension
        guard let proposedName = sanitizedFileName(from: newName, originalExtension: ext) else { return }

        let directoryURL = originalURL.deletingLastPathComponent().standardizedFileURL
        let destination = directoryURL
            .appendingPathComponent(proposedName)
            .standardizedFileURL

        guard destination.deletingLastPathComponent() == directoryURL else { return }
        guard destination != originalURL.standardizedFileURL else { return }
        
        do {
            try FileManager.default.moveItem(at: originalURL, to: destination)
            file.url = destination
            markReadyForNextExport()
        } catch {
            print("Rename failed: \(error)")
        }
    }
    
    /// Avvia l'export usando ffmpeg. Richiede almeno un file in coda.
    func startExport(to outputURL: URL) {
        guard audioFiles.isEmpty == false else { return }
        guard processingState.canStartNewExport else { return }

        let preview = exportPreview
        guard preview.canExport, let ffmpegSettings = preview.ffmpegSettings else {
            if let message = preview.validation.message {
                processingState = .failed(message: message)
            }
            return
        }
        
        processingState = .running(progress: 0)
        let fileURLs = audioFiles.map(\.url)
        let processor = self.processor
        
        Task {
            let result = await processor.process(
                fileURLs: fileURLs,
                outputURL: outputURL,
                settings: ffmpegSettings,
                estimatedTotalDuration: preview.totalDuration,
                progressCallback: { @MainActor progress in
                    self.updateProgress(progress)
                }
            )
            
            switch result {
            case .success:
                processingState = .completed
                NotificationManager.shared.notifyExportFinished(outputURL: outputURL)
            case .failure(let error):
                if case .cancelled = error {
                    return
                }
                processingState = .failed(message: error.localizedDescription)
            }
        }
    }
    
    func cancelExport() {
        Task {
            await processor.cancel()
            if case .running = processingState {
                processingState = .idle
            }
        }
    }
    
    private func updateProgress(_ progress: Double) {
        // Evita che aggiornamenti tardivi sovrascrivano stati terminali (.completed/.failed)
        guard case .running(let currentProgress) = processingState else { return }
        let clampedProgress = min(max(progress, 0), 1)
        guard abs(clampedProgress - currentProgress) >= 0.01 || clampedProgress >= 1 else { return }
        processingState = .running(progress: clampedProgress)
    }
    
    private func markReadyForNextExport() {
        if case .running = processingState { return }
        if processingState != .idle {
            processingState = .idle
        }
    }

    private func observe(_ files: [AudioFile]) {
        for file in files {
            let key = ObjectIdentifier(file)
            guard fileChangeCancellables[key] == nil else { continue }

            fileChangeCancellables[key] = file.objectWillChange.sink { [weak self] _ in
                self?.objectWillChange.send()
            }
        }
    }

    private func stopObserving(_ file: AudioFile) {
        fileChangeCancellables.removeValue(forKey: ObjectIdentifier(file))
    }

    private func sanitizedFileName(from rawName: String, originalExtension: String) -> String? {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        guard trimmed != "." && trimmed != ".." else { return nil }

        let forbiddenCharacters = CharacterSet(charactersIn: "/:")
        guard trimmed.rangeOfCharacter(from: forbiddenCharacters) == nil else { return nil }
        guard trimmed.contains("..") == false else { return nil }

        if trimmed.contains(".") {
            return trimmed
        }
        if originalExtension.isEmpty {
            return trimmed
        }
        return "\(trimmed).\(originalExtension)"
    }
}

// MARK: - Compression

struct CompressionSettings: Equatable, Sendable {
    var quality: Double   // 0...1, dove 1 = qualità alta, meno compressione
    var sampleRate: SampleRate
    var codec: Codec
    var preset: Preset
    var maxOutputSizeMB: Double? = nil
    
    var bitrateLabel: String {
        let kbps = Int(baseBitrateKbps.rounded())
        return "\(kbps) kbps"
    }

    /// Stima bitrate in kbps in base a preset e qualità.
    var baseBitrateKbps: Double {
        // Semplice mapping lineare tra preset e qualità.
        let base: Double
        switch preset {
        case .low: base = 64
        case .medium: base = 96
        case .high: base = 128
        case .pro: base = 192
        }
        // Aggiusta leggermente con lo slider (±25%).
        let delta = (quality - 0.5) * 0.5
        return max(32, base * (1 + delta))
    }

    func targetBitrateKbps(for totalDuration: TimeInterval?) -> Double? {
        guard codec != .copy else { return nil }
        guard let maxOutputSizeMB, let totalDuration, totalDuration > 0 else { return nil }

        let bitsPerSecond = (maxOutputSizeMB * 1_000_000 * 8) / totalDuration
        let kbps = bitsPerSecond / 1_000
        return max(32, kbps)
    }

    func resolvedBitrateKbps(for totalDuration: TimeInterval?) -> Double {
        targetBitrateKbps(for: totalDuration) ?? baseBitrateKbps
    }

    func bitrateLabel(for totalDuration: TimeInterval?) -> String {
        let kbps = Int(resolvedBitrateKbps(for: totalDuration).rounded())
        return "\(kbps) kbps"
    }

    var maxOutputSizeLabel: String? {
        guard let maxOutputSizeMB else { return nil }
        return String(format: "%.0f MB", maxOutputSizeMB)
    }

    func ffmpegBitrate(for totalDuration: TimeInterval?) -> String {
        "\(Int(resolvedBitrateKbps(for: totalDuration)))k"
    }
    
    var ffmpegSampleRate: String {
        switch sampleRate {
        case .s44100: return "44100"
        case .s48000: return "48000"
        }
    }
    
    var ffmpegCodec: String {
        switch codec {
        case .aac: return "aac"
        case .alac: return "alac"
        case .opus: return "libopus"
        case .copy: return "copy"
        }
    }
    
    static let medium = CompressionSettings(quality: 0.5,
                                            sampleRate: .s44100,
                                            codec: .aac,
                                            preset: .medium,
                                            maxOutputSizeMB: nil)
}

enum SampleRate: String, CaseIterable, Identifiable, Sendable {
    case s44100 = "44.1 kHz"
    case s48000 = "48 kHz"
    var id: String { rawValue }
}

enum Codec: String, CaseIterable, Identifiable, Sendable {
    case aac = "AAC"
    case alac = "ALAC"
    case opus = "Opus"
    case copy = "Copia Stream"
    var id: String { rawValue }
}

enum Preset: String, CaseIterable, Identifiable, Sendable {
    case low = "Bassa"
    case medium = "Media"
    case high = "Alta"
    case pro = "Pro"
    var id: String { rawValue }
}

// MARK: - Processing

enum ProcessingState: Equatable {
    case idle
    case running(progress: Double)
    case completed
    case failed(message: String)
    
    var progressValue: Double {
        switch self {
        case .running(let progress): return progress
        default: return 0
        }
    }
    
    var canStartNewExport: Bool {
        switch self {
        case .idle, .completed, .failed:
            return true
        case .running:
            return false
        }
    }
}

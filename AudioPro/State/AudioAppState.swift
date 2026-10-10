import Foundation
import SwiftUI
import Combine
import AppKit
import UniformTypeIdentifiers

/// Stato condiviso dell'app: file caricati, selezione, ricerca, impostazioni di compressione e stato di processing.
@MainActor
final class AudioAppState: ObservableObject {
    struct ExportDestinationDefaults: Equatable {
        let fileName: String
        let allowedContentTypes: [UTType]
        let message: String
    }

    @Published private(set) var audioFiles: [AudioFile] = []
    @Published var selectedFile: AudioFile?
    @Published var searchText: String = ""
    @Published var isInspectorPresented: Bool = false
    @Published var processingState: ProcessingState = .idle
    @Published private(set) var notificationPermissionState: NotificationPermissionState = .unknown
    @Published private(set) var lastCompletedOutputURL: URL?
    @Published var compression: CompressionSettings = .medium {
        didSet {
            if oldValue != compression {
                markReadyForNextExport()
            }
        }
    }
    private let processor: any ExportProcessing
    private let notifier: any ExportNotifying
    private var fileChangeCancellables: [ObjectIdentifier: AnyCancellable] = [:]
    private var exportTask: Task<Void, Never>?
    private var activeExportID: UUID?
    private var activeExportFiles: [AudioFile] = []

    init(
        processor: any ExportProcessing,
        notifier: any ExportNotifying
    ) {
        self.processor = processor
        self.notifier = notifier
    }

    convenience init() {
        self.init(processor: AudioProcessor(), notifier: NotificationManager.shared)
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

    var exportDestinationDefaults: ExportDestinationDefaults {
        let baseName = suggestedExportBaseName
        switch exportPreview.outputFormat ?? .m4a {
        case .m4a:
            return ExportDestinationDefaults(
                fileName: "\(baseName).m4a",
                allowedContentTypes: [.mpeg4Audio],
                message: "Salva come M4A (audio)"
            )
        case .opus:
            return ExportDestinationDefaults(
                fileName: "\(baseName).opus",
                // macOS associa oggi `.opus` al tipo Ogg la cui estensione
                // preferita è `.ogg`; il tipo audio generico preserva invece
                // il nome `.opus` proposto dal pannello.
                allowedContentTypes: [.audio],
                message: "Salva come Opus (audio)"
            )
        case .mp4:
            return ExportDestinationDefaults(
                fileName: "\(baseName).mp4",
                allowedContentTypes: [.mpeg4Movie],
                message: "Salva come MP4 compresso"
            )
        case .source(let fileExtension):
            let contentType = UTType(filenameExtension: fileExtension) ?? .audio
            return ExportDestinationDefaults(
                fileName: "\(baseName).\(fileExtension)",
                allowedContentTypes: [contentType],
                message: "Salva nel formato originale \(fileExtension.uppercased())"
            )
        }
    }

    private var suggestedExportBaseName: String {
        if audioFiles.count == 1, let file = audioFiles.first {
            let sourceName = file.url.deletingPathExtension().lastPathComponent
            if sourceName.isEmpty == false {
                return "\(sourceName) esportato"
            }
        }

        if audioFiles.count > 1 {
            return "Unione \(audioFiles.count) file"
        }

        return "Esportazione"
    }

    var canModifyQueue: Bool {
        processingState.isBusy == false
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
        guard canModifyQueue else { return }
        audioFiles.move(fromOffsets: offsets, toOffset: destination)
        markReadyForNextExport()
    }

    /// Riordina usando identificatori stabili, come richiesto dal drag di una Table.
    func moveFiles(withIDs ids: [AudioFile.ID], to destination: Int) {
        guard canModifyQueue, (0...audioFiles.count).contains(destination) else { return }

        let requestedIDs = Set(ids)
        let offsets = IndexSet(audioFiles.indices.filter { requestedIDs.contains(audioFiles[$0].id) })
        guard offsets.isEmpty == false else { return }

        audioFiles.move(fromOffsets: offsets, toOffset: destination)
        markReadyForNextExport()
    }

    /// Sposta ogni blocco selezionato di una posizione, per menu contestuale,
    /// tastiera e tecnologie assistive. L'ordine relativo resta stabile.
    func moveFiles(withIDs ids: Set<AudioFile.ID>, by offset: Int) {
        guard canModifyQueue, offset == -1 || offset == 1 else { return }
        let selectedIDs = ids.intersection(audioFiles.map(\.id))
        guard selectedIDs.isEmpty == false else { return }

        var didMove = false
        if offset < 0 {
            for index in audioFiles.indices where selectedIDs.contains(audioFiles[index].id) {
                guard index > audioFiles.startIndex,
                      selectedIDs.contains(audioFiles[index - 1].id) == false else { continue }
                audioFiles.swapAt(index, index - 1)
                didMove = true
            }
        } else {
            for index in audioFiles.indices.reversed() where selectedIDs.contains(audioFiles[index].id) {
                guard index < audioFiles.index(before: audioFiles.endIndex),
                      selectedIDs.contains(audioFiles[index + 1].id) == false else { continue }
                audioFiles.swapAt(index, index + 1)
                didMove = true
            }
        }

        if didMove {
            markReadyForNextExport()
        }
    }
    
    func clearAll() {
        guard canModifyQueue else { return }
        audioFiles.removeAll()
        fileChangeCancellables.removeAll()
        selectedFile = nil
        markReadyForNextExport()
    }
    
    func addFiles(_ files: [AudioFile]) {
        guard canModifyQueue, files.isEmpty == false else { return }
        observe(files)
        audioFiles.append(contentsOf: files)
        if selectedFile == nil {
            selectedFile = files.first
        }
        markReadyForNextExport()
    }
    
    func remove(_ file: AudioFile) {
        guard canModifyQueue else { return }
        audioFiles.removeAll { $0 == file }
        stopObserving(file)
        if selectedFile == file {
            selectedFile = audioFiles.first
        }
        markReadyForNextExport()
    }
    
    func remove(atOffsets offsets: IndexSet) {
        guard canModifyQueue,
              offsets.allSatisfy(audioFiles.indices.contains(_:)) else { return }
        let removedFiles = offsets.map { audioFiles[$0] }
        audioFiles.remove(atOffsets: offsets)
        removedFiles.forEach(stopObserving(_:))
        if let selected = selectedFile, audioFiles.contains(where: { $0 == selected }) == false {
            selectedFile = audioFiles.first
        }
        markReadyForNextExport()
    }
    
    func rename(_ file: AudioFile, to newName: String) {
        guard canModifyQueue else { return }
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
        guard processingState.canStartNewExport, exportTask == nil else { return }

        let preview = exportPreview
        guard preview.canExport, let exportJob = preview.exportJob else {
            if let message = preview.validation.message {
                processingState = .failed(message: message)
            }
            return
        }
        guard exportJob.outputFormat.accepts(outputURL) else {
            processingState = .failed(
                message: "L’estensione scelta non è compatibile con il formato di esportazione."
            )
            return
        }
        
        lastCompletedOutputURL = nil
        processingState = .running(progress: 0)
        let exportID = UUID()
        let inputFiles = audioFiles
        let fileURLs = inputFiles.map(\.url)
        let processor = self.processor
        activeExportID = exportID
        activeExportFiles = inputFiles
        notifier.prepareForExportNotifications()
        refreshNotificationPermission()
        
        exportTask = Task { [weak self] in
            guard let self else { return }
            guard Task.isCancelled == false else {
                self.finishExport(
                    id: exportID,
                    outputURL: outputURL,
                    result: .failure(.cancelled)
                )
                return
            }
            let outputHasSecurityScope = outputURL.startAccessingSecurityScopedResource()
            defer {
                if outputHasSecurityScope {
                    outputURL.stopAccessingSecurityScopedResource()
                }
            }

            let result = await processor.process(
                fileURLs: fileURLs,
                outputURL: outputURL,
                job: exportJob,
                estimatedTotalDuration: preview.totalDuration,
                progressCallback: { @MainActor [weak self] progress in
                    guard let self, self.activeExportID == exportID else { return }
                    self.updateProgress(progress)
                }
            )

            self.finishExport(
                id: exportID,
                outputURL: outputURL,
                result: result
            )
        }
    }

    func refreshNotificationPermission() {
        let notifier = self.notifier
        Task {
            notificationPermissionState = await notifier.notificationPermissionState()
        }
    }

    func requestNotificationPermission() {
        let notifier = self.notifier
        Task {
            notificationPermissionState = await notifier.requestNotificationPermission()
        }
    }

    func openNotificationSettings() {
        notifier.openNotificationSettings()
    }
    
    func cancelExport() {
        guard exportTask != nil else { return }
        Task { [weak self] in
            await self?.cancelExportAndWait()
        }
    }

    func cancelExportAndWait() async {
        guard let exportID = activeExportID,
              let task = exportTask else { return }

        task.cancel()
        await processor.cancel()
        await task.value

        // Fallback per processor di test o implementazioni alternative che non
        // restituiscano esplicitamente `.cancelled` dopo il proprio cleanup.
        if activeExportID == exportID {
            resetActiveExport()
            processingState = .idle
        }
    }
    
    private func updateProgress(_ progress: Double) {
        // Evita che aggiornamenti tardivi sovrascrivano stati terminali (.completed/.failed)
        guard case .running(let currentProgress) = processingState else { return }
        let clampedProgress = min(max(progress, 0), 1)
        guard abs(clampedProgress - currentProgress) >= 0.01 || clampedProgress >= 1 else { return }
        processingState = .running(progress: clampedProgress)
    }

    private func finishExport(
        id: UUID,
        outputURL: URL,
        result: Result<Void, AudioProcessor.ProcessError>
    ) {
        guard activeExportID == id else { return }
        defer { resetActiveExport() }

        switch result {
        case .success:
            lastCompletedOutputURL = outputURL
            processingState = .completed
            notifier.notifyExportFinished(outputURL: outputURL)
        case .failure(let error):
            if case .cancelled = error {
                processingState = .idle
            } else {
                processingState = .failed(message: error.localizedDescription)
            }
        }
    }

    private func resetActiveExport() {
        exportTask = nil
        activeExportID = nil
        activeExportFiles.removeAll()
    }
    
    private func markReadyForNextExport() {
        normalizeExportModeIfNeeded()
        if processingState.isBusy { return }
        lastCompletedOutputURL = nil
        if processingState != .idle {
            processingState = .idle
        }
    }

    private func normalizeExportModeIfNeeded() {
        guard compression.exportMode == .videoCompressed else { return }
        guard audioFiles.count == 1, audioFiles.first?.isVideo == true else {
            compression.exportMode = .audioOnly
            return
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
    var exportMode: ExportMode
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
                                            exportMode: .audioOnly,
                                            maxOutputSizeMB: nil)

    func preservingExportMode(_ exportMode: ExportMode) -> CompressionSettings {
        var copy = self
        copy.exportMode = exportMode
        return copy
    }
}

enum SampleRate: String, CaseIterable, Identifiable, Sendable {
    case s44100 = "44,1 kHz"
    case s48000 = "48 kHz"
    var id: String { rawValue }
}

enum Codec: String, CaseIterable, Identifiable, Sendable {
    case aac = "AAC"
    case alac = "ALAC"
    case opus = "Opus"
    case copy = "Copia diretta"
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

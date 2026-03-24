import Foundation

enum ExportValidation: Equatable, Sendable {
    case ready
    case invalidSelection(message: String)
    case loadingMetadata(message: String)
    case failedPreflight(message: String)

    var canExport: Bool {
        if case .ready = self { return true }
        return false
    }

    var message: String? {
        switch self {
        case .ready:
            return nil
        case .invalidSelection(let message), .loadingMetadata(let message), .failedPreflight(let message):
            return message
        }
    }
}

struct ExportPreview: Equatable, Sendable {
    let fileCount: Int
    let totalDuration: TimeInterval?
    let totalFileSize: Int64?
    let originalAverageBitrateKbps: Double?
    let resolvedBitrateKbps: Double?
    let estimatedOutputSizeMB: Double?
    let savingsRatio: Double?
    let exportJob: ExportJob?
    let validation: ExportValidation
    let pendingMetadataCount: Int
    let failedMetadataCount: Int
    let selectedCodec: Codec
    let effectiveCodec: Codec
    let sampleRate: SampleRate?
    let targetSizeMB: Double?
    let usesMergeReencodeFallback: Bool
    let requestedExportMode: ExportMode
    let effectiveExportMode: ExportMode
    let isVideoCompressionEligible: Bool
    let containsVideoFiles: Bool
    let videoCompressionSummary: String?
    let videoModeAvailabilityMessage: String?

    var canExport: Bool {
        validation.canExport && exportJob != nil
    }

    var isVideoModeActive: Bool {
        effectiveExportMode == .videoCompressed
    }

    var bitrateLabel: String {
        if isVideoModeActive {
            return "—"
        }
        if effectiveCodec == .copy {
            return "Originale"
        }
        guard let resolvedBitrateKbps else {
            return pendingMetadataCount > 0 ? "Analizzo..." : "—"
        }
        return "\(Int(resolvedBitrateKbps.rounded())) kbps"
    }

    var totalDurationLabel: String {
        guard let totalDuration else {
            return pendingMetadataCount > 0 ? "Analizzo..." : "—"
        }

        let minutes = Int(totalDuration) / 60
        let seconds = Int(totalDuration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var estimatedOutputLabel: String {
        if isVideoModeActive {
            return "—"
        }
        guard let estimatedOutputSizeMB else {
            return pendingMetadataCount > 0 ? "Analizzo..." : "—"
        }
        return String(format: "~%.2f MB", estimatedOutputSizeMB)
    }

    var savingsLabel: String {
        if isVideoModeActive {
            return "—"
        }
        guard let savingsRatio else {
            return pendingMetadataCount > 0 ? "Analizzo..." : "—"
        }
        return String(format: "~%.0f%%", savingsRatio * 100)
    }

    var targetSizeLabel: String? {
        guard isVideoModeActive == false else { return nil }
        guard let targetSizeMB else { return nil }
        return String(format: "%.0f MB", targetSizeMB)
    }

    var compressionSummary: String {
        if isVideoModeActive {
            return videoCompressionSummary ?? effectiveExportMode.rawValue
        }
        if effectiveCodec == .copy {
            return "Copia Stream"
        }

        var parts: [String] = [effectiveCodec.rawValue]
        if let targetSizeLabel {
            parts.append("Target \(targetSizeLabel)")
        }
        parts.append(bitrateLabel)
        if let sampleRate {
            parts.append(sampleRate.rawValue)
        }
        return parts.joined(separator: " · ")
    }

    var inspectorStatusMessage: String? {
        if let videoModeAvailabilityMessage {
            return videoModeAvailabilityMessage
        }
        if usesMergeReencodeFallback {
            return "Con piu file Copia Stream non e disponibile: l'export usera AAC per concatenare i contenuti."
        }
        return validation.message
    }

    static func make(files: [AudioFile], compression: CompressionSettings) -> ExportPreview {
        let pendingMetadataCount = files.filter { $0.metadataState.isLoading }.count
        let failedMetadataCount = files.filter { $0.metadataState.failureMessage != nil }.count
        let totalDuration = completeSum(files.map(\.duration), expectedCount: files.count)
        let totalFileSize = completeSum(files.map(\.fileSize), expectedCount: files.count)
        let originalAverageBitrateKbps = averageBitrate(totalBytes: totalFileSize, duration: totalDuration)
        let containsVideoFiles = files.contains { $0.isVideo }
        let isVideoCompressionEligible = files.count == 1 && files.first?.isVideo == true
        let requestedExportMode = compression.exportMode
        let effectiveExportMode = resolvedExportMode(
            requestedMode: requestedExportMode,
            isVideoCompressionEligible: isVideoCompressionEligible
        )
        let videoModeAvailabilityMessage = containsVideoFiles && isVideoCompressionEligible == false
            ? "Video compresso e disponibile solo con un singolo file video. Con piu file o sorgenti miste l'export resta solo audio."
            : nil
        let effectiveCodec = effectiveCodec(for: compression.codec, fileCount: files.count)
        let usesMergeReencodeFallback = compression.codec == .copy && effectiveCodec != .copy

        let validation: ExportValidation
        if files.isEmpty {
            validation = .invalidSelection(message: "Aggiungi almeno un file per esportare.")
        } else if effectiveExportMode == .videoCompressed {
            validation = .ready
        } else if compression.maxOutputSizeMB != nil && effectiveCodec != .copy && totalDuration == nil {
            if failedMetadataCount > 0 && pendingMetadataCount == 0 {
                validation = .failedPreflight(message: "Impossibile calcolare il target in MB: mancano i metadata di uno o piu file.")
            } else {
                validation = .loadingMetadata(message: "Attendi il completamento dell'analisi file per calcolare il target in MB.")
            }
        } else {
            validation = .ready
        }

        let resolvedBitrateKbps = effectiveExportMode == .audioOnly
            ? resolvedBitrate(
                compression: compression,
                totalDuration: totalDuration,
                effectiveCodec: effectiveCodec
            )
            : nil
        let exportJob = makeExportJob(
            compression: compression,
            resolvedBitrateKbps: resolvedBitrateKbps,
            effectiveCodec: effectiveCodec,
            effectiveExportMode: effectiveExportMode,
            validation: validation
        )
        let estimatedOutputSizeMB = effectiveExportMode == .audioOnly
            ? estimateOutputSizeMB(
                totalDuration: totalDuration,
                totalFileSize: totalFileSize,
                resolvedBitrateKbps: resolvedBitrateKbps,
                effectiveCodec: effectiveCodec
            )
            : nil
        let savingsRatio = effectiveExportMode == .audioOnly
            ? savingsRatio(totalFileSize: totalFileSize, estimatedOutputSizeMB: estimatedOutputSizeMB)
            : nil
        let videoCompressionSummary = effectiveExportMode == .videoCompressed
            ? VideoCompressionPreset.teamsLecture.summary
            : nil

        return ExportPreview(
            fileCount: files.count,
            totalDuration: totalDuration,
            totalFileSize: totalFileSize,
            originalAverageBitrateKbps: originalAverageBitrateKbps,
            resolvedBitrateKbps: resolvedBitrateKbps,
            estimatedOutputSizeMB: estimatedOutputSizeMB,
            savingsRatio: savingsRatio,
            exportJob: exportJob,
            validation: validation,
            pendingMetadataCount: pendingMetadataCount,
            failedMetadataCount: failedMetadataCount,
            selectedCodec: compression.codec,
            effectiveCodec: effectiveCodec,
            sampleRate: effectiveExportMode == .videoCompressed || effectiveCodec == .copy ? nil : compression.sampleRate,
            targetSizeMB: effectiveExportMode == .videoCompressed ? nil : compression.maxOutputSizeMB,
            usesMergeReencodeFallback: effectiveExportMode == .audioOnly ? usesMergeReencodeFallback : false,
            requestedExportMode: requestedExportMode,
            effectiveExportMode: effectiveExportMode,
            isVideoCompressionEligible: isVideoCompressionEligible,
            containsVideoFiles: containsVideoFiles,
            videoCompressionSummary: videoCompressionSummary,
            videoModeAvailabilityMessage: videoModeAvailabilityMessage
        )
    }

    private static func resolvedExportMode(
        requestedMode: ExportMode,
        isVideoCompressionEligible: Bool
    ) -> ExportMode {
        if requestedMode == .videoCompressed && isVideoCompressionEligible {
            return .videoCompressed
        }
        return .audioOnly
    }

    private static func effectiveCodec(for selectedCodec: Codec, fileCount: Int) -> Codec {
        if selectedCodec == .copy && fileCount > 1 {
            return .aac
        }
        return selectedCodec
    }

    private static func resolvedBitrate(
        compression: CompressionSettings,
        totalDuration: TimeInterval?,
        effectiveCodec: Codec
    ) -> Double? {
        guard effectiveCodec != .copy else { return nil }

        if let targetSizeMB = compression.maxOutputSizeMB,
           let totalDuration,
           totalDuration > 0 {
            let bitsPerSecond = (targetSizeMB * 1_000_000 * 8) / totalDuration
            return max(32, bitsPerSecond / 1_000)
        }

        return compression.baseBitrateKbps
    }

    private static func makeExportJob(
        compression: CompressionSettings,
        resolvedBitrateKbps: Double?,
        effectiveCodec: Codec,
        effectiveExportMode: ExportMode,
        validation: ExportValidation
    ) -> ExportJob? {
        guard validation.canExport else { return nil }

        if effectiveExportMode == .videoCompressed {
            return .videoCompressed(.teamsLecture)
        }

        let codec: String
        switch effectiveCodec {
        case .aac:
            codec = "aac"
        case .alac:
            codec = "alac"
        case .opus:
            codec = "libopus"
        case .copy:
            codec = "copy"
        }

        let bitrate: String
        if let resolvedBitrateKbps {
            bitrate = "\(Int(resolvedBitrateKbps.rounded(.down)))k"
        } else {
            bitrate = ""
        }

        return .audio(AudioExportSettings(codec: codec, bitrate: bitrate, sampleRate: compression.ffmpegSampleRate))
    }

    private static func estimateOutputSizeMB(
        totalDuration: TimeInterval?,
        totalFileSize: Int64?,
        resolvedBitrateKbps: Double?,
        effectiveCodec: Codec
    ) -> Double? {
        if effectiveCodec == .copy {
            guard let totalFileSize else { return nil }
            return Double(totalFileSize) / 1_000_000
        }

        guard let totalDuration, let resolvedBitrateKbps else { return nil }
        let bytesPerSecond = (resolvedBitrateKbps * 1_000) / 8
        let totalBytes = bytesPerSecond * totalDuration
        return totalBytes / 1_000_000
    }

    private static func savingsRatio(totalFileSize: Int64?, estimatedOutputSizeMB: Double?) -> Double? {
        guard let totalFileSize, let estimatedOutputSizeMB else { return nil }
        let originalMB = Double(totalFileSize) / 1_000_000
        guard originalMB > 0 else { return nil }
        return max(0, 1 - (estimatedOutputSizeMB / originalMB))
    }

    private static func averageBitrate(totalBytes: Int64?, duration: TimeInterval?) -> Double? {
        guard let totalBytes, let duration, duration > 0 else { return nil }
        let bitsPerSecond = (Double(totalBytes) * 8) / duration
        return bitsPerSecond / 1_000
    }

    private static func completeSum(_ values: [TimeInterval?], expectedCount: Int) -> TimeInterval? {
        guard expectedCount > 0, values.count == expectedCount else { return nil }
        let unwrapped = values.compactMap { $0 }
        guard unwrapped.count == expectedCount else { return nil }
        return unwrapped.reduce(0, +)
    }

    private static func completeSum(_ values: [Int64?], expectedCount: Int) -> Int64? {
        guard expectedCount > 0, values.count == expectedCount else { return nil }
        let unwrapped = values.compactMap { $0 }
        guard unwrapped.count == expectedCount else { return nil }
        return unwrapped.reduce(0, +)
    }
}

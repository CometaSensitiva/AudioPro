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
    let outputFormat: ExportOutputFormat?
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
            return pendingMetadataCount > 0 ? "Analizzo…" : "—"
        }
        return "\(Int(resolvedBitrateKbps.rounded())) kbps"
    }

    var totalDurationLabel: String {
        guard let totalDuration else {
            return pendingMetadataCount > 0 ? "Analizzo…" : "—"
        }

        let minutes = Int(totalDuration) / 60
        let seconds = Int(totalDuration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var estimatedOutputLabel: String {
        guard let estimatedOutputSizeMB else {
            return pendingMetadataCount > 0 ? "Analizzo…" : "—"
        }
        return String(format: "≈%.2f MB", estimatedOutputSizeMB)
    }

    var savingsLabel: String {
        guard let savingsRatio else {
            return pendingMetadataCount > 0 ? "Analizzo…" : "—"
        }
        return String(format: "≈%.0f%%", savingsRatio * 100)
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
            return "Copia diretta"
        }

        var parts: [String] = [effectiveCodec.rawValue]
        if let targetSizeLabel {
            parts.append("Dimensione massima \(targetSizeLabel)")
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
            return "Con più file, la copia diretta non è disponibile: AudioPro userà AAC per unire i contenuti."
        }
        return validation.message
    }

    @MainActor
    static func make(files: [AudioFile], compression: CompressionSettings) -> ExportPreview {
        let pendingMetadataCount = files.filter { $0.metadataState.isLoading }.count
        let failedMetadataCount = files.filter { $0.metadataState.failureMessage != nil }.count
        let totalDuration = completeSum(files.map(\.duration), expectedCount: files.count)
        let totalFileSize = completeSum(files.map(\.fileSize), expectedCount: files.count)
        let originalAverageBitrateKbps = averageBitrate(totalBytes: totalFileSize, duration: totalDuration)
        let hasUnresolvedTrackMetadata = files.contains {
            $0.hasAudioTrack == nil || $0.hasVideoTrack == nil
        }
        let containsVideoFiles = files.contains { $0.hasVideoTrack == true }
        let containsInputWithoutAudio = files.contains { $0.hasAudioTrack == false }
        let isVideoCompressionEligible = files.count == 1
            && files.first?.hasVideoTrack == true
        let requestedExportMode = compression.exportMode
        let effectiveExportMode = resolvedExportMode(
            requestedMode: requestedExportMode,
            isVideoCompressionEligible: isVideoCompressionEligible
        )
        let videoModeAvailabilityMessage = containsVideoFiles && isVideoCompressionEligible == false
            ? "La modalità Video compresso è disponibile solo con un singolo file video. Con più file o sorgenti miste, l’esportazione resta solo audio."
            : nil
        let effectiveCodec = effectiveCodec(for: compression.codec, fileCount: files.count)
        let usesMergeReencodeFallback = compression.codec == .copy && effectiveCodec != .copy
        let outputFormat = resolvedOutputFormat(
            files: files,
            effectiveCodec: effectiveCodec,
            effectiveExportMode: effectiveExportMode
        )

        let validation: ExportValidation
        if files.isEmpty {
            validation = .invalidSelection(message: "Aggiungi almeno un file per esportare.")
        } else if hasUnresolvedTrackMetadata {
            if pendingMetadataCount > 0 {
                validation = .loadingMetadata(
                    message: "Attendi l’analisi delle tracce audio e video prima di esportare."
                )
            } else {
                validation = .failedPreflight(
                    message: "Impossibile verificare le tracce audio e video di uno o più file."
                )
            }
        } else if effectiveExportMode == .audioOnly, containsInputWithoutAudio {
            validation = .failedPreflight(
                message: "L’esportazione audio richiede una traccia audio in ogni file. Per un singolo video senza audio, scegli Video compresso."
            )
        } else if effectiveExportMode == .audioOnly,
                  effectiveCodec == .alac,
                  compression.maxOutputSizeMB != nil {
            validation = .failedPreflight(
                message: "La dimensione massima in MB non è disponibile con ALAC, perché utilizza una codifica senza perdita. Rimuovi il limite oppure scegli AAC o Opus."
            )
        } else if outputFormat == nil {
            validation = .failedPreflight(
                message: "Impossibile determinare un formato di file compatibile con Copia diretta. Scegli AAC, ALAC o Opus."
            )
        } else if effectiveExportMode == .videoCompressed {
            validation = .ready
        } else if compression.maxOutputSizeMB != nil,
                  supportsTargetSize(effectiveCodec),
                  totalDuration == nil {
            if failedMetadataCount > 0 && pendingMetadataCount == 0 {
                validation = .failedPreflight(message: "Impossibile calcolare la dimensione massima: mancano i metadati di uno o più file.")
            } else {
                validation = .loadingMetadata(message: "Attendi il completamento dell’analisi dei file per calcolare la dimensione massima.")
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
            outputFormat: outputFormat,
            validation: validation
        )
        let estimatedOutputSizeMB: Double?
        switch effectiveExportMode {
        case .audioOnly:
            estimatedOutputSizeMB = estimateOutputSizeMB(
                totalDuration: totalDuration,
                totalFileSize: totalFileSize,
                resolvedBitrateKbps: resolvedBitrateKbps,
                effectiveCodec: effectiveCodec
            )
        case .videoCompressed:
            estimatedOutputSizeMB = estimateVideoOutputSizeMB(totalDuration: totalDuration)
        }
        let savingsRatio = savingsRatio(totalFileSize: totalFileSize, estimatedOutputSizeMB: estimatedOutputSizeMB)
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
            outputFormat: outputFormat,
            validation: validation,
            pendingMetadataCount: pendingMetadataCount,
            failedMetadataCount: failedMetadataCount,
            selectedCodec: compression.codec,
            effectiveCodec: effectiveCodec,
            sampleRate: effectiveExportMode == .videoCompressed || effectiveCodec == .copy ? nil : compression.sampleRate,
            targetSizeMB: effectiveExportMode == .audioOnly && supportsTargetSize(effectiveCodec)
                ? compression.maxOutputSizeMB
                : nil,
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
        guard supportsTargetSize(effectiveCodec) else { return nil }

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
        outputFormat: ExportOutputFormat?,
        validation: ExportValidation
    ) -> ExportJob? {
        guard validation.canExport, let outputFormat else { return nil }

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

        return .audio(
            AudioExportSettings(
                codec: codec,
                bitrate: bitrate,
                sampleRate: compression.ffmpegSampleRate,
                outputFormat: outputFormat
            )
        )
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

        guard supportsTargetSize(effectiveCodec) else { return nil }

        guard let totalDuration, let resolvedBitrateKbps else { return nil }
        let bytesPerSecond = (resolvedBitrateKbps * 1_000) / 8
        let totalBytes = bytesPerSecond * totalDuration
        return totalBytes / 1_000_000
    }

    /// Stima per il video compresso: il preset usa bitrate video e audio fissi.
    private static func estimateVideoOutputSizeMB(totalDuration: TimeInterval?) -> Double? {
        guard let totalDuration,
              let videoBitrateKbps = VideoCompressionPreset.teamsLecture.videoBitrateKbps,
              let audioBitrateKbps = VideoCompressionPreset.teamsLecture.audioBitrateKbps else { return nil }
        let bytesPerSecond = ((videoBitrateKbps + audioBitrateKbps) * 1_000) / 8
        return (bytesPerSecond * totalDuration) / 1_000_000
    }

    private static func resolvedOutputFormat(
        files: [AudioFile],
        effectiveCodec: Codec,
        effectiveExportMode: ExportMode
    ) -> ExportOutputFormat? {
        if effectiveExportMode == .videoCompressed {
            return .mp4
        }

        switch effectiveCodec {
        case .aac, .alac:
            return .m4a
        case .opus:
            return .opus
        case .copy:
            guard files.count == 1,
                  let fileExtension = files.first?.url.pathExtension.lowercased(),
                  isSafeFileExtension(fileExtension) else { return nil }
            return .source(fileExtension: fileExtension)
        }
    }

    private static func supportsTargetSize(_ codec: Codec) -> Bool {
        codec == .aac || codec == .opus
    }

    private static func isSafeFileExtension(_ fileExtension: String) -> Bool {
        guard fileExtension.isEmpty == false, fileExtension.count <= 16 else { return false }
        return fileExtension.unicodeScalars.allSatisfy(CharacterSet.alphanumerics.contains(_:))
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

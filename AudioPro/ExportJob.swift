import Foundation

nonisolated enum ExportOutputFormat: Sendable, Equatable {
    case m4a
    case opus
    case mp4
    case source(fileExtension: String)

    var fileExtension: String {
        switch self {
        case .m4a:
            return "m4a"
        case .opus:
            return "opus"
        case .mp4:
            return "mp4"
        case .source(let fileExtension):
            return fileExtension.lowercased()
        }
    }

    func accepts(_ url: URL) -> Bool {
        url.pathExtension.caseInsensitiveCompare(fileExtension) == .orderedSame
    }
}

nonisolated enum ExportMode: String, CaseIterable, Identifiable, Sendable {
    case audioOnly = "Solo audio"
    case videoCompressed = "Video compresso"

    var id: String { rawValue }
}

nonisolated struct AudioExportSettings: Sendable, Equatable {
    let codec: String
    let bitrate: String
    let sampleRate: String
    let outputFormat: ExportOutputFormat
}

nonisolated struct VideoCompressionPreset: Sendable, Equatable {
    let videoCodec: String
    let videoBitrate: String
    let videoTag: String
    let videoFilter: String
    let audioCodec: String
    let audioBitrate: String
    let outputFormat: ExportOutputFormat

    static let teamsLecture = VideoCompressionPreset(
        videoCodec: "hevc_videotoolbox",
        videoBitrate: "1500k",
        videoTag: "hvc1",
        videoFilter: "scale=1920:-2,fps=30",
        audioCodec: "aac",
        audioBitrate: "128k",
        outputFormat: .mp4
    )

    /// Bitrate video in kbps derivato da `videoBitrate` (es. "1500k"):
    /// il preset è fisso, quindi la stima di output è deterministica.
    var videoBitrateKbps: Double? {
        Self.parseKbps(videoBitrate)
    }

    var audioBitrateKbps: Double? {
        Self.parseKbps(audioBitrate)
    }

    var summary: String {
        "HEVC 1500 kbps · 1080p · 30 fps · AAC 128 kbps"
    }

    var inspectorMessage: String {
        "Profilo video fisso: codifica HEVC con accelerazione hardware a 1080p e 30 fps, bitrate video di 1500 kbps e audio AAC a 128 kbps."
    }

    private static func parseKbps(_ value: String) -> Double? {
        guard value.hasSuffix("k"),
              let parsed = Double(value.dropLast()) else { return nil }
        return parsed
    }
}

nonisolated enum ExportJob: Sendable, Equatable {
    case audio(AudioExportSettings)
    case videoCompressed(VideoCompressionPreset)

    var outputFormat: ExportOutputFormat {
        switch self {
        case .audio(let settings):
            return settings.outputFormat
        case .videoCompressed(let preset):
            return preset.outputFormat
        }
    }
}

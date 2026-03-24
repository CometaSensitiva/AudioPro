import Foundation

enum ExportMode: String, CaseIterable, Identifiable, Sendable {
    case audioOnly = "Solo audio"
    case videoCompressed = "Video compresso"

    var id: String { rawValue }
}

struct AudioExportSettings: Sendable, Equatable {
    let codec: String
    let bitrate: String
    let sampleRate: String
}

struct VideoCompressionPreset: Sendable, Equatable {
    let videoCodec: String
    let videoBitrate: String
    let videoTag: String
    let videoFilter: String
    let audioCodec: String

    static let teamsLecture = VideoCompressionPreset(
        videoCodec: "hevc_videotoolbox",
        videoBitrate: "1500k",
        videoTag: "hvc1",
        videoFilter: "scale=1920:-2,fps=30",
        audioCodec: "copy"
    )

    var summary: String {
        "HEVC 1500 kbps · 1080p · 30 fps · Audio copy"
    }

    var inspectorMessage: String {
        "Preset fisso: HEVC hardware 1500 kbps, tag hvc1, filtro scale=1920:-2,fps=30, audio copiato."
    }
}

enum ExportJob: Sendable, Equatable {
    case audio(AudioExportSettings)
    case videoCompressed(VideoCompressionPreset)
}

import Foundation

enum FFmpegCommandBuilder {
    enum BuilderError: LocalizedError, Equatable {
        case videoCompressionRequiresSingleVideo

        var errorDescription: String? {
            switch self {
            case .videoCompressionRequiresSingleVideo:
                return "La compressione video richiede un singolo file video in input."
            }
        }
    }

    nonisolated static func makeArguments(fileURLs: [URL], outputURL: URL, job: ExportJob) throws -> [String] {
        switch job {
        case .audio(let settings):
            if fileURLs.count == 1, let fileURL = fileURLs.first {
                return makeSingleAudioArguments(fileURL: fileURL, outputURL: outputURL, settings: settings)
            }
            return makeMergedAudioArguments(fileURLs: fileURLs, outputURL: outputURL, settings: settings)
        case .videoCompressed(let preset):
            guard fileURLs.count == 1, let fileURL = fileURLs.first else {
                throw BuilderError.videoCompressionRequiresSingleVideo
            }
            return makeVideoCompressionArguments(fileURL: fileURL, outputURL: outputURL, preset: preset)
        }
    }

    private nonisolated static func makeSingleAudioArguments(
        fileURL: URL,
        outputURL: URL,
        settings: AudioExportSettings
    ) -> [String] {
        var arguments = [
            "-i", fileURL.path,
            "-vn",
        ]

        if settings.codec == "copy" {
            arguments.append(contentsOf: ["-c:a", "copy"])
        } else {
            arguments.append(contentsOf: [
                "-c:a", settings.codec,
                "-b:a", settings.bitrate,
                "-ar", settings.sampleRate,
            ])
        }

        arguments.append(contentsOf: [
            "-y",
            outputURL.path
        ])

        return arguments
    }

    private nonisolated static func makeMergedAudioArguments(
        fileURLs: [URL],
        outputURL: URL,
        settings: AudioExportSettings
    ) -> [String] {
        var arguments: [String] = []

        for url in fileURLs {
            arguments.append(contentsOf: ["-i", url.path])
        }

        let filterInputs = (0..<fileURLs.count).map { "[\($0):a]" }.joined()
        let filterComplex = "\(filterInputs)concat=n=\(fileURLs.count):v=0:a=1[outa]"

        arguments.append(contentsOf: [
            "-filter_complex", filterComplex,
            "-map", "[outa]",
            "-vn",
        ])

        let codec = settings.codec == "copy" ? "aac" : settings.codec
        arguments.append(contentsOf: [
            "-c:a", codec,
            "-b:a", settings.bitrate,
            "-ar", settings.sampleRate,
            "-y",
            outputURL.path
        ])

        return arguments
    }

    private nonisolated static func makeVideoCompressionArguments(
        fileURL: URL,
        outputURL: URL,
        preset: VideoCompressionPreset
    ) -> [String] {
        [
            "-i", fileURL.path,
            "-map", "0:v:0",
            "-map", "0:a?",
            "-c:v", preset.videoCodec,
            "-b:v", preset.videoBitrate,
            "-tag:v", preset.videoTag,
            "-vf", preset.videoFilter,
            "-c:a", preset.audioCodec,
            "-y",
            outputURL.path
        ]
    }
}

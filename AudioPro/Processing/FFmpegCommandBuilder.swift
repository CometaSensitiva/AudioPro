import Foundation

enum FFmpegCommandBuilder {
    enum BuilderError: LocalizedError, Equatable {
        case inputRequired
        case videoCompressionRequiresSingleVideo
        case outputFormatMismatch(expectedExtension: String, actualExtension: String)

        var errorDescription: String? {
            switch self {
            case .inputRequired:
                return "L’esportazione richiede almeno un file sorgente."
            case .videoCompressionRequiresSingleVideo:
                return "La compressione video richiede un solo file video sorgente."
            case .outputFormatMismatch(let expectedExtension, let actualExtension):
                let actual = actualExtension.isEmpty ? "nessuna estensione" : ".\(actualExtension)"
                return "Il formato selezionato richiede l’estensione .\(expectedExtension), ma il file di destinazione usa \(actual)."
            }
        }
    }

    nonisolated static func makeArguments(fileURLs: [URL], outputURL: URL, job: ExportJob) throws -> [String] {
        guard fileURLs.isEmpty == false else {
            throw BuilderError.inputRequired
        }
        guard job.outputFormat.accepts(outputURL) else {
            throw BuilderError.outputFormatMismatch(
                expectedExtension: job.outputFormat.fileExtension,
                actualExtension: outputURL.pathExtension
            )
        }

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
        var arguments = ["-nostdin"]
        arguments.append(contentsOf: localInputArguments(for: fileURL))
        arguments.append(contentsOf: [
            "-vn",
        ])

        if settings.codec == "copy" {
            arguments.append(contentsOf: ["-c:a", "copy"])
        } else {
            arguments.append(contentsOf: ["-c:a", settings.codec])
            appendAudioEncodingOptions(to: &arguments, settings: settings)
        }

        arguments.append(contentsOf: [
            "-n",
            outputURL.path
        ])

        return arguments
    }

    private nonisolated static func makeMergedAudioArguments(
        fileURLs: [URL],
        outputURL: URL,
        settings: AudioExportSettings
    ) -> [String] {
        var arguments: [String] = ["-nostdin"]

        for url in fileURLs {
            arguments.append(contentsOf: localInputArguments(for: url))
        }

        let filterInputs = (0..<fileURLs.count).map { "[\($0):a]" }.joined()
        let filterComplex = "\(filterInputs)concat=n=\(fileURLs.count):v=0:a=1[outa]"

        arguments.append(contentsOf: [
            "-filter_complex", filterComplex,
            "-map", "[outa]",
            "-vn",
        ])

        let codec = settings.codec == "copy" ? "aac" : settings.codec
        arguments.append(contentsOf: ["-c:a", codec])
        appendAudioEncodingOptions(to: &arguments, settings: settings, codecOverride: codec)
        arguments.append(contentsOf: ["-n", outputURL.path])

        return arguments
    }

    private nonisolated static func makeVideoCompressionArguments(
        fileURL: URL,
        outputURL: URL,
        preset: VideoCompressionPreset
    ) -> [String] {
        var arguments = ["-nostdin"]
        arguments.append(contentsOf: localInputArguments(for: fileURL))
        arguments.append(contentsOf: [
            "-map", "0:v:0",
            "-map", "0:a?",
            "-c:v", preset.videoCodec,
            "-b:v", preset.videoBitrate,
            "-tag:v", preset.videoTag,
            "-vf", preset.videoFilter,
            "-c:a", preset.audioCodec,
            "-b:a", preset.audioBitrate,
            "-n",
            outputURL.path
        ])
        return arguments
    }

    private nonisolated static func localInputArguments(for url: URL) -> [String] {
        ["-protocol_whitelist", "file", "-i", url.path]
    }

    private nonisolated static func appendAudioEncodingOptions(
        to arguments: inout [String],
        settings: AudioExportSettings,
        codecOverride: String? = nil
    ) {
        let codec = codecOverride ?? settings.codec
        if codec != "copy", codec != "alac", settings.bitrate.isEmpty == false {
            arguments.append(contentsOf: ["-b:a", settings.bitrate])
        }
        if codec != "copy", settings.sampleRate.isEmpty == false {
            arguments.append(contentsOf: ["-ar", settings.sampleRate])
        }
    }
}

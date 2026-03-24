// ============================================================================
// FILE 4: AudioProcessor.swift
// Logica di elaborazione con ffmpeg
// ============================================================================

import Foundation
import SwiftUI
import CryptoKit
import Security

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

final class AudioProcessor {
    private final class ManagedProcess: @unchecked Sendable {
        nonisolated let process: Process

        nonisolated init(_ process: Process) {
            self.process = process
        }
    }

    private actor ExecutionState {
        private var currentProcess: ManagedProcess?
        private var isCancelled = false

        func reset() {
            currentProcess = nil
            isCancelled = false
        }

        func attach(_ process: ManagedProcess) {
            guard isCancelled == false else {
                process.process.terminate()
                return
            }
            currentProcess = process
        }

        func clearCurrentProcess(_ process: ManagedProcess? = nil) {
            guard let process else {
                currentProcess = nil
                return
            }

            if currentProcess === process {
                currentProcess = nil
            }
        }

        func cancel() {
            isCancelled = true
            let process = currentProcess
            currentProcess = nil
            process?.process.terminate()
        }

        func cancellationRequested() -> Bool {
            isCancelled
        }
    }

    private actor VerificationCache {
        private var verifiedPaths: Set<String> = []

        func contains(_ path: String) -> Bool {
            verifiedPaths.contains(path)
        }

        func insert(_ path: String) {
            verifiedPaths.insert(path)
        }
    }

    private nonisolated static let allowedFFmpegSHA256ByVariant: [String: String] = [
        "x86_64": "26b3ff92f64950f16be16eed88fe29064c2df516efdfac66cb8fa9abed030bdf",
        "arm64": "3b586ff896c0339e8fd574c143aaccac23c80789341e22d4202f8013a133d3a4"
    ]
    private nonisolated static let verificationCache = VerificationCache()
    private nonisolated static let executionState = ExecutionState()
    #if arch(arm64)
    private nonisolated static let preferredHelperName = "ffmpeg-binary-arm64"
    private nonisolated static let fallbackHelperName = "ffmpeg-binary-x86_64"
    #else
    private nonisolated static let preferredHelperName = "ffmpeg-binary-x86_64"
    private nonisolated static let fallbackHelperName = "ffmpeg-binary-arm64"
    #endif
    private nonisolated static let helperDirectory = "Contents/Helpers"
    
    enum ProcessError: LocalizedError {
        case ffmpegNotFound
        case ffmpegNotExecutable
        case ffmpegIntegrityCheckFailed
        case ffmpegFailed(String)
        case unsupportedCommandConfiguration(String)
        case fileCreationFailed
        case cancelled
        
        var errorDescription: String? {
            switch self {
            case .ffmpegNotFound:
                return "ffmpeg non trovato nel bundle dell'app"
            case .ffmpegNotExecutable:
                return "Il binario ffmpeg nel bundle non è eseguibile"
            case .ffmpegIntegrityCheckFailed:
                return "Il binario ffmpeg nel bundle non supera il controllo di integrita"
            case .ffmpegFailed(let message):
                return "Errore ffmpeg: \(message)"
            case .unsupportedCommandConfiguration(let message):
                return message
            case .fileCreationFailed:
                return "Impossibile creare il file temporaneo"
            case .cancelled:
                return "Operazione annullata"
            }
        }
    }
    
    /// Callback per aggiornamenti di progresso
    typealias ProgressCallback = @MainActor @Sendable (Double) -> Void
    
    /// Cancella l'operazione in corso
    nonisolated func cancel() async {
        await Self.executionState.cancel()
    }
    
    /// Processa i file audio: compressione singola o merge multiplo
    nonisolated func process(
        fileURLs: [URL],
        outputURL: URL,
        job: ExportJob,
        estimatedTotalDuration: Double? = nil,
        progressCallback: ProgressCallback? = nil
    ) async -> Result<Void, ProcessError> {
        await Task.detached(priority: .userInitiated) { [self] in
            await Self.executionState.reset()

            let ffmpegPath: String
            switch await getFFmpegPath() {
            case .success(let path):
                ffmpegPath = path
            case .failure(let error):
                return .failure(error)
            }

            let arguments: [String]
            do {
                arguments = try FFmpegCommandBuilder.makeArguments(
                    fileURLs: fileURLs,
                    outputURL: outputURL,
                    job: job
                )
            } catch let error as FFmpegCommandBuilder.BuilderError {
                return .failure(.unsupportedCommandConfiguration(error.localizedDescription))
            } catch {
                return .failure(.unsupportedCommandConfiguration(error.localizedDescription))
            }

            return await runFFmpeg(
                path: ffmpegPath,
                arguments: arguments,
                inputCount: fileURLs.count,
                estimatedTotalDuration: estimatedTotalDuration ?? 0,
                progressCallback: progressCallback
            )
        }.value
    }
    
    // MARK: - Path di ffmpeg
    
    /// Recupera il path di ffmpeg dal bundle
    private nonisolated func getFFmpegPath() async -> Result<String, ProcessError> {
        let candidatePaths = [
            Bundle.main.bundleURL.appendingPathComponent(Self.helperDirectory).appendingPathComponent(Self.preferredHelperName).path,
            Bundle.main.bundleURL.appendingPathComponent(Self.helperDirectory).appendingPathComponent(Self.fallbackHelperName).path,
            Bundle.main.resourceURL?.appendingPathComponent("ffmpeg-binary").path
        ].compactMap { $0 }

        guard let path = candidatePaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            return .failure(.ffmpegNotFound)
        }

        guard FileManager.default.isExecutableFile(atPath: path) else {
            return .failure(.ffmpegNotExecutable)
        }

        guard await verifyFFmpegBinary(atPath: path) else {
            return .failure(.ffmpegIntegrityCheckFailed)
        }

        return .success(path)
    }

    private nonisolated func verifyFFmpegBinary(atPath path: String) async -> Bool {
        if await Self.verificationCache.contains(path) {
            return true
        }

        let isValid: Bool
        if isPackagedHelper(atPath: path) {
            isValid = verifySignedHelper(atPath: path)
        } else {
            isValid = verifyBinaryHash(atPath: path)
        }

        guard isValid else {
            return false
        }

        await Self.verificationCache.insert(path)
        return true
    }

    private nonisolated func isPackagedHelper(atPath path: String) -> Bool {
        let helperDirectory = URL(fileURLWithPath: Bundle.main.bundleURL.appendingPathComponent(Self.helperDirectory).path).resolvingSymlinksInPath().path
        let binaryDirectory = URL(fileURLWithPath: path).resolvingSymlinksInPath().deletingLastPathComponent().path
        return binaryDirectory == helperDirectory
    }

    private nonisolated func verifySignedHelper(atPath path: String) -> Bool {
        let url = URL(fileURLWithPath: path) as CFURL
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(url, SecCSFlags(), &staticCode)

        guard createStatus == errSecSuccess, let staticCode else {
            return false
        }

        let checkStatus = SecStaticCodeCheckValidity(staticCode, SecCSFlags(), nil)
        return checkStatus == errSecSuccess
    }

    private nonisolated func verifyBinaryHash(atPath path: String) -> Bool {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe) else {
            return false
        }
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()

        return Self.allowedFFmpegSHA256ByVariant.values.contains(hex)
    }
    
    // MARK: - Esecuzione ffmpeg
    
    /// Esegue ffmpeg con gli argomenti specificati
    private nonisolated func runFFmpeg(
        path: String,
        arguments: [String],
        inputCount: Int,
        estimatedTotalDuration: Double,
        progressCallback: ProgressCallback?
    ) async -> Result<Void, ProcessError> {
        let process = Process()
        let managedProcess = ManagedProcess(process)
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        // Cattura l'output di errore per il debugging e progresso
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = errorPipe
        
        // Wrapper thread-safe per le variabili mutabili condivise
        final class ProgressTracker: @unchecked Sendable {
            private let lock = NSLock()
            var outputData = Data()
            private var estimatedTotalDuration: Double
            private var parsedDurations: [Double] = []
            private let expectedInputCount: Int
            
            init(estimatedTotalDuration: Double, expectedInputCount: Int) {
                self.estimatedTotalDuration = estimatedTotalDuration
                self.expectedInputCount = expectedInputCount
            }
            
            func append(_ data: Data) {
                lock.lock()
                defer { lock.unlock() }
                outputData.append(data)
            }
            
            func addParsedDuration(_ duration: Double) {
                lock.lock()
                defer { lock.unlock() }
                guard duration > 0 else { return }
                if parsedDurations.count >= expectedInputCount { return }
                parsedDurations.append(duration)
            }
            
            func getTotalDuration() -> Double {
                lock.lock()
                defer { lock.unlock() }
                if parsedDurations.isEmpty {
                    return estimatedTotalDuration
                } else {
                    let parsedSum = parsedDurations.reduce(0, +)
                    return max(parsedSum, estimatedTotalDuration)
                }
            }
            
            func getOutputData() -> Data {
                lock.lock()
                defer { lock.unlock() }
                return outputData
            }
        }
        
        let tracker = ProgressTracker(estimatedTotalDuration: estimatedTotalDuration, expectedInputCount: inputCount)
        let durationRegex = try? NSRegularExpression(pattern: #"Duration: (\d{2}):(\d{2}):(\d{2}\.\d{2})"#)
        let timeRegex = try? NSRegularExpression(pattern: #"time=(\d{2}):(\d{2}):(\d{2}\.\d{2})"#)
        
        // Leggi output in background per tracciare progresso
        let outputHandle = errorPipe.fileHandleForReading
        outputHandle.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            guard data.isEmpty == false else { return }

            Task {
                guard await Self.executionState.cancellationRequested() == false else { return }

                tracker.append(data)

                guard
                    let output = String(data: data, encoding: .utf8),
                    let durationRegex,
                    let timeRegex
                else { return }

                let fullRange = NSRange(output.startIndex..., in: output)

                // Somma le durate di tutti gli input (Duration:)
                let durationMatches = durationRegex.matches(in: output, options: [], range: fullRange)
                durationMatches.forEach { match in
                    guard let range = Range(match.range, in: output) else { return }
                    let durationStr = String(output[range])
                    let seconds = self.parseDuration(from: durationStr)
                    tracker.addParsedDuration(seconds)
                }

                // Cerca il tempo corrente (time=) rispetto alla durata totale
                let totalDur = tracker.getTotalDuration()
                guard totalDur > 0 else { return }
                let timeMatches = timeRegex.matches(in: output, options: [], range: fullRange)
                for match in timeMatches {
                    guard let range = Range(match.range, in: output) else { continue }
                    let timeStr = String(output[range])
                    let currentTime = self.parseDuration(from: timeStr)
                    let progress = min(currentTime / totalDur, 1.0)
                    await progressCallback?(progress)
                }
            }
        }
        
        do {
            try process.run()
            await Self.executionState.attach(managedProcess)
            if await Self.executionState.cancellationRequested() {
                process.terminate()
            }
            process.waitUntilExit()
            
            // Ferma il reading handler
            outputHandle.readabilityHandler = nil
            await Self.executionState.clearCurrentProcess(managedProcess)
            
            // Controlla se cancellato
            if await Self.executionState.cancellationRequested() {
                return .failure(.cancelled)
            }
            
            // Leggi eventuali dati rimanenti
            let remainingData = outputHandle.readDataToEndOfFile()
            tracker.append(remainingData)
            let errorOutput = String(data: tracker.getOutputData(), encoding: .utf8) ?? ""
            
            if process.terminationStatus != 0 {
                return .failure(.ffmpegFailed(errorOutput))
            }
            
            // Assicura progresso al 100%
            await progressCallback?(1.0)
            
            return .success(())
        } catch {
            outputHandle.readabilityHandler = nil
            await Self.executionState.clearCurrentProcess(managedProcess)
            return .failure(.ffmpegFailed(error.localizedDescription))
        }
    }
    
    /// Parsa una stringa di durata da ffmpeg (HH:MM:SS.xx) in secondi
    private nonisolated func parseDuration(from string: String) -> Double {
        guard let timestamp = extractTimestamp(from: string) else {
            return 0
        }

        let components = timestamp.split(separator: ":")
        guard components.count == 3,
              let hours = Double(components[0]),
              let minutes = Double(components[1]),
              let seconds = Double(components[2]) else {
            return 0
        }

        return hours * 3600 + minutes * 60 + seconds
    }

    private nonisolated func extractTimestamp(from string: String) -> String? {
        let scalars = Array(string.unicodeScalars)
        guard scalars.count >= 11 else { return nil }

        for start in 0...(scalars.count - 11) {
            let candidate = String(String.UnicodeScalarView(scalars[start..<min(start + 11, scalars.count)]))
            guard candidate.count == 11 else { continue }
            if isTimestamp(candidate) {
                return candidate
            }
        }

        return nil
    }

    private nonisolated func isTimestamp(_ candidate: String) -> Bool {
        let chars = Array(candidate)
        guard chars.count == 11 else { return false }

        return chars[0].isNumber &&
            chars[1].isNumber &&
            chars[2] == ":" &&
            chars[3].isNumber &&
            chars[4].isNumber &&
            chars[5] == ":" &&
            chars[6].isNumber &&
            chars[7].isNumber &&
            chars[8] == "." &&
            chars[9].isNumber &&
            chars[10].isNumber
    }
}

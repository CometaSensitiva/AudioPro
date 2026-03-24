import Foundation

actor FFmpegProcessRunner {
    private final class TerminationObserver: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Int32, Never>?
        private var terminationStatus: Int32?

        func install(on process: Process) {
            process.terminationHandler = { [weak self] terminatedProcess in
                self?.finish(with: terminatedProcess.terminationStatus)
            }
        }

        func wait() async -> Int32 {
            await withCheckedContinuation { continuation in
                lock.lock()
                defer { lock.unlock() }

                if let terminationStatus {
                    continuation.resume(returning: terminationStatus)
                } else {
                    self.continuation = continuation
                }
            }
        }

        private func finish(with status: Int32) {
            lock.lock()
            let continuation = self.continuation
            if continuation == nil {
                terminationStatus = status
            } else {
                self.continuation = nil
            }
            lock.unlock()

            continuation?.resume(returning: status)
        }
    }

    private actor ProgressTracker {
        private var logTail = ProcessLogTail()
        private var estimatedTotalDuration: Double
        private var parsedDurations: [Double] = []
        private let expectedInputCount: Int

        init(estimatedTotalDuration: Double, expectedInputCount: Int) {
            self.estimatedTotalDuration = estimatedTotalDuration
            self.expectedInputCount = expectedInputCount
        }

        func append(_ data: Data) {
            logTail.append(data)
        }

        func addParsedDuration(_ duration: Double) {
            guard duration > 0 else { return }
            if parsedDurations.count >= expectedInputCount { return }
            parsedDurations.append(duration)
        }

        func totalDuration() -> Double {
            if parsedDurations.isEmpty {
                return estimatedTotalDuration
            }
            let parsedSum = parsedDurations.reduce(0, +)
            return max(parsedSum, estimatedTotalDuration)
        }

        func outputString() -> String {
            logTail.stringValue
        }
    }

    private var currentProcess: Process?
    private var isCancelled = false

    func cancel() {
        isCancelled = true
        currentProcess?.terminate()
        currentProcess = nil
    }

    func run(
        path: String,
        arguments: [String],
        inputCount: Int,
        estimatedTotalDuration: Double,
        progressCallback: ExportProgressCallback?
    ) async -> Result<Void, AudioProcessor.ProcessError> {
        isCancelled = false
        currentProcess = nil

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = errorPipe

        let tracker = ProgressTracker(
            estimatedTotalDuration: estimatedTotalDuration,
            expectedInputCount: inputCount
        )
        let terminationObserver = TerminationObserver()
        let durationRegex = try? NSRegularExpression(pattern: #"Duration: (\d{2}):(\d{2}):(\d{2}\.\d{2})"#)
        let timeRegex = try? NSRegularExpression(pattern: #"time=(\d{2}):(\d{2}):(\d{2}\.\d{2})"#)

        let outputHandle = errorPipe.fileHandleForReading
        outputHandle.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            guard data.isEmpty == false else { return }

            Task {
                await self.handleOutput(
                    data,
                    tracker: tracker,
                    durationRegex: durationRegex,
                    timeRegex: timeRegex,
                    progressCallback: progressCallback
                )
            }
        }

        do {
            terminationObserver.install(on: process)
            try process.run()
            currentProcess = process

            if isCancelled {
                process.terminate()
            }

            let terminationStatus = await terminationObserver.wait()

            outputHandle.readabilityHandler = nil
            process.terminationHandler = nil
            currentProcess = nil

            if isCancelled {
                return .failure(.cancelled)
            }

            await tracker.append(outputHandle.readDataToEndOfFile())
            let errorOutput = await tracker.outputString()

            if terminationStatus != 0 {
                return .failure(.ffmpegFailed(errorOutput))
            }

            await progressCallback?(1.0)
            return .success(())
        } catch {
            outputHandle.readabilityHandler = nil
            process.terminationHandler = nil
            currentProcess = nil
            return .failure(.ffmpegFailed(error.localizedDescription))
        }
    }

    private func handleOutput(
        _ data: Data,
        tracker: ProgressTracker,
        durationRegex: NSRegularExpression?,
        timeRegex: NSRegularExpression?,
        progressCallback: ExportProgressCallback?
    ) async {
        guard isCancelled == false else { return }

        await tracker.append(data)

        guard
            let output = String(data: data, encoding: .utf8),
            let durationRegex,
            let timeRegex
        else { return }

        let fullRange = NSRange(output.startIndex..., in: output)
        let durationMatches = durationRegex.matches(in: output, options: [], range: fullRange)
        for match in durationMatches {
            guard let range = Range(match.range, in: output) else { return }
            let durationStr = String(output[range])
            let seconds = Self.parseDuration(from: durationStr)
            await tracker.addParsedDuration(seconds)
        }

        let totalDuration = await tracker.totalDuration()
        guard totalDuration > 0 else { return }

        let timeMatches = timeRegex.matches(in: output, options: [], range: fullRange)
        for match in timeMatches {
            guard let range = Range(match.range, in: output) else { continue }
            let timeStr = String(output[range])
            let currentTime = Self.parseDuration(from: timeStr)
            let progress = min(currentTime / totalDuration, 1.0)
            await progressCallback?(progress)
        }
    }

    private nonisolated static func parseDuration(from string: String) -> Double {
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

    private nonisolated static func extractTimestamp(from string: String) -> String? {
        let scalars = Array(string.unicodeScalars)
        guard scalars.count >= 11 else { return nil }

        for start in 0...(scalars.count - 11) {
            let candidate = String(
                String.UnicodeScalarView(
                    scalars[start..<min(start + 11, scalars.count)]
                )
            )
            guard candidate.count == 11 else { continue }
            if isTimestamp(candidate) {
                return candidate
            }
        }

        return nil
    }

    private nonisolated static func isTimestamp(_ candidate: String) -> Bool {
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

import Foundation
import Darwin

actor FFmpegProcessRunner {
    private final class TerminationObserver: @unchecked Sendable {
        private let lock = NSLock()
        private var continuations: [CheckedContinuation<Int32, Never>] = []
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
                    continuations.append(continuation)
                }
            }
        }

        private func finish(with status: Int32) {
            lock.lock()
            guard terminationStatus == nil else {
                lock.unlock()
                return
            }
            terminationStatus = status
            let continuations = self.continuations
            self.continuations.removeAll()
            lock.unlock()

            continuations.forEach { $0.resume(returning: status) }
        }
    }

    private final class CompletionObserver: @unchecked Sendable {
        private let lock = NSLock()
        private var continuations: [CheckedContinuation<Void, Never>] = []
        private var isFinished = false

        func wait() async {
            await withCheckedContinuation { continuation in
                lock.lock()
                defer { lock.unlock() }

                if isFinished {
                    continuation.resume()
                } else {
                    continuations.append(continuation)
                }
            }
        }

        func finish() {
            lock.lock()
            guard isFinished == false else {
                lock.unlock()
                return
            }
            isFinished = true
            let continuations = self.continuations
            self.continuations.removeAll()
            lock.unlock()

            continuations.forEach { $0.resume() }
        }
    }

    private struct ActiveRun {
        let id: UUID
        let process: Process
        let completionObserver: CompletionObserver
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

    private var activeRun: ActiveRun?
    private var cancelledRunIDs: Set<UUID> = []
    private let terminationGracePeriod: Duration

    init(terminationGracePeriod: Duration = .seconds(2)) {
        self.terminationGracePeriod = terminationGracePeriod
    }

    func cancel() async {
        guard let run = activeRun else { return }
        cancelledRunIDs.insert(run.id)
        if run.process.isRunning {
            run.process.terminate()
        }

        let runID = run.id
        let processIdentifier = run.process.processIdentifier
        let gracePeriod = terminationGracePeriod
        let escalationTask = Task.detached { [weak self] in
            do {
                try await Task.sleep(for: gracePeriod)
            } catch {
                return
            }
            await self?.forceTerminateIfNeeded(
                runID: runID,
                processIdentifier: processIdentifier
            )
        }
        await run.completionObserver.wait()
        escalationTask.cancel()
    }

    func hasActiveProcess() -> Bool {
        activeRun != nil
    }

    func run(
        path: String,
        arguments: [String],
        inputCount: Int,
        estimatedTotalDuration: Double,
        progressCallback: ExportProgressCallback?
    ) async -> Result<Void, AudioProcessor.ProcessError> {
        guard Task.isCancelled == false else {
            return .failure(.cancelled)
        }
        guard activeRun == nil else {
            return .failure(.exportAlreadyRunning)
        }

        let runID = UUID()
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
        let completionObserver = CompletionObserver()
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
                    runID: runID,
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
            activeRun = ActiveRun(
                id: runID,
                process: process,
                completionObserver: completionObserver
            )

            let terminationStatus = await terminationObserver.wait()

            outputHandle.readabilityHandler = nil
            process.terminationHandler = nil

            if cancelledRunIDs.remove(runID) != nil {
                _ = outputHandle.readDataToEndOfFile()
                finishRun(runID, completionObserver: completionObserver)
                return .failure(.cancelled)
            }

            await tracker.append(outputHandle.readDataToEndOfFile())
            let errorOutput = await tracker.outputString()

            if cancelledRunIDs.remove(runID) != nil {
                finishRun(runID, completionObserver: completionObserver)
                return .failure(.cancelled)
            }

            if terminationStatus != 0 {
                finishRun(runID, completionObserver: completionObserver)
                return .failure(.ffmpegFailed(errorOutput))
            }

            await progressCallback?(1.0)
            if cancelledRunIDs.remove(runID) != nil {
                finishRun(runID, completionObserver: completionObserver)
                return .failure(.cancelled)
            }
            finishRun(runID, completionObserver: completionObserver)
            return .success(())
        } catch {
            outputHandle.readabilityHandler = nil
            process.terminationHandler = nil
            clearActiveRun(ifMatching: runID)
            cancelledRunIDs.remove(runID)
            completionObserver.finish()
            return .failure(.ffmpegFailed(error.localizedDescription))
        }
    }

    private func handleOutput(
        _ data: Data,
        runID: UUID,
        tracker: ProgressTracker,
        durationRegex: NSRegularExpression?,
        timeRegex: NSRegularExpression?,
        progressCallback: ExportProgressCallback?
    ) async {
        await tracker.append(data)

        guard activeRun?.id == runID,
              cancelledRunIDs.contains(runID) == false else { return }

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
            guard activeRun?.id == runID,
                  cancelledRunIDs.contains(runID) == false else { return }
            await progressCallback?(progress)
        }
    }

    private func clearActiveRun(ifMatching runID: UUID) {
        guard activeRun?.id == runID else { return }
        activeRun = nil
    }

    private func forceTerminateIfNeeded(runID: UUID, processIdentifier: pid_t) {
        guard let run = activeRun,
              run.id == runID,
              run.process.processIdentifier == processIdentifier,
              run.process.isRunning else {
            return
        }
        _ = Darwin.kill(processIdentifier, SIGKILL)
    }

    private func finishRun(_ runID: UUID, completionObserver: CompletionObserver) {
        clearActiveRun(ifMatching: runID)
        completionObserver.finish()
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

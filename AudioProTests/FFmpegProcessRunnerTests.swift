import XCTest
@testable import AudioPro

final class FFmpegProcessRunnerTests: XCTestCase {
    func testRunCompletesForFastSuccessfulProcess() async {
        let runner = FFmpegProcessRunner()

        let result = await runner.run(
            path: "/usr/bin/true",
            arguments: [],
            inputCount: 0,
            estimatedTotalDuration: 0,
            progressCallback: nil
        )

        switch result {
        case .success:
            break
        case .failure(let error):
            XCTFail("Expected success, got \(error.localizedDescription)")
        }
    }

    func testRunReturnsFailureForFastFailingProcess() async {
        let runner = FFmpegProcessRunner()

        let result = await runner.run(
            path: "/usr/bin/false",
            arguments: [],
            inputCount: 0,
            estimatedTotalDuration: 0,
            progressCallback: nil
        )

        switch result {
        case .success:
            XCTFail("Expected failure for /usr/bin/false")
        case .failure(let error):
            guard case .ffmpegFailed = error else {
                return XCTFail("Expected ffmpegFailed, got \(error)")
            }
        }
    }

    func testCancelWaitsForTerminationAndReturnsCancelled() async {
        let runner = FFmpegProcessRunner()
        let runTask = Task {
            await runner.run(
                path: "/bin/sleep",
                arguments: ["10"],
                inputCount: 0,
                estimatedTotalDuration: 0,
                progressCallback: nil
            )
        }

        let becameActive = await waitUntilActive(runner)
        XCTAssertTrue(becameActive)

        await runner.cancel()
        let result = await runTask.value

        guard case .failure(.cancelled) = result else {
            return XCTFail("Expected cancellation, got \(result)")
        }
        let remainsActive = await runner.hasActiveProcess()
        XCTAssertFalse(remainsActive)
    }

    func testRunnerCanStartAgainAfterCancellation() async {
        let runner = FFmpegProcessRunner()
        let firstTask = Task {
            await runner.run(
                path: "/bin/sleep",
                arguments: ["10"],
                inputCount: 0,
                estimatedTotalDuration: 0,
                progressCallback: nil
            )
        }

        let becameActive = await waitUntilActive(runner)
        XCTAssertTrue(becameActive)
        await runner.cancel()
        _ = await firstTask.value

        let secondResult = await runner.run(
            path: "/usr/bin/true",
            arguments: [],
            inputCount: 0,
            estimatedTotalDuration: 0,
            progressCallback: nil
        )

        guard case .success = secondResult else {
            return XCTFail("Expected the next run to succeed, got \(secondResult)")
        }
    }

    func testCancellationEscalatesWhenProcessIgnoresTermination() async throws {
        let runner = FFmpegProcessRunner(terminationGracePeriod: .milliseconds(50))
        let readyMarker = FileManager.default.temporaryDirectory.appendingPathComponent("AudioProIgnoreTerm-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: readyMarker) }
        let runTask = Task {
            await runner.run(
                path: "/bin/sh",
                arguments: [
                    "-c",
                    "trap '' TERM; /usr/bin/touch \(readyMarker.path); exec /bin/sleep 10",
                ],
                inputCount: 0,
                estimatedTotalDuration: 0,
                progressCallback: nil
            )
        }

        let helperIsReady = await waitUntilFileExists(readyMarker)
        XCTAssertTrue(helperIsReady)

        let start = ContinuousClock.now
        await runner.cancel()
        let elapsed = start.duration(to: .now)
        let result = await runTask.value

        guard case .failure(.cancelled) = result else {
            return XCTFail("Expected forced cancellation, got \(result)")
        }
        XCTAssertLessThan(elapsed, .seconds(1))
        let hasActiveProcess = await runner.hasActiveProcess()
        XCTAssertFalse(hasActiveProcess)
    }

    func testOverlappingRunIsRejectedWithoutReplacingActiveProcess() async {
        let runner = FFmpegProcessRunner()
        let firstTask = Task {
            await runner.run(
                path: "/bin/sleep",
                arguments: ["10"],
                inputCount: 0,
                estimatedTotalDuration: 0,
                progressCallback: nil
            )
        }

        let becameActive = await waitUntilActive(runner)
        XCTAssertTrue(becameActive)
        let overlappingResult = await runner.run(
            path: "/usr/bin/true",
            arguments: [],
            inputCount: 0,
            estimatedTotalDuration: 0,
            progressCallback: nil
        )

        guard case .failure(.exportAlreadyRunning) = overlappingResult else {
            await runner.cancel()
            _ = await firstTask.value
            return XCTFail("Expected exportAlreadyRunning, got \(overlappingResult)")
        }

        let firstStillActive = await runner.hasActiveProcess()
        XCTAssertTrue(firstStillActive)
        await runner.cancel()
        _ = await firstTask.value
    }

    func testCancelledTaskDoesNotLaunchAProcess() async {
        let runner = FFmpegProcessRunner()
        let gate = RunnerTestGate()
        let runTask = Task {
            await gate.waitUntilOpen()
            return await runner.run(
                path: "/bin/sleep",
                arguments: ["10"],
                inputCount: 0,
                estimatedTotalDuration: 0,
                progressCallback: nil
            )
        }

        runTask.cancel()
        await gate.open()
        let result = await runTask.value

        guard case .failure(.cancelled) = result else {
            return XCTFail("Expected pre-launch cancellation, got \(result)")
        }
        let hasActiveProcess = await runner.hasActiveProcess()
        XCTAssertFalse(hasActiveProcess)
    }

    private func waitUntilActive(_ runner: FFmpegProcessRunner) async -> Bool {
        for _ in 0..<1_000 {
            if await runner.hasActiveProcess() {
                return true
            }
            await Task.yield()
        }
        return false
    }

    private func waitUntilFileExists(_ url: URL) async -> Bool {
        for _ in 0..<1_000 {
            if FileManager.default.fileExists(atPath: url.path) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return false
    }
}

private actor RunnerTestGate {
    private var isOpen = false

    func waitUntilOpen() async {
        while isOpen == false {
            await Task.yield()
        }
    }

    func open() {
        isOpen = true
    }
}

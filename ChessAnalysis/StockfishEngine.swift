import Foundation
import UIKit

actor StockfishEngine {
    static let shared = StockfishEngine()

    private var isRunning = false
    private var configuredThreads: Int = 1
    private var configuredHash: Int = 1
    private var idleTask: Task<Void, Never>?
    private var isInLowPowerMode = true
    private let idleTimeoutSeconds: UInt64 = 3 // Enter low-power mode after 3 seconds

    func _sfCompileCheck() {
        sf_start()
        _ = sf_send("uci")
        _ = sf_read_line()
        sf_stop()
    }

    func start() async throws {
        if isRunning { return }
        sf_start()
        isRunning = true
        try await send("uci")
        _ = try await readUntil(prefix: "uciok")
        try await configureEngine()
    }

    func stop() async {
        idleTask?.cancel()
        idleTask = nil
        guard isRunning else { return }
        _ = sf_send("quit")
        sf_stop()
        isRunning = false
        isInLowPowerMode = true
        configuredThreads = 1
        configuredHash = 1
        print("[StockfishEngine] Fully stopped")
    }

    /// Reduce resource usage when not analyzing (keeps engine alive but minimal footprint)
    private func enterLowPowerMode() async {
        guard isRunning, !isInLowPowerMode else { return }
        // Reduce hash to 1MB and threads to 1 to minimize memory/CPU
        _ = sf_send("setoption name Hash value 1")
        _ = sf_send("setoption name Threads value 1")
        _ = sf_send("isready")
        // Wait briefly for engine to process
        try? await Task.sleep(nanoseconds: 100_000_000)
        _ = sf_read_line() // Consume readyok
        configuredHash = 1
        configuredThreads = 1
        isInLowPowerMode = true
        print("[StockfishEngine] Entered low-power mode (1MB hash, 1 thread)")
    }

    /// Call this when the user leaves the analysis view to immediately free resources
    func stopIfIdle() async {
        idleTask?.cancel()
        idleTask = nil
        guard isRunning else { return }
        await enterLowPowerMode()
    }

    private func scheduleIdleShutdown() {
        idleTask?.cancel()
        idleTask = nil
        let timeout = idleTimeoutSeconds
        idleTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: timeout * 1_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.enterLowPowerMode()
            } catch {
                // Task was cancelled, which is expected
            }
        }
    }

    func analyze(positionFEN: String, timeLimitMs: Int, depthCap: Int, multiPV: Int) async throws -> AnalysisLine {
        idleTask?.cancel()
        isInLowPowerMode = false
        try await start()
        try await configureEngine()
        try await send("ucinewgame")
        try await send("position fen \(positionFEN)")
        try await send("setoption name MultiPV value \(multiPV)")
        if timeLimitMs > 0 {
            try await send("go depth \(depthCap) movetime \(timeLimitMs)")
        } else {
            try await send("go depth \(depthCap)")
        }

        var bestMove = ""
        var bestEval = 0
        var bestPV = ""

        while true {
            let line = try await readLine()
            if line.hasPrefix("bestmove") {
                let parts = line.split(separator: " ")
                if parts.count >= 2 {
                    bestMove = String(parts[1])
                }
                break
            }
            if line.hasPrefix("info") {
                if let parsed = parseInfo(line: line) {
                    bestEval = parsed.evalCp
                    bestPV = parsed.pv
                }
            }
        }

        scheduleIdleShutdown()
        return AnalysisLine(pv: bestPV, evalCp: bestEval, bestMoveUci: bestMove)
    }

    func analyze(positionMoves: [String], timeLimitMs: Int, depthCap: Int, multiPV: Int) async throws -> AnalysisLine {
        idleTask?.cancel()
        isInLowPowerMode = false
        try await start()
        try await configureEngine()
        try await send("ucinewgame")
        if positionMoves.isEmpty {
            try await send("position startpos")
        } else {
            let moves = positionMoves.joined(separator: " ")
            try await send("position startpos moves \(moves)")
        }
        try await send("setoption name MultiPV value \(multiPV)")
        if timeLimitMs > 0 {
            try await send("go depth \(depthCap) movetime \(timeLimitMs)")
        } else {
            try await send("go depth \(depthCap)")
        }

        var bestMove = ""
        var bestEval = 0
        var bestPV = ""

        while true {
            let line = try await readLine()
            if line.hasPrefix("bestmove") {
                let parts = line.split(separator: " ")
                if parts.count >= 2 {
                    bestMove = String(parts[1])
                }
                break
            }
            if line.hasPrefix("info") {
                if let parsed = parseInfo(line: line) {
                    bestEval = parsed.evalCp
                    bestPV = parsed.pv
                }
            }
        }

        scheduleIdleShutdown()
        return AnalysisLine(pv: bestPV, evalCp: bestEval, bestMoveUci: bestMove)
    }

    func runSmokeTest(seconds: TimeInterval) async {
        do {
            try await start()
            try await send("uci")
            try await send("isready")
            let deadline = Date().addingTimeInterval(seconds)
            while Date() < deadline {
                if let line = readLineIfAvailable() {
                    print("SF:", line)
                }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            await stop()
        } catch {
            print("SF smoke test failed:", error)
        }
    }

    private func configureEngine() async throws {
        let settings = await effectiveSettings()
        // Always reconfigure if coming out of low-power mode or settings changed
        if settings.threads != configuredThreads {
            try await send("setoption name Threads value \(settings.threads)")
            configuredThreads = settings.threads
        }
        if settings.hash != configuredHash {
            try await send("setoption name Hash value \(settings.hash)")
            configuredHash = settings.hash
        }
        try await send("isready")
        _ = try await readUntil(prefix: "readyok")
    }

    private func effectiveSettings() async -> (threads: Int, hash: Int) {
        let processorCount = max(2, ProcessInfo.processInfo.activeProcessorCount / 2)
        let baseThreads = min(4, processorCount)
        let baseHash = 96

        let (batteryLow, lowPowerEnabled) = await MainActor.run {
            UIDevice.current.isBatteryMonitoringEnabled = true
            let level = UIDevice.current.batteryLevel
            let unplugged = UIDevice.current.batteryState == .unplugged
            let batteryLow = level >= 0 && level < 0.2 && unplugged
            let batteryCritical = level >= 0 && level < 0.10 && unplugged
            let overrideActive = UserDefaults.standard.bool(forKey: "analysis.lowPower.override")
            let lowPowerEnabled = overrideActive
                ? UserDefaults.standard.bool(forKey: "analysis.lowPower")
                : batteryCritical
            return (batteryLow, lowPowerEnabled)
        }
        let thermalState = ProcessInfo.processInfo.thermalState
        if lowPowerEnabled {
            return (threads: max(1, baseThreads - 2), hash: 48)
        }
        if thermalState == .serious || thermalState == .critical || batteryLow {
            return (threads: max(1, baseThreads - 2), hash: 64)
        }
        return (threads: baseThreads, hash: baseHash)
    }

    private func send(_ command: String) async throws {
        let success = command.withCString { cString in
            sf_send(cString)
        }
        if !success {
            throw StockfishError.notRunning
        }
    }

    private func readUntil(prefix: String, timeoutSeconds: Double = 30) async throws -> String {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            let line = try await readLine(timeoutSeconds: timeoutSeconds)
            if line.hasPrefix(prefix) { return line }
        }
        throw StockfishError.timeout
    }

    private func readLine(timeoutSeconds: Double = 30) async throws -> String {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var attemptCount = 0
        let maxAttempts = Int(timeoutSeconds * 100) // 10ms per attempt

        while attemptCount < maxAttempts {
            try Task.checkCancellation()

            if let linePtr = sf_read_line() {
                return String(cString: linePtr).trimmingCharacters(in: .whitespacesAndNewlines)
            }

            if Date() >= deadline {
                throw StockfishError.timeout
            }

            try await Task.sleep(nanoseconds: 10_000_000)
            attemptCount += 1
        }
        throw StockfishError.timeout
    }

    private func readLineIfAvailable() -> String? {
        guard let linePtr = sf_read_line() else { return nil }
        return String(cString: linePtr).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseInfo(line: String) -> (evalCp: Int, pv: String)? {
        let tokens = line.split(separator: " ")
        guard let scoreIndex = tokens.firstIndex(of: "score") else { return nil }
        guard tokens.count > scoreIndex + 2 else { return nil }
        let scoreType = tokens[scoreIndex + 1]
        let scoreValue = Int(tokens[scoreIndex + 2]) ?? 0
        let evalCp: Int
        if scoreType == "cp" {
            evalCp = scoreValue
        } else if scoreType == "mate" {
            let base = 100000
            evalCp = scoreValue >= 0 ? base + scoreValue : -base + scoreValue
        } else {
            evalCp = scoreValue
        }

        if let pvIndex = tokens.firstIndex(of: "pv") {
            let pvTokens = tokens[(pvIndex + 1)...]
            return (evalCp, pvTokens.joined(separator: " "))
        }
        return (evalCp, "")
    }
}

enum StockfishError: LocalizedError {
    case notRunning
    case timeout
    case engineCrashed

    var errorDescription: String? {
        switch self {
        case .notRunning:
            return "Chess engine is not running."
        case .timeout:
            return "Chess engine timed out. Please try again."
        case .engineCrashed:
            return "Chess engine stopped unexpectedly. Please restart analysis."
        }
    }
}

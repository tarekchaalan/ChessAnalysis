import Foundation
import UIKit

actor AnalysisQueue {
    static let shared = AnalysisQueue()

    private enum State {
        case idle
        case processing
        case cancelling
    }

    private var currentTask: Task<Void, Never>?
    private var queue: [@Sendable () async throws -> Void] = []
    private var state: State = .idle
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    func enqueue(_ operation: @escaping @Sendable () async throws -> Void) {
        queue.append(operation)
        startIfNeeded()
    }

    func cancel() {
        guard state == .processing else {
            // Already idle or cancelling
            queue.removeAll()
            return
        }
        state = .cancelling
        currentTask?.cancel()
        queue.removeAll()
        // State will be set to idle when processQueue exits
    }

    var queueCount: Int {
        queue.count
    }

    var isIdle: Bool {
        state == .idle
    }

    private func startIfNeeded() {
        guard state == .idle else { return }
        state = .processing
        beginBackgroundTask()
        currentTask = Task {
            await self.processQueue()
        }
    }

    private func processQueue() async {
        while state == .processing && !queue.isEmpty {
            let operation = queue.removeFirst()
            do {
                try Task.checkCancellation()
                try await operation()
            } catch is CancellationError {
                // Cancelled, exit loop
                break
            } catch {
                // Operation failed, continue with next
                continue
            }
        }
        // Clean up
        state = .idle
        currentTask = nil
        endBackgroundTask()
    }

    private func beginBackgroundTask() {
        guard backgroundTask == .invalid else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let taskId = UIApplication.shared.beginBackgroundTask(withName: "AnalysisQueue") {
                Task { await self.cancel() }
            }
            await self.setBackgroundTask(taskId)
        }
    }

    private func setBackgroundTask(_ id: UIBackgroundTaskIdentifier) {
        backgroundTask = id
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        let taskId = backgroundTask
        backgroundTask = .invalid
        Task { @MainActor in
            UIApplication.shared.endBackgroundTask(taskId)
        }
    }
}

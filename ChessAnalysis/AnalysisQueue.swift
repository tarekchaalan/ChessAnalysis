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
    private var isBackgroundTaskPending = false  // Prevents race condition in beginBackgroundTask

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
        // Check both the actual task AND the pending flag to prevent race condition
        guard backgroundTask == .invalid && !isBackgroundTaskPending else { return }
        isBackgroundTaskPending = true  // Set immediately to prevent duplicate requests

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
        isBackgroundTaskPending = false  // Clear pending flag once we have the actual task
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else {
            isBackgroundTaskPending = false  // Clear pending flag if we're ending without a task
            return
        }
        let taskId = backgroundTask
        backgroundTask = .invalid
        isBackgroundTaskPending = false
        Task { @MainActor in
            UIApplication.shared.endBackgroundTask(taskId)
        }
    }
}

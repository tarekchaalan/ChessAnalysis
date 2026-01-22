import Foundation
import UIKit

actor AnalysisQueue {
    static let shared = AnalysisQueue()
    private var currentTask: Task<Void, Error>?
    private var queue: [@Sendable () async throws -> Void] = []
    private var isProcessing = false
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    func enqueue(_ operation: @escaping @Sendable () async throws -> Void) {
        queue.append(operation)
        startIfNeeded()
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        queue.removeAll()
        isProcessing = false
        endBackgroundTask()
    }

    private func startIfNeeded() {
        guard !isProcessing else { return }
        isProcessing = true
        beginBackgroundTask()
        currentTask = Task { [weak self] in
            await self?.processQueue()
        }
    }

    private func processQueue() async {
        while !queue.isEmpty {
            let operation = queue.removeFirst()
            do {
                try await operation()
            } catch is CancellationError {
                break
            } catch {
                continue
            }
        }
        isProcessing = false
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

import Foundation
import Combine

@MainActor
final class AnalysisViewModel: ObservableObject {
    @Published var analyses: [MoveAnalysis] = []
    @Published var accuracy: Double = 0
    @Published var isAnalyzing = false
    @Published var errorMessage: String?
    @Published var isPartialAnalysis = false

    private let store = GameStore.shared
    private let analyzer = AnalysisService.shared
    private let queue = AnalysisQueue.shared
    private var currentAnalysisTask: Task<Void, Never>?

    // Incremental accuracy tracking for O(1) updates
    private var runningLossSum: Double = 0
    private var moveCount: Int = 0

    func loadAnalysis(gameId: UUID) async {
        do {
            analyses = try await store.fetchAnalysis(gameId: gameId)
            accuracy = computeAccuracy(from: analyses)
            isPartialAnalysis = false
        } catch {
            errorMessage = formatErrorMessage(error)
        }
    }

    func startAnalysis(pgn: String, gameId: UUID, coachLines: Bool) {
        isAnalyzing = true
        isPartialAnalysis = false
        errorMessage = nil

        // Reset incremental tracking
        runningLossSum = 0
        moveCount = 0

        currentAnalysisTask = Task { [weak self] in
            guard let self else { return }

            await self.queue.enqueue { [weak self] in
                guard let self else { return }
                do {
                    await MainActor.run {
                        self.analyses = []
                        self.analyses.reserveCapacity(100) // Pre-allocate for typical game
                    }

                    let stream = await self.analyzer.streamAnalysis(pgn: pgn, coachLines: coachLines)
                    for try await move in stream {
                        try Task.checkCancellation()
                        await MainActor.run {
                            self.analyses.append(move)
                            // Incremental accuracy update - O(1) instead of O(n)
                            self.runningLossSum += exp(-Double(move.loss) / 120.0)
                            self.moveCount += 1
                            self.accuracy = (self.runningLossSum / Double(self.moveCount) * 1000).rounded() / 10.0
                        }
                    }

                    let result = await MainActor.run {
                        AnalysisResult(moves: self.analyses, accuracyPercent: self.accuracy)
                    }
                    try await self.store.replaceAnalysis(gameId: gameId, analyses: result.moves)
                    await MainActor.run {
                        self.isAnalyzing = false
                        self.isPartialAnalysis = false
                    }
                } catch is CancellationError {
                    await MainActor.run {
                        self.isAnalyzing = false
                        // Keep partial results but mark as incomplete
                        if !self.analyses.isEmpty {
                            self.isPartialAnalysis = true
                        }
                    }
                } catch {
                    await MainActor.run {
                        self.errorMessage = self.formatErrorMessage(error)
                        self.isAnalyzing = false
                        // Mark as partial if we have some results
                        if !self.analyses.isEmpty {
                            self.isPartialAnalysis = true
                        }
                    }
                }
            }
        }
    }

    func cancel() {
        currentAnalysisTask?.cancel()
        currentAnalysisTask = nil
        Task { await queue.cancel() }
        isAnalyzing = false
    }

    /// Clear any partial analysis results
    func clearPartialResults() {
        analyses = []
        accuracy = 0
        isPartialAnalysis = false
        runningLossSum = 0
        moveCount = 0
    }

    private func computeAccuracy(from moves: [MoveAnalysis]) -> Double {
        guard !moves.isEmpty else { return 0 }
        let total = moves.reduce(0.0) { sum, move in
            sum + exp(-Double(move.loss) / 120.0)
        }
        let avg = total / Double(moves.count)
        return (avg * 1000).rounded() / 10.0
    }

    private func formatErrorMessage(_ error: Error) -> String {
        // Provide user-friendly error messages
        if let analysisError = error as? AnalysisService.AnalysisError {
            return analysisError.localizedDescription
        }
        if let stockfishError = error as? StockfishError {
            return stockfishError.localizedDescription
        }
        if let sanError = error as? SANError {
            return sanError.localizedDescription
        }

        let description = error.localizedDescription
        // Clean up common cryptic errors
        if description.contains("cancelled") || description.contains("cancel") {
            return "Analysis was cancelled."
        }

        return "Analysis failed: \(description)"
    }
}

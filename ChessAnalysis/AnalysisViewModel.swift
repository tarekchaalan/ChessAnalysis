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

    // Incremental accuracy tracking
    private var totalLoss: Int = 0
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
        totalLoss = 0
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
                            // Incremental accuracy update using Chess.com ACPL formula
                            self.totalLoss += move.loss
                            self.moveCount += 1
                            self.accuracy = Self.computeAccuracyFromACPL(
                                totalLoss: self.totalLoss,
                                moveCount: self.moveCount
                            )
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
        totalLoss = 0
        moveCount = 0
    }

    private func computeAccuracy(from moves: [MoveAnalysis]) -> Double {
        guard !moves.isEmpty else { return 0 }
        let totalLoss = moves.reduce(0) { $0 + $1.loss }
        return Self.computeAccuracyFromACPL(totalLoss: totalLoss, moveCount: moves.count)
    }

    /// Chess.com-style accuracy formula based on Average Centipawn Loss (ACPL)
    /// This formula is used consistently across AnalysisService, StatisticsService, and here
    private static func computeAccuracyFromACPL(totalLoss: Int, moveCount: Int) -> Double {
        guard moveCount > 0 else { return 0 }
        let acpl = Double(totalLoss) / Double(moveCount)
        // Chess.com accuracy formula: 103.1668 * exp(-0.04354 * ACPL) - 3.1669
        let accuracy = 103.1668 * exp(-0.04354 * acpl) - 3.1669
        return max(0, min(100, (accuracy * 10).rounded() / 10))
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

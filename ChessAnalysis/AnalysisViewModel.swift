import Foundation
import Combine

@MainActor
final class AnalysisViewModel: ObservableObject {
    @Published var analyses: [MoveAnalysis] = []
    @Published var accuracy: Double = 0
    @Published var isAnalyzing = false
    @Published var errorMessage: String?

    private let store = GameStore.shared
    private let analyzer = AnalysisService.shared
    private let queue = AnalysisQueue.shared

    func loadAnalysis(gameId: UUID) async {
        do {
            analyses = try await store.fetchAnalysis(gameId: gameId)
            accuracy = computeAccuracy(from: analyses)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startAnalysis(pgn: String, gameId: UUID, coachLines: Bool) {
        isAnalyzing = true
        Task {
            await queue.enqueue { [weak self] in
                guard let self else { return }
                do {
                    await MainActor.run {
                        self.analyses = []
                    }
                    let stream = await self.analyzer.streamAnalysis(pgn: pgn, coachLines: coachLines)
                    for try await move in stream {
                        await MainActor.run {
                            self.analyses.append(move)
                            self.accuracy = self.computeAccuracy(from: self.analyses)
                        }
                    }
                    let result = await MainActor.run {
                        AnalysisResult(moves: self.analyses, accuracyPercent: self.accuracy)
                    }
                    try await self.store.replaceAnalysis(gameId: gameId, analyses: result.moves)
                    await MainActor.run {
                        self.isAnalyzing = false
                    }
                } catch is CancellationError {
                    await MainActor.run {
                        self.isAnalyzing = false
                    }
                } catch {
                    await MainActor.run {
                        self.errorMessage = error.localizedDescription
                        self.isAnalyzing = false
                    }
                }
            }
        }
    }

    func cancel() {
        Task { await queue.cancel() }
        isAnalyzing = false
    }

    private func computeAccuracy(from moves: [MoveAnalysis]) -> Double {
        guard !moves.isEmpty else { return 0 }
        let total = moves.reduce(0.0) { sum, move in
            sum + exp(-Double(move.loss) / 120.0)
        }
        let avg = total / Double(moves.count)
        return (avg * 1000).rounded() / 10.0
    }
}

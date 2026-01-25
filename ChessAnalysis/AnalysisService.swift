import Foundation
import UIKit

actor AnalysisService {
    @MainActor static let shared = AnalysisService(store: GameStore.shared)

    private let store: GameStore
    nonisolated private let engine = StockfishEngine.shared

    init(store: GameStore) {
        self.store = store
    }

    func analyzeGame(
        pgn: String,
        gameId: UUID,
        coachLines: Bool,
        progress: ((Int, Int) -> Void)? = nil
    ) async throws -> AnalysisResult {
        let totalMoves = await MainActor.run {
            PGNParser.extractMoves(from: pgn).count
        }
        let total = max(totalMoves, 1)
        var collected: [MoveAnalysis] = []
        var completed = 0
        for try await move in streamAnalysis(pgn: pgn, coachLines: coachLines) {
            collected.append(move)
            completed += 1
            progress?(completed, total)
        }
        let accuracy = Self.computeAccuracy(moves: collected)
        try await store.replaceAnalysis(gameId: gameId, analyses: collected)
        progress?(total, total)
        return AnalysisResult(moves: collected, accuracyPercent: accuracy)
    }

    func streamAnalysis(pgn: String, coachLines: Bool) -> AsyncThrowingStream<MoveAnalysis, Error> {
        AsyncThrowingStream { continuation in
            let analysisTask = Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }
                do {
                    // Parse PGN off main thread for better performance
                    let (whiteRating, blackRating, parsedMoves) = try await Task.detached(priority: .userInitiated) {
                        // Some parsing helpers may be MainActor-isolated under Swift 6 strict concurrency;
                        // keep the heavy lifting off-main, but hop to MainActor for those helpers if required.
                        let (whiteHeader, blackHeader, parsedMoves) = try await MainActor.run {
                            let whiteHeader = PGNParser.extractHeader(from: pgn, key: "WhiteElo")
                            let blackHeader = PGNParser.extractHeader(from: pgn, key: "BlackElo")
                            let sanMoves = PGNParser.extractMoves(from: pgn)
                            let parsedMoves = try SANParser.parseMoves(pgnMoves: sanMoves)
                            return (whiteHeader, blackHeader, parsedMoves)
                        }
                        let whiteRating = AnalysisService.parseRating(from: whiteHeader)
                        let blackRating = AnalysisService.parseRating(from: blackHeader)
                        return (whiteRating, blackRating, parsedMoves)
                    }.value

                    let uciMoves = parsedMoves.map { Self.uciString($0.0) }

                    // Validate that uciMoves and parsedMoves have same length
                    guard uciMoves.count == parsedMoves.count else {
                        throw AnalysisError.moveParseMismatch
                    }

                    let depthCap = await self.effectiveDepthCap()
                    let timeLimitMs = 1000
                    let multiPV = coachLines ? 3 : 1

                    for (index, moveInfo) in parsedMoves.enumerated() {
                        try Task.checkCancellation()
                        let (move, beforePosition) = moveInfo

                        // Generate FEN for the position before the move
                        let beforeFen = await MainActor.run { beforePosition.fen() }

                        let afterPosition = await MainActor.run { MoveGenerator.apply(move: move, to: beforePosition) }

                        let beforeMoves = Array(uciMoves.prefix(index))
                        let afterMoves = Array(uciMoves.prefix(index + 1))
                        let mover: PieceColor = (index % 2 == 0) ? .white : .black
                        let afterSide: PieceColor = (mover == .white) ? .black : .white
                        let moverRating = mover == .white ? whiteRating : blackRating

                        let beforeAnalysis = try await self.engine.analyze(
                            positionMoves: beforeMoves,
                            timeLimitMs: timeLimitMs,
                            depthCap: depthCap,
                            multiPV: multiPV
                        )
                        let afterAnalysis = try await self.engine.analyze(
                            positionMoves: afterMoves,
                            timeLimitMs: timeLimitMs,
                            depthCap: depthCap,
                            multiPV: multiPV
                        )

                        let evalBefore = Self.normalizeEvalToWhite(beforeAnalysis.evalCp, sideToMove: mover)
                        let evalAfter = Self.normalizeEvalToWhite(afterAnalysis.evalCp, sideToMove: afterSide)
                        let loss = Self.computeLoss(evalBeforeWhite: evalBefore, evalAfterWhite: evalAfter, mover: mover)

                        let isCheckmate = await MainActor.run { MoveGenerator.isCheckmate(position: afterPosition) }

                        let classification = Self.classifyMove(
                            loss: loss,
                            evalBefore: evalBefore,
                            evalAfter: evalAfter,
                            bestMoveUci: beforeAnalysis.bestMoveUci,
                            playedMoveUci: Self.uciString(move),
                            mover: mover,
                            ply: index + 1,
                            rating: moverRating,
                            beforePosition: beforePosition,
                            afterPosition: afterPosition,
                            isCheckmate: isCheckmate
                        )

                        let analysis = MoveAnalysis(
                            ply: index + 1,
                            fen: beforeFen,  // Store actual FEN instead of "startpos"
                            playedUci: Self.uciString(move),
                            bestUci: beforeAnalysis.bestMoveUci,
                            evalBefore: evalBefore,
                            evalAfter: evalAfter,
                            loss: loss,
                            classification: classification,
                            pv: beforeAnalysis.pv
                        )
                        continuation.yield(analysis)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            // Handle cancellation properly
            continuation.onTermination = { @Sendable _ in
                analysisTask.cancel()
            }
        }
    }

    enum AnalysisError: LocalizedError {
        case moveParseMismatch

        var errorDescription: String? {
            switch self {
            case .moveParseMismatch:
                return "Failed to parse game moves correctly."
            }
        }
    }

    private func effectiveDepthCap() async -> Int {
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
            return 12
        }
        if thermalState == .serious || thermalState == .critical || batteryLow {
            return 14
        }
        return 20
    }

    private nonisolated static func normalizeEvalToWhite(_ evalCp: Int, sideToMove: PieceColor) -> Int {
        return sideToMove == .white ? evalCp : -evalCp
    }

    private nonisolated static func computeLoss(evalBeforeWhite: Int, evalAfterWhite: Int, mover: PieceColor) -> Int {
        if mover == .white {
            return max(0, evalBeforeWhite - evalAfterWhite)
        } else {
            return max(0, evalAfterWhite - evalBeforeWhite)
        }
    }

    private nonisolated static func classifyMove(
        loss: Int,
        evalBefore: Int,
        evalAfter: Int,
        bestMoveUci: String,
        playedMoveUci: String,
        mover: PieceColor,
        ply: Int,
        rating: Int,
        beforePosition: ChessPosition,
        afterPosition: ChessPosition,
        isCheckmate: Bool
    ) -> String {
        let isBestMove = playedMoveUci == bestMoveUci
        let mateBase = 100000

        // Check if this move delivers checkmate
        if isCheckmate {
            return isBestMove ? MoveClassification.best.rawValue : "Excellent"
        }

        // Calculate centipawn loss from mover's perspective
        let signedEvalBefore = mover == .white ? evalBefore : -evalBefore
        let signedEvalAfter = mover == .white ? evalAfter : -evalAfter
        let cpLoss = max(0, signedEvalBefore - signedEvalAfter)

        // Check for brilliant move: sacrifice that maintains/improves position
        if isBestMove && cpLoss <= 10 {
            let materialBefore = materialScore(position: beforePosition, color: mover)
            let materialAfter = materialScore(position: afterPosition, color: mover)
            let materialSacrifice = materialBefore - materialAfter
            // Brilliant: Sacrificed significant material but position is still good/better
            if materialSacrifice >= 2.5 && signedEvalAfter >= -50 {
                return MoveClassification.brilliant.rawValue
            }
        }

        // Check for great move: best move that significantly improves a difficult position
        // or finds the only good move in a critical situation
        if isBestMove && cpLoss <= 10 {
            // Great: Turned a losing/equal position into winning, or found only saving move
            let wasLosing = signedEvalBefore <= -100
            let nowWinning = signedEvalAfter >= 100
            let bigSwing = signedEvalAfter - signedEvalBefore >= 150
            if (wasLosing && nowWinning) || bigSwing {
                return MoveClassification.great.rawValue
            }
        }

        // Book move: early game moves with minimal loss
        if ply <= 12 && cpLoss <= 20 {
            return "Book"
        }

        // Best move: engine's top choice with minimal loss
        if isBestMove && cpLoss <= 10 {
            return MoveClassification.best.rawValue
        }

        // Mate-related best move
        if isBestMove && abs(evalAfter) >= mateBase {
            return MoveClassification.best.rawValue
        }

        // Classification based on centipawn loss thresholds
        if cpLoss <= 10 { return "Excellent" }
        if cpLoss <= 25 { return MoveClassification.good.rawValue }
        if cpLoss <= 50 { return MoveClassification.good.rawValue }
        if cpLoss <= 100 { return MoveClassification.inaccuracy.rawValue }
        if cpLoss <= 200 { return MoveClassification.mistake.rawValue }

        // Check for "Miss" - had a winning position but missed winning continuation
        if signedEvalBefore >= 200 && signedEvalAfter <= 50 {
            return "Miss"
        }

        return MoveClassification.blunder.rawValue
    }

    private nonisolated static func parseRating(from header: String?) -> Int {
        guard let header, let value = Int(header) else { return 1500 }
        return value
    }

    private nonisolated static func materialScore(position: ChessPosition, color: PieceColor) -> Double {
        position.board.compactMap { $0 }.reduce(0.0) { sum, piece in
            guard piece.color == color else { return sum }
            return sum + materialValue(piece.type)
        }
    }

    private nonisolated static func materialValue(_ type: PieceType) -> Double {
        switch type {
        case .pawn: return 1
        case .knight, .bishop: return 3
        case .rook: return 5
        case .queen: return 9
        case .king: return 0
        }
    }

    private nonisolated static func computeAccuracy(moves: [MoveAnalysis]) -> Double {
        guard !moves.isEmpty else { return 0 }
        // Calculate Average Centipawn Loss (ACPL)
        let totalLoss = moves.reduce(0) { $0 + $1.loss }
        let acpl = Double(totalLoss) / Double(moves.count)
        // Chess.com-style accuracy formula: accuracy = 103.1668 * exp(-0.04354 * ACPL) - 3.1669
        // Simplified and bounded version:
        let accuracy = 103.1668 * exp(-0.04354 * acpl) - 3.1669
        return max(0, min(100, (accuracy * 10).rounded() / 10))
    }

    private nonisolated static func uciString(_ move: ChessMove) -> String {
        func squareName(index: Int) -> String {
            let file = index % 8
            let rank = 8 - (index / 8)
            guard let scalar = UnicodeScalar(97 + file) else { return "a\(rank)" }
            let fileChar = String(scalar)
            return "\(fileChar)\(rank)"
        }
        var uci = "\(squareName(index: move.from))\(squareName(index: move.to))"
        if let promo = move.promotion {
            let suffix: String
            switch promo {
            case .queen: suffix = "q"
            case .rook: suffix = "r"
            case .bishop: suffix = "b"
            case .knight: suffix = "n"
            default: suffix = "q"
            }
            uci.append(suffix)
        }
        return uci
    }
}

//
//  StatisticsService.swift
//  ChessAnalysis
//

import Foundation

actor StatisticsService {
    static let shared = StatisticsService()

    // Cached DateFormatter for performance (DateFormatter is expensive to create)
    private static let gameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private func getStore() async -> GameStore {
        await MainActor.run {
            GameStore.shared
        }
    }

    /// Compute all statistics from remote games and analyzed games
    func computeStatistics(
        remoteGames: [RemoteGame],
        downloadedGames: [GameMetadata],
        username: String
    ) async -> AggregatedStatistics {
        let lowercaseUsername = username.lowercased()

        // Run independent computations in parallel
        async let overall = computeOverallStats(games: remoteGames, username: lowercaseUsername)
        async let byColor = computeColorStats(games: remoteGames, username: lowercaseUsername)
        async let byTimeControl = computeTimeControlStats(games: remoteGames, username: lowercaseUsername)
        async let ratingHistory = computeRatingHistory(games: remoteGames, username: lowercaseUsername)
        async let openings = computeOpeningStats(games: remoteGames, username: lowercaseUsername)
        async let moveQuality = computeMoveQualityStats(downloadedGames: downloadedGames, username: lowercaseUsername)
        async let accuracyTrend = computeAccuracyTrend(downloadedGames: downloadedGames, username: lowercaseUsername)
        async let opponents = computeOpponentStats(games: remoteGames, username: lowercaseUsername)
        async let terminations = computeTerminationStats(games: remoteGames, username: lowercaseUsername)

        return await AggregatedStatistics(
            overall: overall,
            byColor: byColor,
            byTimeControl: byTimeControl,
            ratingHistory: ratingHistory,
            openings: openings,
            moveQuality: moveQuality,
            accuracyTrend: accuracyTrend,
            opponents: opponents,
            terminations: terminations
        )
    }

    // MARK: - Overall Stats

    private func computeOverallStats(games: [RemoteGame], username: String) -> OverallStats {
        var wins = 0
        var losses = 0
        var draws = 0

        for game in games {
            let result = classifyResult(game: game, username: username)
            switch result {
            case .win: wins += 1
            case .loss: losses += 1
            case .draw: draws += 1
            case .unknown: break
            }
        }

        return OverallStats(totalGames: games.count, wins: wins, losses: losses, draws: draws)
    }

    // MARK: - Color Stats

    private func computeColorStats(games: [RemoteGame], username: String) -> ColorStats {
        var whiteWins = 0, whiteLosses = 0, whiteDraws = 0, whiteGames = 0
        var blackWins = 0, blackLosses = 0, blackDraws = 0, blackGames = 0

        for game in games {
            let playedAsWhite = game.whitePlayer.lowercased() == username
            let result = classifyResult(game: game, username: username)

            if playedAsWhite {
                whiteGames += 1
                switch result {
                case .win: whiteWins += 1
                case .loss: whiteLosses += 1
                case .draw: whiteDraws += 1
                case .unknown: break
                }
            } else {
                blackGames += 1
                switch result {
                case .win: blackWins += 1
                case .loss: blackLosses += 1
                case .draw: blackDraws += 1
                case .unknown: break
                }
            }
        }

        return ColorStats(
            asWhite: OverallStats(totalGames: whiteGames, wins: whiteWins, losses: whiteLosses, draws: whiteDraws),
            asBlack: OverallStats(totalGames: blackGames, wins: blackWins, losses: blackLosses, draws: blackDraws)
        )
    }

    // MARK: - Time Control Stats

    private func computeTimeControlStats(games: [RemoteGame], username: String) -> TimeControlStats {
        var bullet = (games: 0, wins: 0, losses: 0, draws: 0)
        var blitz = (games: 0, wins: 0, losses: 0, draws: 0)
        var rapid = (games: 0, wins: 0, losses: 0, draws: 0)
        var classical = (games: 0, wins: 0, losses: 0, draws: 0)

        for game in games {
            let result = classifyResult(game: game, username: username)
            let tc = game.timeClass.lowercased()

            var stats: (games: Int, wins: Int, losses: Int, draws: Int)
            switch tc {
            case "bullet": stats = bullet
            case "blitz": stats = blitz
            case "rapid": stats = rapid
            case "daily", "classical": stats = classical
            default: continue
            }

            stats.games += 1
            switch result {
            case .win: stats.wins += 1
            case .loss: stats.losses += 1
            case .draw: stats.draws += 1
            case .unknown: break
            }

            switch tc {
            case "bullet": bullet = stats
            case "blitz": blitz = stats
            case "rapid": rapid = stats
            case "daily", "classical": classical = stats
            default: break
            }
        }

        return TimeControlStats(
            bullet: OverallStats(totalGames: bullet.games, wins: bullet.wins, losses: bullet.losses, draws: bullet.draws),
            blitz: OverallStats(totalGames: blitz.games, wins: blitz.wins, losses: blitz.losses, draws: blitz.draws),
            rapid: OverallStats(totalGames: rapid.games, wins: rapid.wins, losses: rapid.losses, draws: rapid.draws),
            classical: OverallStats(totalGames: classical.games, wins: classical.wins, losses: classical.losses, draws: classical.draws)
        )
    }

    // MARK: - Rating History

    private func computeRatingHistory(games: [RemoteGame], username: String) async -> [RatingDataPoint] {
        // Sort games by date (oldest first)
        let sortedGames = games.sorted { ($0.endTime ?? .distantPast) < ($1.endTime ?? .distantPast) }

        // Collect raw data first
        var rawData: [(date: Date, rating: Int, timeClass: String)] = []
        for game in sortedGames {
            guard let date = game.endTime else { continue }
            let playedAsWhite = game.whitePlayer.lowercased() == username
            if let rating = playedAsWhite ? game.whiteElo : game.blackElo {
                rawData.append((date, rating, game.timeClass))
            }
        }

        // Capture as immutable before passing to MainActor
        let finalRawData = rawData
        return finalRawData.map { RatingDataPoint(date: $0.date, rating: $0.rating, timeClass: $0.timeClass) }
    }

    // MARK: - Opening Stats

    private func computeOpeningStats(games: [RemoteGame], username: String) async -> [OpeningStats] {
        var openingData: [String: (eco: String, name: String, wins: Int, losses: Int, draws: Int)] = [:]

        for game in games {
            // PGNParser methods need MainActor
            let (eco, name) = await MainActor.run {
                let eco = PGNParser.extractECO(from: game.pgn) ?? "Unknown"
                let name = PGNParser.extractOpeningName(from: game.pgn) ?? eco
                return (eco, name)
            }

            let key = eco
            var data = openingData[key] ?? (eco: eco, name: name, wins: 0, losses: 0, draws: 0)

            // Prefer longer/more specific opening names (e.g., "Sicilian Defense: Najdorf" over "Sicilian Defense")
            if name.count > data.name.count {
                data.name = name
            }

            let result = classifyResult(game: game, username: username)
            switch result {
            case .win: data.wins += 1
            case .loss: data.losses += 1
            case .draw: data.draws += 1
            case .unknown: break
            }

            openingData[key] = data
        }

        // Create OpeningStats on MainActor
        let finalData = openingData
        return await MainActor.run {
            finalData.map { (_, value) in
                OpeningStats(
                    ecoCode: value.eco,
                    openingName: value.name,
                    gamesPlayed: value.wins + value.losses + value.draws,
                    wins: value.wins,
                    losses: value.losses,
                    draws: value.draws
                )
            }
            .sorted { $0.gamesPlayed > $1.gamesPlayed }
        }
    }

    // MARK: - Move Quality Stats

    private func computeMoveQualityStats(downloadedGames: [GameMetadata], username: String) async -> MoveQualityStats {
        // Only include games that have been analyzed
        let analyzedGames = downloadedGames.filter { $0.lastAnalyzedAt != nil }

        guard !analyzedGames.isEmpty else {
            return await MainActor.run { MoveQualityStats.empty }
        }

        var totalMoves = 0
        var brilliantMoves = 0
        var greatMoves = 0
        var bestMoves = 0
        var goodMoves = 0
        var inaccuracies = 0
        var mistakes = 0
        var blunders = 0
        var totalAccuracy = 0.0
        var gamesWithAccuracy = 0

        for game in analyzedGames {
            do {
                let store = await getStore()
                let analyses = try await store.fetchAnalysis(gameId: game.id)
                guard !analyses.isEmpty else { continue }

                // Determine which moves belong to the user
                let playedAsWhite = game.summary.whitePlayer.lowercased() == username
                let userMoves = analyses.filter { move in
                    let isWhiteMove = move.ply % 2 == 1
                    return playedAsWhite == isWhiteMove
                }

                for move in userMoves {
                    totalMoves += 1

                    switch move.classification.lowercased() {
                    case "brilliant": brilliantMoves += 1
                    case "great": greatMoves += 1
                    case "best": bestMoves += 1
                    case "excellent": bestMoves += 1  // Count excellent as best-tier
                    case "good": goodMoves += 1
                    case "book": goodMoves += 1  // Count book moves as good-tier
                    case "inaccuracy": inaccuracies += 1
                    case "mistake": mistakes += 1
                    case "miss": mistakes += 1  // Count miss as mistake-tier
                    case "blunder": blunders += 1
                    default: break
                    }
                }

                // Calculate accuracy for this game
                if !userMoves.isEmpty {
                    let accuracy = computeAccuracy(moves: userMoves)
                    totalAccuracy += accuracy
                    gamesWithAccuracy += 1
                }
            } catch {
                // Skip games with fetch errors
                continue
            }
        }

        let averageAccuracy = gamesWithAccuracy > 0 ? totalAccuracy / Double(gamesWithAccuracy) : 0

        return MoveQualityStats(
            totalMoves: totalMoves,
            brilliantMoves: brilliantMoves,
            greatMoves: greatMoves,
            bestMoves: bestMoves,
            goodMoves: goodMoves,
            inaccuracies: inaccuracies,
            mistakes: mistakes,
            blunders: blunders,
            averageAccuracy: averageAccuracy,
            analyzedGameCount: analyzedGames.count
        )
    }

    // MARK: - Accuracy Trend

    private func computeAccuracyTrend(downloadedGames: [GameMetadata], username: String) async -> [AccuracyDataPoint] {
        var dataPoints: [AccuracyDataPoint] = []

        // Sort by game date
        let sortedGames = downloadedGames
            .filter { $0.lastAnalyzedAt != nil }
            .sorted { parseGameDate($0.summary.gameDate) ?? .distantPast < parseGameDate($1.summary.gameDate) ?? .distantPast }

        for game in sortedGames {
            do {
                let store = await getStore()
                let analyses = try await store.fetchAnalysis(gameId: game.id)
                guard !analyses.isEmpty else { continue }

                let playedAsWhite = game.summary.whitePlayer.lowercased() == username
                let userMoves = analyses.filter { move in
                    let isWhiteMove = move.ply % 2 == 1
                    return playedAsWhite == isWhiteMove
                }

                guard !userMoves.isEmpty else { continue }

                let accuracy = computeAccuracy(moves: userMoves)
                let date = parseGameDate(game.summary.gameDate) ?? game.downloadedAt
                let gameId = game.id

                let dataPoint = await MainActor.run {
                    AccuracyDataPoint(
                        date: date,
                        accuracy: accuracy,
                        gameId: gameId
                    )
                }
                dataPoints.append(dataPoint)
            } catch {
                continue
            }
        }

        return dataPoints
    }

    // MARK: - Opponent Stats

    private func computeOpponentStats(games: [RemoteGame], username: String) async -> [OpponentStats] {
        var opponentData: [String: (wins: Int, losses: Int, draws: Int)] = [:]

        for game in games {
            let playedAsWhite = game.whitePlayer.lowercased() == username
            let opponent = playedAsWhite ? game.blackPlayer : game.whitePlayer

            var data = opponentData[opponent] ?? (wins: 0, losses: 0, draws: 0)

            let result = classifyResult(game: game, username: username)
            switch result {
            case .win: data.wins += 1
            case .loss: data.losses += 1
            case .draw: data.draws += 1
            case .unknown: break
            }

            opponentData[opponent] = data
        }

        // Create OpponentStats on MainActor
        let finalData = opponentData
        return await MainActor.run {
            finalData.map { (opponent, data) in
                OpponentStats(
                    opponentName: opponent,
                    gamesPlayed: data.wins + data.losses + data.draws,
                    wins: data.wins,
                    losses: data.losses,
                    draws: data.draws
                )
            }
            .sorted { $0.gamesPlayed > $1.gamesPlayed }
        }
    }

    // MARK: - Termination Stats

    private func computeTerminationStats(games: [RemoteGame], username: String) async -> TerminationStats {
        var winsCheckmate = 0, winsResignation = 0, winsTimeout = 0, winsOther = 0
        var lossesCheckmate = 0, lossesResignation = 0, lossesTimeout = 0, lossesOther = 0

        for game in games {
            let result = classifyResult(game: game, username: username)
            let termination = await MainActor.run {
                PGNParser.extractTermination(from: game.pgn)?.lowercased() ?? ""
            }

            let isCheckmate = termination.contains("checkmate")
            let isResignation = termination.contains("resign")
            let isTimeout = termination.contains("time") || termination.contains("timeout") || termination.contains("abandonment")

            switch result {
            case .win:
                if isCheckmate { winsCheckmate += 1 }
                else if isResignation { winsResignation += 1 }
                else if isTimeout { winsTimeout += 1 }
                else { winsOther += 1 }
            case .loss:
                if isCheckmate { lossesCheckmate += 1 }
                else if isResignation { lossesResignation += 1 }
                else if isTimeout { lossesTimeout += 1 }
                else { lossesOther += 1 }
            case .draw, .unknown:
                break
            }
        }

        return TerminationStats(
            winsBy: TerminationBreakdown(
                checkmate: winsCheckmate,
                resignation: winsResignation,
                timeout: winsTimeout,
                other: winsOther
            ),
            lossesBy: TerminationBreakdown(
                checkmate: lossesCheckmate,
                resignation: lossesResignation,
                timeout: lossesTimeout,
                other: lossesOther
            )
        )
    }

    // MARK: - Helpers

    private enum GameResult {
        case win, loss, draw, unknown
    }

    private func classifyResult(game: RemoteGame, username: String) -> GameResult {
        let playedAsWhite = game.whitePlayer.lowercased() == username
        let result = game.result

        switch result {
        case "1-0":
            return playedAsWhite ? .win : .loss
        case "0-1":
            return playedAsWhite ? .loss : .win
        case "1/2-1/2":
            return .draw
        default:
            return .unknown
        }
    }

    private func computeAccuracy(moves: [MoveAnalysis]) -> Double {
        guard !moves.isEmpty else { return 0 }
        let totalLoss = moves.reduce(0) { $0 + $1.loss }
        let acpl = Double(totalLoss) / Double(moves.count)
        // Chess.com-style accuracy formula
        let accuracy = 103.1668 * exp(-0.04354 * acpl) - 3.1669
        return max(0, min(100, (accuracy * 10).rounded() / 10))
    }

    private nonisolated func parseGameDate(_ value: String) -> Date? {
        Self.gameDateFormatter.date(from: value)
    }
}

//
//  StatisticsModels.swift
//  ChessAnalysis
//

import Foundation

// MARK: - Overall Performance

struct OverallStats: Hashable, Sendable {
    let totalGames: Int
    let wins: Int
    let losses: Int
    let draws: Int

    var winRate: Double {
        totalGames > 0 ? Double(wins) / Double(totalGames) * 100 : 0
    }

    var lossRate: Double {
        totalGames > 0 ? Double(losses) / Double(totalGames) * 100 : 0
    }

    var drawRate: Double {
        totalGames > 0 ? Double(draws) / Double(totalGames) * 100 : 0
    }

    static let empty = OverallStats(totalGames: 0, wins: 0, losses: 0, draws: 0)
}

// MARK: - Color-based Stats

struct ColorStats: Hashable, Sendable {
    let asWhite: OverallStats
    let asBlack: OverallStats

    static let empty = ColorStats(asWhite: .empty, asBlack: .empty)
}

// MARK: - Time Control Stats

struct TimeControlStats: Hashable, Sendable {
    let bullet: OverallStats
    let blitz: OverallStats
    let rapid: OverallStats
    let classical: OverallStats

    static let empty = TimeControlStats(
        bullet: .empty,
        blitz: .empty,
        rapid: .empty,
        classical: .empty
    )
}

// MARK: - Rating History

struct RatingDataPoint: Identifiable, Hashable, Sendable {
    let id: UUID
    let date: Date
    let rating: Int
    let timeClass: String

    init(date: Date, rating: Int, timeClass: String) {
        self.id = UUID()
        self.date = date
        self.rating = rating
        self.timeClass = timeClass
    }
}

// MARK: - Opening Statistics

struct OpeningStats: Identifiable, Hashable, Sendable {
    let id: UUID
    let ecoCode: String
    let openingName: String
    let gamesPlayed: Int
    let wins: Int
    let losses: Int
    let draws: Int

    var winRate: Double {
        gamesPlayed > 0 ? Double(wins) / Double(gamesPlayed) * 100 : 0
    }

    init(ecoCode: String, openingName: String, gamesPlayed: Int, wins: Int, losses: Int, draws: Int) {
        self.id = UUID()
        self.ecoCode = ecoCode
        self.openingName = openingName
        self.gamesPlayed = gamesPlayed
        self.wins = wins
        self.losses = losses
        self.draws = draws
    }
}

// MARK: - Move Quality Stats (from analyzed games)

struct MoveQualityStats: Hashable, Sendable {
    let totalMoves: Int
    let brilliantMoves: Int
    let greatMoves: Int
    let bestMoves: Int
    let goodMoves: Int
    let inaccuracies: Int
    let mistakes: Int
    let blunders: Int
    let averageAccuracy: Double
    let analyzedGameCount: Int

    static let empty = MoveQualityStats(
        totalMoves: 0,
        brilliantMoves: 0,
        greatMoves: 0,
        bestMoves: 0,
        goodMoves: 0,
        inaccuracies: 0,
        mistakes: 0,
        blunders: 0,
        averageAccuracy: 0,
        analyzedGameCount: 0
    )
}

// MARK: - Accuracy Trend

struct AccuracyDataPoint: Identifiable, Hashable, Sendable {
    let id: UUID
    let date: Date
    let accuracy: Double
    let gameId: UUID

    init(date: Date, accuracy: Double, gameId: UUID) {
        self.id = UUID()
        self.date = date
        self.accuracy = accuracy
        self.gameId = gameId
    }
}

// MARK: - Opponent Stats

struct OpponentStats: Identifiable, Hashable, Sendable {
    let id: UUID
    let opponentName: String
    let gamesPlayed: Int
    let wins: Int
    let losses: Int
    let draws: Int

    var winRate: Double {
        gamesPlayed > 0 ? Double(wins) / Double(gamesPlayed) * 100 : 0
    }

    init(opponentName: String, gamesPlayed: Int, wins: Int, losses: Int, draws: Int) {
        self.id = UUID()
        self.opponentName = opponentName
        self.gamesPlayed = gamesPlayed
        self.wins = wins
        self.losses = losses
        self.draws = draws
    }
}

// MARK: - Termination Stats

struct TerminationBreakdown: Hashable, Sendable {
    let checkmate: Int
    let resignation: Int
    let timeout: Int
    let other: Int

    var total: Int { checkmate + resignation + timeout + other }

    static let empty = TerminationBreakdown(checkmate: 0, resignation: 0, timeout: 0, other: 0)
}

struct TerminationStats: Hashable, Sendable {
    let winsBy: TerminationBreakdown
    let lossesBy: TerminationBreakdown

    static let empty = TerminationStats(winsBy: .empty, lossesBy: .empty)
}

// MARK: - Aggregate Container

struct AggregatedStatistics: Hashable, Sendable {
    let overall: OverallStats
    let byColor: ColorStats
    let byTimeControl: TimeControlStats
    let ratingHistory: [RatingDataPoint]
    let openings: [OpeningStats]
    let moveQuality: MoveQualityStats
    let accuracyTrend: [AccuracyDataPoint]
    let opponents: [OpponentStats]
    let terminations: TerminationStats

    static let empty = AggregatedStatistics(
        overall: .empty,
        byColor: .empty,
        byTimeControl: .empty,
        ratingHistory: [],
        openings: [],
        moveQuality: .empty,
        accuracyTrend: [],
        opponents: [],
        terminations: .empty
    )
}

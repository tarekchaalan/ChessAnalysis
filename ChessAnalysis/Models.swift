import Foundation

struct RemoteGame: Identifiable, Hashable, Codable {
    let id: String
    let pgn: String
    let whitePlayer: String
    let blackPlayer: String
    let whiteElo: Int?
    let blackElo: Int?
    let result: String
    let gameDate: String
    let timeControl: String
    let timeClass: String
    let endTime: Date?
    let url: String
}

struct GameMetadata: Identifiable, Hashable {
    let id: UUID
    let remoteId: String
    let pgnPath: String
    let downloadedAt: Date
    let lastAnalyzedAt: Date?
    let analysisVersion: Int
    let bytesOnDisk: Int64
    let summary: GameSummary
}

struct GameSummary: Hashable {
    let whitePlayer: String
    let blackPlayer: String
    let whiteElo: Int?
    let blackElo: Int?
    let result: String
    let gameDate: String
    let timeControl: String
}

struct AnalysisLine: Hashable {
    let pv: String
    let evalCp: Int
    let bestMoveUci: String
}

struct MoveAnalysis: Identifiable, Hashable {
    let id = UUID()
    let ply: Int
    let fen: String
    let playedUci: String
    let bestUci: String
    let evalBefore: Int
    let evalAfter: Int
    let loss: Int
    let classification: String
    let pv: String
}

struct AnalysisResult: Hashable {
    let moves: [MoveAnalysis]
    let accuracyPercent: Double
}

enum MoveClassification: String {
    case best = "Best"
    case great = "Great"
    case brilliant = "Brilliant"
    case good = "Good"
    case inaccuracy = "Inaccuracy"
    case mistake = "Mistake"
    case blunder = "Blunder"
}

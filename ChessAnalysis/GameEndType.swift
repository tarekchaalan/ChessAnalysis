import Foundation

enum EndFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case resignation = "Resignation"
    case checkmate = "Checkmate"
    case timeout = "Time"

    var id: String { rawValue }
}

enum GameEndType: String, Hashable {
    case resignation
    case checkmate
    case timeout
    case other

    var displayName: String {
        switch self {
        case .resignation: return "resignation"
        case .checkmate: return "checkmate"
        case .timeout: return "timeout"
        case .other: return "resignation"
        }
    }

    static func fromPGN(_ pgn: String) -> GameEndType {
        let termination = PGNParser.extractHeader(from: pgn, key: "Termination")?.lowercased() ?? ""
        let hasMate = PGNParser.extractMoves(from: pgn).last?.contains("#") == true
        if termination.contains("checkmate") || hasMate { return .checkmate }
        if termination.contains("resign") { return .resignation }
        if termination.contains("time") || termination.contains("flag") { return .timeout }
        return .other
    }

    func matches(filter: EndFilter) -> Bool {
        switch filter {
        case .all: return true
        case .resignation: return self == .resignation
        case .checkmate: return self == .checkmate
        case .timeout: return self == .timeout
        }
    }
}

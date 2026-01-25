import Foundation

enum PieceColor: String {
    case white
    case black

    var opposite: PieceColor { self == .white ? .black : .white }
}

enum PieceType: String {
    case king, queen, rook, bishop, knight, pawn
}

struct Piece: Hashable {
    let color: PieceColor
    let type: PieceType
}

struct ChessMove: Hashable {
    let from: Int
    let to: Int
    let promotion: PieceType?
    let isCastleKingSide: Bool
    let isCastleQueenSide: Bool
    let isEnPassant: Bool
}

struct ChessPosition: Hashable {
    var board: [Piece?]
    var sideToMove: PieceColor
    var castlingRights: Set<String>
    var enPassant: Int?
    var halfMoveClock: Int
    var fullMoveNumber: Int

    static func startPosition() -> ChessPosition {
        let pieces = [
            "rnbqkbnr",
            "pppppppp",
            "........",
            "........",
            "........",
            "........",
            "PPPPPPPP",
            "RNBQKBNR"
        ]
        var board: [Piece?] = Array(repeating: nil, count: 64)
        for rank in 0..<8 {
            let row = Array(pieces[rank])
            for file in 0..<8 {
                let index = rank * 8 + file
                board[index] = Piece.from(char: row[file])
            }
        }
        return ChessPosition(
            board: board,
            sideToMove: .white,
            castlingRights: ["K", "Q", "k", "q"],
            enPassant: nil,
            halfMoveClock: 0,
            fullMoveNumber: 1
        )
    }

    func fen() -> String {
        var rows: [String] = []
        for rank in 0..<8 {
            var row = ""
            var empty = 0
            for file in 0..<8 {
                let index = rank * 8 + file
                if let piece = board[index] {
                    if empty > 0 {
                        row.append("\(empty)")
                        empty = 0
                    }
                    row.append(piece.fenChar)
                } else {
                    empty += 1
                }
            }
            if empty > 0 { row.append("\(empty)") }
            rows.append(row)
        }
        let boardPart = rows.joined(separator: "/")
        let side = sideToMove == .white ? "w" : "b"
        let castling = castlingRights.isEmpty ? "-" : castlingRights.sorted().joined()
        let enp = enPassant.flatMap { ChessPosition.squareName(index: $0) } ?? "-"
        return "\(boardPart) \(side) \(castling) \(enp) \(halfMoveClock) \(fullMoveNumber)"
    }

    static func squareName(index: Int) -> String {
        let file = index % 8
        let rank = 8 - (index / 8)
        guard let scalar = UnicodeScalar(97 + file) else { return "a\(rank)" }
        let fileChar = String(scalar)
        return "\(fileChar)\(rank)"
    }

    static func indexFrom(square: String) -> Int? {
        guard square.count == 2,
              let fileChar = square.unicodeScalars.first,
              let rankChar = square.unicodeScalars.last
        else { return nil }
        let file = Int(fileChar.value) - 97
        let rank = Int(rankChar.value) - 49
        guard file >= 0, file < 8, rank >= 0, rank < 8 else { return nil }
        let row = 7 - rank
        return row * 8 + file
    }

    func isValid() -> Bool {
        guard board.count == 64 else { return false }
        let whiteKings = board.compactMap { $0 }.filter { $0.color == .white && $0.type == .king }.count
        let blackKings = board.compactMap { $0 }.filter { $0.color == .black && $0.type == .king }.count
        return whiteKings == 1 && blackKings == 1
    }
}

extension Piece {
    static func from(char: Character) -> Piece? {
        switch char {
        case "K": return Piece(color: .white, type: .king)
        case "Q": return Piece(color: .white, type: .queen)
        case "R": return Piece(color: .white, type: .rook)
        case "B": return Piece(color: .white, type: .bishop)
        case "N": return Piece(color: .white, type: .knight)
        case "P": return Piece(color: .white, type: .pawn)
        case "k": return Piece(color: .black, type: .king)
        case "q": return Piece(color: .black, type: .queen)
        case "r": return Piece(color: .black, type: .rook)
        case "b": return Piece(color: .black, type: .bishop)
        case "n": return Piece(color: .black, type: .knight)
        case "p": return Piece(color: .black, type: .pawn)
        default: return nil
        }
    }

    var fenChar: String {
        switch (color, type) {
        case (.white, .king): return "K"
        case (.white, .queen): return "Q"
        case (.white, .rook): return "R"
        case (.white, .bishop): return "B"
        case (.white, .knight): return "N"
        case (.white, .pawn): return "P"
        case (.black, .king): return "k"
        case (.black, .queen): return "q"
        case (.black, .rook): return "r"
        case (.black, .bishop): return "b"
        case (.black, .knight): return "n"
        case (.black, .pawn): return "p"
        }
    }
}

enum SANParser {
    static func parseMoves(pgnMoves: [String]) throws -> [(ChessMove, ChessPosition)] {
        var position = ChessPosition.startPosition()
        guard position.isValid() else { throw SANError.invalidPosition }
        var result: [(ChessMove, ChessPosition)] = []
        for (index, san) in pgnMoves.enumerated() {
            let ply = index + 1
            let move = try moveFromSAN(san, position: position, ply: ply)
            let before = position
            position = apply(move, to: position)
            if !position.isValid() { throw SANError.invalidPosition }
            result.append((move, before))
        }
        return result
    }

    static func moveFromSAN(_ san: String, position: ChessPosition, ply: Int = 0) throws -> ChessMove {
        let trimmed = san
            .replacingOccurrences(of: "+", with: "")
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "!", with: "")
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: "–", with: "-") // en-dash
            .replacingOccurrences(of: "—", with: "-") // em-dash
            .replacingOccurrences(of: "\u{2010}", with: "-") // hyphen
            .replacingOccurrences(of: "\u{2011}", with: "-") // non-breaking hyphen
            .replacingOccurrences(of: "\u{2212}", with: "-") // minus sign

        // Normalize castling notation
        let castleKingSide = ["O-O", "0-0", "o-o"]
        let castleQueenSide = ["O-O-O", "0-0-0", "o-o-o"]

        if castleKingSide.contains(trimmed) {
            return try castleMove(isKingSide: true, position: position, ply: ply)
        }
        if castleQueenSide.contains(trimmed) {
            return try castleMove(isKingSide: false, position: position, ply: ply)
        }

        let promotion: PieceType?
        let base: Substring
        if let promoIndex = trimmed.firstIndex(of: "=") {
            let promoChar = trimmed[trimmed.index(after: promoIndex)]
            promotion = pieceType(from: promoChar)
            base = trimmed[..<promoIndex]
        } else {
            promotion = nil
            base = trimmed[...]
        }

        let destination = String(base.suffix(2))
        guard let toIndex = ChessPosition.indexFrom(square: destination) else {
            throw SANError.invalidMove(move: san, ply: ply)
        }

        let isCapture = trimmed.contains("x")
        let pieceChar = trimmed.first ?? " "
        let pieceType = pieceType(from: pieceChar) ?? .pawn

        let disambiguation = parseDisambiguation(trimmed, pieceType: pieceType)
        let candidates = legalMoves(for: position, pieceType: pieceType)
            .filter { $0.to == toIndex }
            .filter { move in
                if let promo = promotion {
                    return move.promotion == promo
                }
                return true
            }
            .filter { move in
                // If notation has "x", require it to be a capture
                if isCapture {
                    if move.isEnPassant { return true }
                    if let target = position.board[move.to] {
                        return target.color != position.sideToMove
                    }
                    return false
                }
                // If notation doesn't have "x", allow both captures and non-captures
                // (some PGNs omit the "x" for captures)
                return true
            }

        let resolved = candidates.filter { move in
            if let file = disambiguation.file, move.from % 8 != file { return false }
            if let rank = disambiguation.rank, move.from / 8 != rank { return false }
            return true
        }

        guard let move = resolved.first else {
            throw SANError.unresolvedMove(move: san, ply: ply)
        }
        return move
    }

    private static func castleMove(isKingSide: Bool, position: ChessPosition, ply: Int = 0) throws -> ChessMove {
        if position.sideToMove == .white {
            guard let from = ChessPosition.indexFrom(square: "e1"),
                  let to = ChessPosition.indexFrom(square: isKingSide ? "g1" : "c1") else {
                throw SANError.invalidMove(move: isKingSide ? "O-O" : "O-O-O", ply: ply)
            }
            return ChessMove(from: from, to: to, promotion: nil, isCastleKingSide: isKingSide, isCastleQueenSide: !isKingSide, isEnPassant: false)
        } else {
            guard let from = ChessPosition.indexFrom(square: "e8"),
                  let to = ChessPosition.indexFrom(square: isKingSide ? "g8" : "c8") else {
                throw SANError.invalidMove(move: isKingSide ? "O-O" : "O-O-O", ply: ply)
            }
            return ChessMove(from: from, to: to, promotion: nil, isCastleKingSide: isKingSide, isCastleQueenSide: !isKingSide, isEnPassant: false)
        }
    }

    private static func pieceType(from char: Character) -> PieceType? {
        switch char {
        case "K": return .king
        case "Q": return .queen
        case "R": return .rook
        case "B": return .bishop
        case "N": return .knight
        default: return nil
        }
    }

    private static func parseDisambiguation(_ san: String, pieceType: PieceType) -> (file: Int?, rank: Int?) {
        if pieceType == .pawn {
            let chars = Array(san)
            if chars.count >= 2, chars[1] == "x" {
                let fileChar = chars[0]
                guard let scalar = fileChar.unicodeScalars.first else { return (nil, nil) }
                let file = Int(scalar.value) - 97
                return (file, nil)
            }
            return (nil, nil)
        }

        let body = san.dropFirst()
        let bodyStr = body.replacingOccurrences(of: "x", with: "")
        if bodyStr.count <= 2 {
            return (nil, nil)
        }
        let dis = bodyStr.prefix(bodyStr.count - 2)
        var file: Int?
        var rank: Int?
        for ch in dis {
            guard let scalar = ch.unicodeScalars.first else { continue }
            if ch >= "a" && ch <= "h" {
                file = Int(scalar.value) - 97
            } else if ch >= "1" && ch <= "8" {
                rank = 8 - (Int(scalar.value) - 48)
            }
        }
        return (file, rank)
    }

    private static func legalMoves(for position: ChessPosition, pieceType: PieceType) -> [ChessMove] {
        guard position.isValid() else { return [] }
        let pseudo = MoveGenerator.pseudoLegalMoves(position: position, pieceType: pieceType)
        return pseudo.filter { move in
            let next = apply(move, to: position)
            return !MoveGenerator.isKingInCheck(position: next, color: position.sideToMove)
        }
    }

    static func apply(_ move: ChessMove, to position: ChessPosition) -> ChessPosition {
        return MoveGenerator.apply(move: move, to: position)
    }
}

enum SANError: Error, LocalizedError {
    case invalidMove(move: String, ply: Int)
    case unresolvedMove(move: String, ply: Int)
    case invalidPosition

    var errorDescription: String? {
        switch self {
        case .invalidMove(let move, let ply):
            return "Invalid PGN: could not parse move '\(move)' at ply \(ply)."
        case .unresolvedMove(let move, let ply):
            return "Invalid PGN: could not resolve move '\(move)' at ply \(ply)."
        case .invalidPosition:
            return "Invalid PGN: position became illegal."
        }
    }
}

enum MoveGenerator {
    static func pseudoLegalMoves(position: ChessPosition, pieceType: PieceType) -> [ChessMove] {
        var moves: [ChessMove] = []
        guard position.board.count == 64 else { return moves }
        for index in 0..<64 {
            guard let piece = position.board[index], piece.color == position.sideToMove, piece.type == pieceType else { continue }
            moves.append(contentsOf: movesForPiece(at: index, piece: piece, position: position))
        }
        return moves
    }

    static func isKingInCheck(position: ChessPosition, color: PieceColor) -> Bool {
        guard let kingIndex = position.board.firstIndex(where: { $0?.type == .king && $0?.color == color }) else { return false }
        return isSquareAttacked(index: kingIndex, by: color.opposite, position: position)
    }

    static func isCheckmate(position: ChessPosition) -> Bool {
        let color = position.sideToMove
        guard isKingInCheck(position: position, color: color) else { return false }
        // Check if there are any legal moves
        for i in 0..<64 {
            guard let piece = position.board[i], piece.color == color else { continue }
            let moves = movesForPiece(at: i, piece: piece, position: position, ignoreKingSafety: false)
            for move in moves {
                let next = apply(move: move, to: position)
                if !isKingInCheck(position: next, color: color) {
                    return false
                }
            }
        }
        return true
    }

    static func isSquareAttacked(index: Int, by color: PieceColor, position: ChessPosition) -> Bool {
        guard position.board.count == 64 else { return false }
        for i in 0..<64 {
            guard let piece = position.board[i], piece.color == color else { continue }
            let moves = movesForPiece(at: i, piece: piece, position: position, ignoreKingSafety: true)
            if moves.contains(where: { $0.to == index }) {
                return true
            }
        }
        return false
    }

    static func movesForPiece(at index: Int, piece: Piece, position: ChessPosition, ignoreKingSafety: Bool = false) -> [ChessMove] {
        guard position.isValid(), position.board.count == 64, index >= 0, index < 64 else { return [] }
        switch piece.type {
        case .pawn: return pawnMoves(at: index, piece: piece, position: position)
        case .knight: return knightMoves(at: index, piece: piece, position: position)
        case .bishop: return slidingMoves(at: index, piece: piece, position: position, directions: [(-1,-1), (-1,1), (1,-1), (1,1)])
        case .rook: return slidingMoves(at: index, piece: piece, position: position, directions: [(-1,0), (1,0), (0,-1), (0,1)])
        case .queen: return slidingMoves(at: index, piece: piece, position: position, directions: [(-1,-1), (-1,1), (1,-1), (1,1), (-1,0), (1,0), (0,-1), (0,1)])
        case .king:
            var moves = kingMoves(at: index, piece: piece, position: position, includeCastling: !ignoreKingSafety)
            if !ignoreKingSafety {
                moves = moves.filter { move in
                    let next = apply(move: move, to: position)
                    return !isKingInCheck(position: next, color: piece.color)
                }
            }
            return moves
        }
    }

    private static func pawnMoves(at index: Int, piece: Piece, position: ChessPosition) -> [ChessMove] {
        var moves: [ChessMove] = []
        guard position.board.count == 64, index >= 0, index < 64 else { return moves }
        let direction = piece.color == .white ? -1 : 1
        let startRank = piece.color == .white ? 6 : 1
        let promotionRank = piece.color == .white ? 0 : 7
        let file = index % 8

        let forward = index + direction * 8
        if forward >= 0 && forward < 64, position.board[forward] == nil {
            if forward / 8 == promotionRank {
                moves.append(contentsOf: promotionMoves(from: index, to: forward))
            } else {
                moves.append(ChessMove(from: index, to: forward, promotion: nil, isCastleKingSide: false, isCastleQueenSide: false, isEnPassant: false))
            }
            if index / 8 == startRank {
                let doubleForward = index + direction * 16
                if doubleForward >= 0 && doubleForward < 64, position.board[doubleForward] == nil {
                    moves.append(ChessMove(from: index, to: doubleForward, promotion: nil, isCastleKingSide: false, isCastleQueenSide: false, isEnPassant: false))
                }
            }
        }

        for fileOffset in [-1, 1] {
            if (file == 0 && fileOffset == -1) || (file == 7 && fileOffset == 1) {
                continue
            }
            let target = index + direction * 8 + fileOffset
            if target >= 0 && target < 64 {
                if let capturePiece = position.board[target], capturePiece.color != piece.color {
                    if target / 8 == promotionRank {
                        moves.append(contentsOf: promotionMoves(from: index, to: target))
                    } else {
                        moves.append(ChessMove(from: index, to: target, promotion: nil, isCastleKingSide: false, isCastleQueenSide: false, isEnPassant: false))
                    }
                }
            }
        }

        if let ep = position.enPassant {
            let epRank = piece.color == .white ? 3 : 4
            var targets: [Int] = []
            if file > 0 { targets.append(index + direction * 8 - 1) }
            if file < 7 { targets.append(index + direction * 8 + 1) }
            if index / 8 == epRank, targets.contains(ep) {
                moves.append(ChessMove(from: index, to: ep, promotion: nil, isCastleKingSide: false, isCastleQueenSide: false, isEnPassant: true))
            }
        }

        return moves
    }

    private static func promotionMoves(from: Int, to: Int) -> [ChessMove] {
        return [
            ChessMove(from: from, to: to, promotion: .queen, isCastleKingSide: false, isCastleQueenSide: false, isEnPassant: false),
            ChessMove(from: from, to: to, promotion: .rook, isCastleKingSide: false, isCastleQueenSide: false, isEnPassant: false),
            ChessMove(from: from, to: to, promotion: .bishop, isCastleKingSide: false, isCastleQueenSide: false, isEnPassant: false),
            ChessMove(from: from, to: to, promotion: .knight, isCastleKingSide: false, isCastleQueenSide: false, isEnPassant: false)
        ]
    }

    private static func knightMoves(at index: Int, piece: Piece, position: ChessPosition) -> [ChessMove] {
        let offsets = [(-2,-1), (-2,1), (-1,-2), (-1,2), (1,-2), (1,2), (2,-1), (2,1)]
        return offsets.compactMap { dr, dc in
            let row = index / 8 + dr
            let col = index % 8 + dc
            guard row >= 0, row < 8, col >= 0, col < 8 else { return nil }
            let target = row * 8 + col
            if let occupant = position.board[target], occupant.color == piece.color { return nil }
            return ChessMove(from: index, to: target, promotion: nil, isCastleKingSide: false, isCastleQueenSide: false, isEnPassant: false)
        }
    }

    private static func slidingMoves(at index: Int, piece: Piece, position: ChessPosition, directions: [(Int, Int)]) -> [ChessMove] {
        var moves: [ChessMove] = []
        for (dr, dc) in directions {
            var row = index / 8 + dr
            var col = index % 8 + dc
            while row >= 0, row < 8, col >= 0, col < 8 {
                let target = row * 8 + col
                if let occupant = position.board[target] {
                    if occupant.color != piece.color {
                        moves.append(ChessMove(from: index, to: target, promotion: nil, isCastleKingSide: false, isCastleQueenSide: false, isEnPassant: false))
                    }
                    break
                } else {
                    moves.append(ChessMove(from: index, to: target, promotion: nil, isCastleKingSide: false, isCastleQueenSide: false, isEnPassant: false))
                }
                row += dr
                col += dc
            }
        }
        return moves
    }

    private static func kingMoves(at index: Int, piece: Piece, position: ChessPosition, includeCastling: Bool) -> [ChessMove] {
        var moves: [ChessMove] = []
        guard position.isValid(), position.board.count == 64, index >= 0, index < 64 else { return moves }
        let offsets = [(-1,-1), (-1,0), (-1,1), (0,-1), (0,1), (1,-1), (1,0), (1,1)]
        for (dr, dc) in offsets {
            let row = index / 8 + dr
            let col = index % 8 + dc
            guard row >= 0, row < 8, col >= 0, col < 8 else { continue }
            let target = row * 8 + col
            if let occupant = position.board[target], occupant.color == piece.color { continue }
            moves.append(ChessMove(from: index, to: target, promotion: nil, isCastleKingSide: false, isCastleQueenSide: false, isEnPassant: false))
        }

        guard includeCastling else { return moves }
        guard position.board.count == 64 else { return moves }
        if piece.color == .white {
            guard let e1 = ChessPosition.indexFrom(square: "e1"),
                  let f1 = ChessPosition.indexFrom(square: "f1"),
                  let g1 = ChessPosition.indexFrom(square: "g1"),
                  let d1 = ChessPosition.indexFrom(square: "d1"),
                  let c1 = ChessPosition.indexFrom(square: "c1"),
                  let b1 = ChessPosition.indexFrom(square: "b1") else { return moves }
            if position.castlingRights.contains("K") &&
                position.board[f1] == nil &&
                position.board[g1] == nil &&
                !isSquareAttacked(index: e1, by: .black, position: position) &&
                !isSquareAttacked(index: f1, by: .black, position: position) &&
                !isSquareAttacked(index: g1, by: .black, position: position) {
                moves.append(ChessMove(from: e1, to: g1, promotion: nil, isCastleKingSide: true, isCastleQueenSide: false, isEnPassant: false))
            }
            if position.castlingRights.contains("Q") &&
                position.board[d1] == nil &&
                position.board[c1] == nil &&
                position.board[b1] == nil &&
                !isSquareAttacked(index: e1, by: .black, position: position) &&
                !isSquareAttacked(index: d1, by: .black, position: position) &&
                !isSquareAttacked(index: c1, by: .black, position: position) {
                moves.append(ChessMove(from: e1, to: c1, promotion: nil, isCastleKingSide: false, isCastleQueenSide: true, isEnPassant: false))
            }
        } else {
            guard let e8 = ChessPosition.indexFrom(square: "e8"),
                  let f8 = ChessPosition.indexFrom(square: "f8"),
                  let g8 = ChessPosition.indexFrom(square: "g8"),
                  let d8 = ChessPosition.indexFrom(square: "d8"),
                  let c8 = ChessPosition.indexFrom(square: "c8"),
                  let b8 = ChessPosition.indexFrom(square: "b8") else { return moves }
            if position.castlingRights.contains("k") &&
                position.board[f8] == nil &&
                position.board[g8] == nil &&
                !isSquareAttacked(index: e8, by: .white, position: position) &&
                !isSquareAttacked(index: f8, by: .white, position: position) &&
                !isSquareAttacked(index: g8, by: .white, position: position) {
                moves.append(ChessMove(from: e8, to: g8, promotion: nil, isCastleKingSide: true, isCastleQueenSide: false, isEnPassant: false))
            }
            if position.castlingRights.contains("q") &&
                position.board[d8] == nil &&
                position.board[c8] == nil &&
                position.board[b8] == nil &&
                !isSquareAttacked(index: e8, by: .white, position: position) &&
                !isSquareAttacked(index: d8, by: .white, position: position) &&
                !isSquareAttacked(index: c8, by: .white, position: position) {
                moves.append(ChessMove(from: e8, to: c8, promotion: nil, isCastleKingSide: false, isCastleQueenSide: true, isEnPassant: false))
            }
        }

        return moves
    }

    static func apply(move: ChessMove, to position: ChessPosition) -> ChessPosition {
        var next = position
        var board = position.board
        guard board.count == 64,
              move.from >= 0, move.from < 64,
              move.to >= 0, move.to < 64 else {
            return next
        }
        let movingPiece = board[move.from]
        let capturedPiece = board[move.to]
        board[move.from] = nil

        if move.isEnPassant, let movingPiece {
            let direction = movingPiece.color == .white ? 1 : -1
            let captureIndex = move.to + direction * 8
            if captureIndex >= 0 && captureIndex < 64 {
                board[captureIndex] = nil
            }
        }

        if move.isCastleKingSide || move.isCastleQueenSide {
            if position.sideToMove == .white {
                if move.isCastleKingSide {
                    if let rookFrom = ChessPosition.indexFrom(square: "h1"),
                       let rookTo = ChessPosition.indexFrom(square: "f1"),
                       rookFrom < board.count, rookTo < board.count {
                        board[rookTo] = board[rookFrom]
                        board[rookFrom] = nil
                    }
                } else {
                    if let rookFrom = ChessPosition.indexFrom(square: "a1"),
                       let rookTo = ChessPosition.indexFrom(square: "d1"),
                       rookFrom < board.count, rookTo < board.count {
                        board[rookTo] = board[rookFrom]
                        board[rookFrom] = nil
                    }
                }
            } else {
                if move.isCastleKingSide {
                    if let rookFrom = ChessPosition.indexFrom(square: "h8"),
                       let rookTo = ChessPosition.indexFrom(square: "f8"),
                       rookFrom < board.count, rookTo < board.count {
                        board[rookTo] = board[rookFrom]
                        board[rookFrom] = nil
                    }
                } else {
                    if let rookFrom = ChessPosition.indexFrom(square: "a8"),
                       let rookTo = ChessPosition.indexFrom(square: "d8"),
                       rookFrom < board.count, rookTo < board.count {
                        board[rookTo] = board[rookFrom]
                        board[rookFrom] = nil
                    }
                }
            }
        }

        if let promo = move.promotion, let movingPiece {
            board[move.to] = Piece(color: movingPiece.color, type: promo)
        } else {
            board[move.to] = movingPiece
        }

        next.board = board
        next.enPassant = nil
        if let movingPiece, movingPiece.type == .pawn {
            let diff = abs(move.to - move.from)
            if diff == 16 {
                let direction = movingPiece.color == .white ? -1 : 1
                next.enPassant = move.from + direction * 8
            }
        }

        updateCastlingRights(move: move, position: position, next: &next)
        next.sideToMove = position.sideToMove.opposite
        next.halfMoveClock = (movingPiece?.type == .pawn || capturedPiece != nil) ? 0 : position.halfMoveClock + 1
        if position.sideToMove == .black { next.fullMoveNumber += 1 }
        return next
    }

    private static func updateCastlingRights(move: ChessMove, position: ChessPosition, next: inout ChessPosition) {
        if let movingPiece = position.board[move.from], movingPiece.type == .king {
            if movingPiece.color == .white {
                next.castlingRights.remove("K")
                next.castlingRights.remove("Q")
            } else {
                next.castlingRights.remove("k")
                next.castlingRights.remove("q")
            }
        }
        if let movingPiece = position.board[move.from], movingPiece.type == .rook {
            let fromSquare = ChessPosition.squareName(index: move.from)
            if fromSquare == "a1" { next.castlingRights.remove("Q") }
            if fromSquare == "h1" { next.castlingRights.remove("K") }
            if fromSquare == "a8" { next.castlingRights.remove("q") }
            if fromSquare == "h8" { next.castlingRights.remove("k") }
        }
        if let captured = position.board[move.to], captured.type == .rook {
            let toSquare = ChessPosition.squareName(index: move.to)
            if toSquare == "a1" { next.castlingRights.remove("Q") }
            if toSquare == "h1" { next.castlingRights.remove("K") }
            if toSquare == "a8" { next.castlingRights.remove("q") }
            if toSquare == "h8" { next.castlingRights.remove("k") }
        }
    }
}

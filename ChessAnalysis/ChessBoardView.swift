import SwiftUI

struct ChessBoardView: View {
    let fen: String
    let bestMoveUci: String?
    let lastMoveUci: String?
    let lastMoveClassification: String?
    let isFlipped: Bool
    var arrowScale: CGFloat = 1.0
    @AppStorage("board.theme") private var themeId = BoardTheme.defaultId

    private var position: ChessPosition {
        FENParser.position(from: fen) ?? ChessPosition.startPosition()
    }

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let square = size / 8.0
            ZStack {
                boardSquares(square: square)
                moveHighlights(square: square)
                piecesLayer(square: square)
                classificationBadge(square: square)
                if let move = bestMoveUci, move.count >= 4 {
                    bestMoveArrow(square: square, uci: move)
                }
            }
            .frame(width: size, height: size)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private func boardSquares(square: CGFloat) -> some View {
        let theme = BoardTheme.theme(for: themeId)
        VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { rank in
                HStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { file in
                        Rectangle()
                            .fill(((rank + file) % 2 == 0) ? theme.lightColor : theme.darkColor)
                            .frame(width: square, height: square)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func moveHighlights(square: CGFloat) -> some View {
        if let highlight = highlightSquares() {
            let color = highlight.color
            ForEach(highlight.indices, id: \.self) { index in
                highlightSquare(index: index, square: square, color: color)
            }
        }
    }

    private func highlightSquare(index: Int, square: CGFloat, color: Color) -> some View {
        let (row, col) = displayRowCol(for: index)
        return Rectangle()
            .fill(color)
            .frame(width: square, height: square)
            .position(x: CGFloat(col) * square + square / 2, y: CGFloat(row) * square + square / 2)
    }

    @ViewBuilder
    private func piecesLayer(square: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { rank in
                HStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { file in
                        let boardIndex = boardIndex(forDisplayRow: rank, col: file)
                        let piece = position.board[boardIndex]
                        ZStack {
                            if let assetName = pieceAssetName(piece) {
                                Image(assetName)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: square * 0.95, height: square * 0.95)
                                    .frame(width: square, height: square, alignment: .center)
                            } else {
                                Color.clear
                            }
                        }
                        .frame(width: square, height: square, alignment: .center)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func classificationBadge(square: CGFloat) -> some View {
        if let toIndex = highlightSquares()?.toIndex,
           let classification = lastMoveClassification,
           let assetName = classificationAssetName(classification) {
            let (row, col) = displayRowCol(for: toIndex)
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(width: square * 0.4, height: square * 0.4)
                .position(x: CGFloat(col) * square + square * 0.78, y: CGFloat(row) * square + square * 0.22)
        }
    }

    @ViewBuilder
    private func bestMoveArrow(square: CGFloat, uci: String) -> some View {
        let fromSquare = String(uci.prefix(2))
        let toSquare = String(uci.dropFirst(2).prefix(2))
        if let from = ChessPosition.indexFrom(square: fromSquare),
           let to = ChessPosition.indexFrom(square: toSquare) {
            let fromPoint = squareCenter(index: from, square: square)
            let toPoint = squareCenter(index: to, square: square)
            let arrowColor = Color(red: 0.41, green: 0.57, blue: 0.24)
            let lineWidth = square * 0.12 * arrowScale
            let headLength = square * 0.35 * arrowScale
            let headWidth = square * 0.22 * arrowScale
            let shortenBy = square * 0.25 * arrowScale
            ArrowShape(start: fromPoint, end: toPoint, shortenBy: shortenBy)
                .stroke(arrowColor.opacity(0.9),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                .overlay(
                    ArrowHeadShape(start: fromPoint, end: toPoint, length: headLength, width: headWidth)
                        .fill(arrowColor)
                )
        }
    }

    private func squareCenter(index: Int, square: CGFloat) -> CGPoint {
        let (row, col) = displayRowCol(for: index)
        return CGPoint(x: CGFloat(col) * square + square / 2, y: CGFloat(row) * square + square / 2)
    }

    private func displayRowCol(for boardIndex: Int) -> (row: Int, col: Int) {
        let row = boardIndex / 8
        let col = boardIndex % 8
        if isFlipped {
            return (7 - row, 7 - col)
        }
        return (row, col)
    }

    private func boardIndex(forDisplayRow row: Int, col: Int) -> Int {
        if isFlipped {
            return (7 - row) * 8 + (7 - col)
        }
        return row * 8 + col
    }

    private func highlightSquares() -> (indices: [Int], toIndex: Int, color: Color)? {
        guard let lastMoveUci, lastMoveUci.count >= 4,
              let from = ChessPosition.indexFrom(square: String(lastMoveUci.prefix(2))),
              let to = ChessPosition.indexFrom(square: String(lastMoveUci.dropFirst(2).prefix(2))) else {
            return nil
        }
        let color = classificationHighlightColor(lastMoveClassification ?? "")
        return ([from, to], to, color)
    }

    private func pieceAssetName(_ piece: Piece?) -> String? {
        guard let piece else { return nil }
        switch (piece.color, piece.type) {
        case (.white, .king): return "wk"
        case (.white, .queen): return "wq"
        case (.white, .rook): return "wr"
        case (.white, .bishop): return "wb"
        case (.white, .knight): return "wn"
        case (.white, .pawn): return "wp"
        case (.black, .king): return "bk"
        case (.black, .queen): return "bq"
        case (.black, .rook): return "br"
        case (.black, .bishop): return "bb"
        case (.black, .knight): return "bn"
        case (.black, .pawn): return "bp"
        }
    }
}

struct ArrowShape: Shape {
    let start: CGPoint
    let end: CGPoint
    let shortenBy: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: start)
        let shortened = shortenLine(from: start, to: end, by: shortenBy)
        path.addLine(to: shortened)
        return path
    }

    private func shortenLine(from: CGPoint, to: CGPoint, by amount: CGFloat) -> CGPoint {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = max(1, sqrt(dx * dx + dy * dy))
        let ux = dx / length
        let uy = dy / length
        return CGPoint(x: to.x - ux * amount, y: to.y - uy * amount)
    }
}

struct ArrowHeadShape: Shape {
    let start: CGPoint
    let end: CGPoint
    let length: CGFloat
    let width: CGFloat

    func path(in rect: CGRect) -> Path {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let angle = atan2(dy, dx)
        let length = length
        let width = width

        let tip = end
        let base = CGPoint(
            x: end.x - cos(angle) * length,
            y: end.y - sin(angle) * length
        )
        let left = CGPoint(
            x: base.x + cos(angle + .pi / 2) * width,
            y: base.y + sin(angle + .pi / 2) * width
        )
        let right = CGPoint(
            x: base.x + cos(angle - .pi / 2) * width,
            y: base.y + sin(angle - .pi / 2) * width
        )

        var path = Path()
        path.move(to: tip)
        path.addLine(to: left)
        path.addLine(to: right)
        path.closeSubpath()
        return path
    }
}

enum FENParser {
    static func position(from fen: String) -> ChessPosition? {
        let parts = fen.split(separator: " ")
        guard parts.count >= 4 else { return nil }
        let boardPart = parts[0]
        let side = parts[1] == "w" ? PieceColor.white : PieceColor.black
        let castling = parts[2] == "-" ? [] : Set(parts[2].map { String($0) })
        let enp = parts[3] == "-" ? nil : ChessPosition.indexFrom(square: String(parts[3]))

        var board: [Piece?] = Array(repeating: nil, count: 64)
        let ranks = boardPart.split(separator: "/")
        guard ranks.count == 8 else { return nil }
        for (rankIndex, rank) in ranks.enumerated() {
            var file = 0
            for ch in rank {
                if let digit = ch.wholeNumberValue {
                    file += digit
                } else {
                    let index = rankIndex * 8 + file
                    board[index] = Piece.from(char: ch)
                    file += 1
                }
            }
        }

        return ChessPosition(
            board: board,
            sideToMove: side,
            castlingRights: castling,
            enPassant: enp,
            halfMoveClock: 0,
            fullMoveNumber: 1
        )
    }
}

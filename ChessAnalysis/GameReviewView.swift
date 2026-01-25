import SwiftUI

struct GameReviewView: View {
    let game: GameMetadata
    let username: String
    let pgnText: String
    let positions: [ChessPosition]
    let analyses: [MoveAnalysis]
    let clockTimes: [String]
    let whiteAvatarURL: URL?
    let blackAvatarURL: URL?

    @State private var currentPly: Int = 0
    @AppStorage("review.showBestMove") private var showBestMove = false
    @State private var isFlipped = false
    @State private var didSetInitialFlip = false
    @State private var showMateLine = false
    @State private var isInitialLoad = true

    var body: some View {
        GeometryReader { proxy in
            let boardSize = proxy.size.width
            ScrollView {
                VStack(spacing: 16) {
                    ZStack {
                        EvalBarView(
                            evalCp: currentEval,
                            overrideText: evalBarText,
                            winnerColor: winnerColor,
                            forceWinnerFill: shouldForceWinnerFill
                        )
                        .frame(height: 32)
                        .frame(maxWidth: .infinity)

                        HStack {
                            if showMateButton, currentEval > 0 {
                                Button("Show mate") {
                                    showMateLine = true
                                }
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.black)
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                            }
                            Spacer()
                            if showMateButton, currentEval < 0 {
                                Button("Show mate") {
                                    showMateLine = true
                                }
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.white)
                                .foregroundColor(.black)
                                .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                    .padding(.horizontal, 8)

                    VStack(alignment: .leading, spacing: 8) {
                        PlayerHeaderView(
                            name: isFlipped ? game.summary.whitePlayer : game.summary.blackPlayer,
                            rating: isFlipped ? game.summary.whiteElo : game.summary.blackElo,
                            avatarURL: isFlipped ? whiteAvatarURL : blackAvatarURL,
                            timeRemaining: clockTime(for: isFlipped ? .white : .black)
                        )
                        .padding(.horizontal, 8)

                        ChessBoardView(
                            fen: currentFEN,
                            bestMoveUci: showBestMove ? currentBestMove : nil,
                            lastMoveUci: currentMove?.playedUci,
                            lastMoveClassification: currentMove?.classification,
                            isFlipped: isFlipped
                        )
                        .frame(width: boardSize, height: boardSize)

                        PlayerHeaderView(
                            name: isFlipped ? game.summary.blackPlayer : game.summary.whitePlayer,
                            rating: isFlipped ? game.summary.blackElo : game.summary.whiteElo,
                            avatarURL: isFlipped ? blackAvatarURL : whiteAvatarURL,
                            timeRemaining: clockTime(for: isFlipped ? .black : .white)
                        )
                        .padding(.horizontal, 8)
                    }

                    moveScroller
                        .padding(.horizontal, 8)
                    moveList
                        .padding(.horizontal, 8)
                }
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isFlipped.toggle()
                } label: {
                    FlipBoardIcon()
                        .frame(width: 22, height: 22)
                        .foregroundColor(.white)
                        .rotationEffect(.degrees(isFlipped ? 180 : 0))
                        .animation(.easeInOut(duration: 0.2), value: isFlipped)
                }
                .accessibilityLabel("Flip board")
            }
        }
        .onAppear {
            if !didSetInitialFlip {
                isFlipped = shouldFlipForUser()
                didSetInitialFlip = true
            }
            isInitialLoad = true
            currentPly = positions.isEmpty ? 0 : min(positions.count - 1, 0)
        }
        .onChange(of: currentPly) { _, newValue in
            if isInitialLoad {
                isInitialLoad = false
                return
            }
            playMoveSound(for: newValue)
        }
        .sheet(isPresented: $showMateLine) {
            MateLineView(
                startPosition: currentPosition,
                pvMoves: matePV,
                isFlipped: isFlipped,
                startingMateIn: mateDistance,
                mateForWhite: currentEval > 0
            )
        }
        .onDisappear {
            Task {
                await StockfishEngine.shared.stopIfIdle()
            }
        }
    }

    private var currentMove: MoveAnalysis? {
        guard currentPly > 0, currentPly - 1 < analyses.count else { return nil }
        return analyses[currentPly - 1]
    }

    private var currentEval: Int {
        currentMove?.evalAfter ?? 0
    }

    private var currentPosition: ChessPosition {
        guard currentPly >= 0, currentPly < positions.count else {
            return ChessPosition.startPosition()
        }
        return positions[currentPly]
    }

    private var winnerColor: PieceColor? {
        switch game.summary.result {
        case "1-0": return .white
        case "0-1": return .black
        default: return nil
        }
    }

    private var resignationLabel: String? {
        guard let winnerColor else { return nil }
        if isCheckmate || isTimeOut { return nil }
        guard currentPly >= positions.count - 1 else { return nil }
        let loserName = winnerColor == .white ? game.summary.blackPlayer : game.summary.whitePlayer
        return "\(loserName) Resigned"
    }

    private var evalBarText: String? {
        if isCheckmate {
            return "Checkmate"
        }
        return resignationLabel
    }

    private var shouldForceWinnerFill: Bool {
        isCheckmate || resignationLabel != nil
    }

    private var showMateButton: Bool {
        abs(currentEval) >= 100000 && !matePV.isEmpty && !isCheckmate
    }

    private var mateDistance: Int {
        let eval = abs(currentEval)
        guard eval >= 100000 else { return 0 }
        return eval - 100000
    }

    private var matePV: [String] {
        // analyses[N].pv is the PV from position N (before move N+1 was played)
        // So to get PV from currentPosition (position at currentPly), we need analyses[currentPly].pv
        let pvString: String
        if currentPly < analyses.count {
            // Use the PV from the current position
            pvString = analyses[currentPly].pv
        } else if currentPly > 0, currentPly - 1 < analyses.count {
            // At end of game, no more analysis - fall back but this may be wrong side
            pvString = analyses[currentPly - 1].pv
        } else {
            return []
        }
        let allMoves = pvString.split(separator: " ").map(String.init)
        // Mate in X means X moves by the winning side, so max 2*X - 1 total plies
        // e.g., M3 = at most 5 plies (W, B, W, B, W checkmates)
        let maxPly = max(1, mateDistance * 2 - 1)
        return Array(allMoves.prefix(maxPly))
    }

    private var sanMoves: [String] {
        PGNParser.extractMoves(from: pgnText)
    }

    private var currentFEN: String {
        guard currentPly >= 0, currentPly < positions.count else {
            return ChessPosition.startPosition().fen()
        }
        return positions[currentPly].fen()
    }

    private var currentBestMove: String? {
        currentMove?.bestUci
    }

    private func moveBy(_ delta: Int) {
        let next = currentPly + delta
        guard next >= 0, next < positions.count else { return }
        currentPly = next
    }

    private var moveScroller: some View {
        let pairs = movePairs()
        let selectedId = selectedPairId()
        return ScrollViewReader { reader in
            HStack(spacing: 8) {
                Button(action: { moveBy(-1) }) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
                .disabled(currentPly <= 0)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(pairs) { pair in
                            MovePairCapsule(
                                pair: pair,
                                isSelected: isPairSelected(pair)
                            )
                            .id(pair.id)
                            .onTapGesture {
                                currentPly = min(pair.startPly + 1, positions.count - 1)
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                }
                .onChange(of: selectedId) { _, value in
                    guard let value else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        reader.scrollTo(value, anchor: .center)
                    }
                }

                Button(action: { moveBy(1) }) {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
                .disabled(currentPly >= positions.count - 1)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var moveList: some View {
        let pairs = movePairs()
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(pairs) { pair in
                HStack(spacing: 12) {
                    Text("\(pair.moveNumber).")
                        .frame(width: 28, alignment: .leading)
                        .foregroundColor(.secondary)
                    moveCell(analysis: pair.whiteAnalysis, san: pair.whiteSan)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    moveCell(analysis: pair.blackAnalysis, san: pair.blackSan)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(isPairSelected(pair) ? Color.white.opacity(0.12) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
                .onTapGesture {
                    currentPly = min(pair.startPly + 1, positions.count - 1)
                }
            }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func moveCell(analysis: MoveAnalysis?, san: String?) -> some View {
        let classification = analysis?.classification
        let accessibilityLabel = buildMoveAccessibilityLabel(san: san, classification: classification)

        return HStack(spacing: 6) {
            if let classification,
               let assetName = classificationAssetName(classification) {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .accessibilityHidden(true) // Hide from VoiceOver, included in parent label
            } else {
                Color.clear
                    .frame(width: 16, height: 16)
            }
            Text(san ?? "--")
                .font(.subheadline)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private func buildMoveAccessibilityLabel(san: String?, classification: String?) -> String {
        guard let san else { return "No move" }

        var label = san

        if let classification {
            let classificationDescription: String
            switch classification.lowercased() {
            case "brilliant":
                classificationDescription = "Brilliant move"
            case "great":
                classificationDescription = "Great move"
            case "best":
                classificationDescription = "Best move"
            case "excellent":
                classificationDescription = "Excellent move"
            case "good":
                classificationDescription = "Good move"
            case "book":
                classificationDescription = "Book move"
            case "inaccuracy":
                classificationDescription = "Inaccuracy"
            case "mistake":
                classificationDescription = "Mistake"
            case "blunder":
                classificationDescription = "Blunder"
            case "miss":
                classificationDescription = "Missed opportunity"
            default:
                classificationDescription = classification
            }
            label = "\(san), \(classificationDescription)"
        }

        return label
    }

    private func movePairs() -> [MovePair] {
        let sanMoves = PGNParser.extractMoves(from: pgnText)
        var pairs: [MovePair] = []
        let maxCount = max(sanMoves.count, analyses.count)
        var index = 0
        while index < maxCount {
            let moveNumber = index / 2 + 1
            let whiteSan = index < sanMoves.count ? sanMoves[index] : nil
            let blackSan = index + 1 < sanMoves.count ? sanMoves[index + 1] : nil
            let whiteAnalysis = index < analyses.count ? analyses[index] : nil
            let blackAnalysis = index + 1 < analyses.count ? analyses[index + 1] : nil
            pairs.append(MovePair(
                id: moveNumber,
                moveNumber: moveNumber,
                startPly: index,
                whiteSan: whiteSan,
                blackSan: blackSan,
                whiteAnalysis: whiteAnalysis,
                blackAnalysis: blackAnalysis
            ))
            index += 2
        }
        return pairs
    }

    private func isPairSelected(_ pair: MovePair) -> Bool {
        let currentMoveIndex = max(currentPly - 1, 0)
        return currentMoveIndex >= pair.startPly && currentMoveIndex <= pair.startPly + 1
    }

    private func selectedPairId() -> Int? {
        let pairs = movePairs()
        return pairs.first(where: isPairSelected)?.id
    }

    private func clockTime(for color: PieceColor) -> String {
        guard !clockTimes.isEmpty else { return "--:--" }
        let currentIndex = max(currentPly - 1, 0)
        var index = min(currentIndex, clockTimes.count - 1)
        while index >= 0 {
            let isWhite = index % 2 == 0
            if (color == .white && isWhite) || (color == .black && !isWhite) {
                return clockTimes[index]
            }
            index -= 1
        }
        return "--:--"
    }

    private var isCheckmate: Bool {
        let sanMoves = PGNParser.extractMoves(from: pgnText)
        guard !sanMoves.isEmpty else { return false }
        let lastIndex = sanMoves.count - 1
        guard currentPly >= lastIndex + 1 else { return false }
        return sanMoves[lastIndex].contains("#")
    }

    private var isTimeOut: Bool {
        guard let winnerColor else { return false }
        let loser = winnerColor == .white ? PieceColor.black : PieceColor.white
        guard let time = finalClockTime(for: loser),
              let seconds = parseClockSeconds(time) else {
            return false
        }
        return seconds == 0
    }

    private func finalClockTime(for color: PieceColor) -> String? {
        guard !clockTimes.isEmpty else { return nil }
        for index in stride(from: clockTimes.count - 1, through: 0, by: -1) {
            let isWhite = index % 2 == 0
            if (color == .white && isWhite) || (color == .black && !isWhite) {
                return clockTimes[index]
            }
        }
        return nil
    }

    private func parseClockSeconds(_ value: String) -> Int? {
        if value == "--:--" { return nil }
        let trimmed = value.split(separator: ".").first.map(String.init) ?? value
        let parts = trimmed.split(separator: ":").map { Int($0) ?? 0 }
        if parts.count == 3 {
            return parts[0] * 3600 + parts[1] * 60 + parts[2]
        }
        if parts.count == 2 {
            return parts[0] * 60 + parts[1]
        }
        if parts.count == 1 {
            return parts[0]
        }
        return nil
    }

    private func playMoveSound(for ply: Int) {
        let moveIndex = ply - 1
        guard moveIndex >= 0, moveIndex < sanMoves.count else { return }
        let san = sanMoves[moveIndex]
        let moverIsWhite = moveIndex % 2 == 0
        let soundName: String
        if san.hasPrefix("O-O") {
            soundName = "castle"
        } else if san.contains("=") {
            soundName = "promote"
        } else if san.contains("#") || san.contains("+") {
            soundName = "move-check"
        } else if san.contains("x") {
            soundName = "capture"
        } else {
            soundName = moverIsWhite ? "move-self" : "move-opponent"
        }
        MoveSoundPlayer.play(name: soundName, fileExtension: "wav")
    }

    private func shouldFlipForUser() -> Bool {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if game.summary.whitePlayer.localizedCaseInsensitiveContains(trimmed) { return false }
        if game.summary.blackPlayer.localizedCaseInsensitiveContains(trimmed) { return true }
        return false
    }
}

private struct MovePair: Identifiable {
    let id: Int
    let moveNumber: Int
    let startPly: Int
    let whiteSan: String?
    let blackSan: String?
    let whiteAnalysis: MoveAnalysis?
    let blackAnalysis: MoveAnalysis?
}

private struct MovePairCapsule: View {
    let pair: MovePair
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text("\(pair.moveNumber).")
                .foregroundColor(.secondary)
            moveText(analysis: pair.whiteAnalysis, san: pair.whiteSan)
            moveText(analysis: pair.blackAnalysis, san: pair.blackSan)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(isSelected ? Color.white.opacity(0.16) : Color.black.opacity(0.2))
        .clipShape(Capsule())
    }

    private func moveText(analysis: MoveAnalysis?, san: String?) -> some View {
        HStack(spacing: 4) {
            if let classification = analysis?.classification,
               let assetName = classificationAssetName(classification) {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
            }
            Text(san ?? "--")
        }
    }
}

private struct PlayerHeaderView: View {
    let name: String
    let rating: Int?
    let avatarURL: URL?
    let timeRemaining: String

    var body: some View {
        HStack(spacing: 8) {
            if let avatarURL {
                AsyncImage(url: avatarURL) { image in
                    image.resizable()
                        .scaledToFill()
                } placeholder: {
                    Image("default")
                        .resizable()
                        .scaledToFill()
                }
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image("default")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            HStack(spacing: 4) {
                Text(name)
                    .font(.headline)
                if let rating {
                    Text("(\(rating))")
                        .font(.caption)
                        .fontWeight(.light)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Text(timeRemaining)
                .font(.subheadline)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}

private struct MateLineView: View {
    let startPosition: ChessPosition
    let pvMoves: [String]
    let isFlipped: Bool
    let startingMateIn: Int
    let mateForWhite: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var positions: [ChessPosition] = []
    @State private var currentIndex = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                EvalBarView(
                    evalCp: currentEval,
                    overrideText: evalText,
                    winnerColor: nil,
                    forceWinnerFill: false
                )
                .frame(height: 32)

                ChessBoardView(
                    fen: currentPosition.fen(),
                    bestMoveUci: nextMoveUci,
                    lastMoveUci: lastMoveUci,
                    lastMoveClassification: "mateline",
                    isFlipped: isFlipped
                )
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)

                HStack(spacing: 32) {
                    Button {
                        currentIndex = max(0, currentIndex - 1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 32, weight: .semibold))
                    }
                    .disabled(currentIndex == 0)

                    Text(stepLabel)
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Button {
                        currentIndex = min(max(positions.count - 1, 0), currentIndex + 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 32, weight: .semibold))
                    }
                    .disabled(currentIndex >= max(positions.count - 1, 0))
                }
            }
            .padding()
            .navigationTitle("Mate Line")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                positions = buildPositions()
                currentIndex = 0
            }
        }
    }

    private var currentEval: Int {
        // Calculate mate-in from current position
        // Each move reduces the mate distance by 1 for the mating side
        let movesPlayed = currentIndex
        let whiteMovesPlayed = (movesPlayed + 1) / 2
        let blackMovesPlayed = movesPlayed / 2
        let matingMoves = mateForWhite ? whiteMovesPlayed : blackMovesPlayed
        let remainingMate = max(1, startingMateIn - matingMoves)

        // If it's checkmate (last position), return very high eval
        if currentIndex == positions.count - 1 && positions.count > 1 {
            return mateForWhite ? 100001 : -100001
        }

        return mateForWhite ? (100000 + remainingMate) : -(100000 + remainingMate)
    }

    private var evalText: String? {
        if currentIndex == positions.count - 1 && positions.count > 1 {
            return "Checkmate"
        }
        return nil
    }

    private var currentPosition: ChessPosition {
        if positions.isEmpty { return startPosition }
        return positions[min(currentIndex, positions.count - 1)]
    }

    private var lastMoveUci: String? {
        guard currentIndex > 0, currentIndex - 1 < pvMoves.count else { return nil }
        return pvMoves[currentIndex - 1]
    }

    private var nextMoveUci: String? {
        guard currentIndex < pvMoves.count else { return nil }
        return pvMoves[currentIndex]
    }

    private var stepLabel: String {
        if positions.isEmpty { return "--" }
        return "\(currentIndex)/\(max(positions.count - 1, 0))"
    }

    private func buildPositions() -> [ChessPosition] {
        var result: [ChessPosition] = [startPosition]
        var position = startPosition
        for move in pvMoves {
            guard let parsed = parseUci(move, position: position) else { break }
            position = MoveGenerator.apply(move: parsed, to: position)
            result.append(position)
        }
        return result
    }

    private func parseUci(_ uci: String, position: ChessPosition) -> ChessMove? {
        guard uci.count >= 4 else { return nil }
        let fromSquare = String(uci.prefix(2))
        let toSquare = String(uci.dropFirst(2).prefix(2))
        guard let from = ChessPosition.indexFrom(square: fromSquare),
              let to = ChessPosition.indexFrom(square: toSquare) else { return nil }
        let promoChar = uci.count > 4 ? uci.last : nil
        let promotion: PieceType? = {
            switch promoChar {
            case "q": return .queen
            case "r": return .rook
            case "b": return .bishop
            case "n": return .knight
            default: return nil
            }
        }()
        let movingPiece = position.board[from]
        let isKing = movingPiece?.type == .king
        let isCastleKingSide = isKing && ((fromSquare == "e1" && toSquare == "g1") || (fromSquare == "e8" && toSquare == "g8"))
        let isCastleQueenSide = isKing && ((fromSquare == "e1" && toSquare == "c1") || (fromSquare == "e8" && toSquare == "c8"))
        let isEnPassant = movingPiece?.type == .pawn && position.enPassant == to
        return ChessMove(
            from: from,
            to: to,
            promotion: promotion,
            isCastleKingSide: isCastleKingSide,
            isCastleQueenSide: isCastleQueenSide,
            isEnPassant: isEnPassant
        )
    }
}

private struct FlipBoardIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        let offsetX = rect.midX - 12 * scale
        let offsetY = rect.midY - 12 * scale
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: x * scale + offsetX, y: y * scale + offsetY)
        }

        var path = Path()
        path.move(to: p(8, 22))
        path.addLine(to: p(5.88616, 22))
        path.addCurve(to: p(3.05381, 21.4576),
                      control1: p(4.18402, 22),
                      control2: p(3.33294, 22))
        path.addCurve(to: p(4.25869, 18.8375),
                      control1: p(2.77467, 20.9152),
                      control2: p(3.26934, 20.2226))
        path.addLine(to: p(5.38815, 17.2563))
        path.addCurve(to: p(6.37105, 16.1662),
                      control1: p(5.82805, 16.6404),
                      control2: p(6.048, 16.3325))
        path.addCurve(to: p(7.82935, 16),
                      control1: p(6.69411, 16),
                      control2: p(7.07252, 16))
        path.addLine(to: p(16.1702, 16))
        path.addCurve(to: p(17.6285, 16.1662),
                      control1: p(16.927, 16),
                      control2: p(17.3055, 16))
        path.addCurve(to: p(18.6114, 17.2563),
                      control1: p(17.9516, 16.3325),
                      control2: p(18.1715, 16.6404))
        path.addLine(to: p(19.7409, 18.8375))
        path.addCurve(to: p(20.9458, 21.4576),
                      control1: p(20.7302, 20.2226),
                      control2: p(21.2249, 20.9152))
        path.addCurve(to: p(18.1134, 22),
                      control1: p(20.6666, 22),
                      control2: p(19.8156, 22))
        path.addLine(to: p(12, 22))

        path.move(to: p(12, 2))
        path.addLine(to: p(5.88616, 2))
        path.addCurve(to: p(3.05381, 2.54242),
                      control1: p(4.18402, 2),
                      control2: p(3.33294, 2))
        path.addCurve(to: p(4.25869, 5.16247),
                      control1: p(2.77467, 3.08484),
                      control2: p(3.26934, 3.77738))
        path.addLine(to: p(5.38815, 6.74372))
        path.addCurve(to: p(6.37105, 7.83375),
                      control1: p(5.82805, 7.35957),
                      control2: p(6.048, 7.6675))
        path.addCurve(to: p(7.82935, 8),
                      control1: p(6.69411, 8),
                      control2: p(7.07252, 8))
        path.addLine(to: p(16.1702, 8))
        path.addCurve(to: p(17.6285, 7.83375),
                      control1: p(16.927, 8),
                      control2: p(17.3055, 8))
        path.addCurve(to: p(18.6114, 6.74372),
                      control1: p(17.9516, 7.6675),
                      control2: p(18.1715, 7.35957))
        path.addLine(to: p(19.7409, 5.16248))
        path.addCurve(to: p(20.9458, 2.54242),
                      control1: p(20.7302, 3.77738),
                      control2: p(21.2249, 3.08484))
        path.addCurve(to: p(18.1134, 2),
                      control1: p(20.6666, 2),
                      control2: p(19.8156, 2))
        path.addLine(to: p(16.0567, 2))

        path.move(to: p(14, 12))
        path.addLine(to: p(10, 12))
        path.move(to: p(6, 12))
        path.addLine(to: p(2, 12))
        path.move(to: p(22, 12))
        path.addLine(to: p(18, 12))

        return path
    }
}

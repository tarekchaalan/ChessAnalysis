import SwiftUI

struct GameDetailView: View {
    let game: GameMetadata
    @ObservedObject var settings: AppSettings
    @StateObject private var viewModel = AnalysisViewModel()
    @State private var pgnText: String = ""
    @State private var positions: [ChessPosition] = []
    @State private var clockTimes: [String] = []
    @State private var whiteAvatarURL: URL?
    @State private var blackAvatarURL: URL?
    @State private var whiteRating: Int = 1500
    @State private var blackRating: Int = 1500

    private let classificationOrder = [
        "Brilliant", "Great", "Best", "Excellent", "Good", "Book",
        "Inaccuracy", "Mistake", "Miss", "Blunder"
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                summaryHeader
                EvaluationGraphView(evals: viewModel.analyses.map { $0.evalAfter })

                accuracySection
                classificationSection
                ratingSection
                phaseSection
                analysisSection

                NavigationLink("Review Game") {
                    GameReviewView(
                        game: game,
                        username: settings.username,
                        pgnText: pgnText,
                        positions: positions,
                        analyses: viewModel.analyses,
                        clockTimes: clockTimes,
                        whiteAvatarURL: whiteAvatarURL,
                        blackAvatarURL: blackAvatarURL
                    )
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .navigationTitle("Game Review")
        .task {
            await load()
        }
        .onDisappear {
            // Stop the engine immediately when leaving to save energy
            Task {
                await StockfishEngine.shared.stopIfIdle()
            }
        }
    }

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                PlayerSummaryView(name: game.summary.whitePlayer, rating: game.summary.whiteElo, avatarURL: whiteAvatarURL)
                Spacer()
                Text(game.summary.result)
                    .font(.headline)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Spacer()
                PlayerSummaryView(name: game.summary.blackPlayer, rating: game.summary.blackElo, avatarURL: blackAvatarURL)
            }
            .frame(maxWidth: .infinity)
            HStack(spacing: 6) {
                Text(game.summary.gameDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                TimeControlIcon(timeClass: nil, timeControl: game.summary.timeControl)
            }
        }
    }

    private var accuracySection: some View {
        let accuracies = accuracyByColor()
        return VStack(alignment: .leading, spacing: 8) {
            Text("Accuracy")
                .font(.headline)
            HStack {
                accuracyPill(title: game.summary.whitePlayer, value: accuracies.white)
                Spacer()
                accuracyPill(title: game.summary.blackPlayer, value: accuracies.black)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var classificationSection: some View {
        let counts = classificationCounts()
        return VStack(alignment: .leading, spacing: 8) {
            Text("Move Classifications")
                .font(.headline)
            ForEach(classificationOrder, id: \.self) { label in
                let count = counts[label.lowercased()] ?? (0, 0)
                HStack {
                    Text(label)
                        .frame(width: 110, alignment: .leading)
                    Spacer()
                    Text("\(count.white)")
                        .foregroundColor(classificationColor(label))
                        .frame(width: 24)
                    if let assetName = classificationAssetName(label) {
                        Image(assetName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                    }
                    Text("\(count.black)")
                        .foregroundColor(classificationColor(label))
                        .frame(width: 24)
                }
            }
        }
    }

    private var ratingSection: some View {
        let accuracies = accuracyByColor()
        return VStack(alignment: .leading, spacing: 8) {
            Text("Game Rating")
                .font(.headline)
            HStack {
                ratingPill(value: accuracies.white)
                Spacer()
                ratingPill(value: accuracies.black)
            }
        }
    }

    private var phaseSection: some View {
        let phases = phaseClassifications()
        return VStack(alignment: .leading, spacing: 8) {
            Text("Phase Classifications")
                .font(.headline)
            phaseRow(title: "Opening", white: phases.opening.white, black: phases.opening.black)
            phaseRow(title: "Middlegame", white: phases.middle.white, black: phases.middle.black)
            phaseRow(title: "Endgame", white: phases.end.white, black: phases.end.black)
        }
    }

    private var analysisSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.isAnalyzing {
                HStack {
                    ProgressView("Analyzing...")
                    Button("Cancel") {
                        viewModel.cancel()
                    }
                    .buttonStyle(.bordered)
                }
            }
            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }
            Button(viewModel.analyses.isEmpty ? "Analyze Game" : "Re-analyze") {
                Task {
                    let moveCount = PGNParser.extractMoves(from: pgnText).count
                    let estimatedBytes = Int64(moveCount) * 320
                    let capBytes = Int64(settings.storageCapMB) * 1_048_576
                    try? await GameStore.shared.enforceStorageLimit(extraBytes: estimatedBytes, capBytes: capBytes)
                    viewModel.startAnalysis(pgn: pgnText, gameId: game.id, coachLines: settings.coachLines)
                }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func accuracyPill(title: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value == 0 ? "--" : String(format: "%.1f", value))
                .font(.headline)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func ratingPill(value: Double) -> some View {
        let rating = value == 0 ? "--" : "\(estimatedRating(value))"
        return Text(rating)
            .font(.headline)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func phaseRow(title: String, white: String?, black: String?) -> some View {
        HStack {
            Text(title)
                .frame(width: 110, alignment: .leading)
            Spacer()
            phaseBadge(text: white)
            Spacer()
            phaseBadge(text: black)
        }
    }

    private func phaseBadge(text: String?) -> some View {
        if let text, let assetName = classificationAssetName(text) {
            return AnyView(
                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
            )
        }
        return AnyView(
            Text("-")
                .foregroundColor(.secondary)
        )
    }

    private func load() async {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: game.pgnPath))
            pgnText = String(data: data, encoding: .utf8) ?? ""
            positions = buildPositions(pgn: pgnText)
            clockTimes = PGNParser.extractClockTimes(from: pgnText)
            whiteRating = game.summary.whiteElo ?? parseRating(PGNParser.extractHeader(from: pgnText, key: "WhiteElo"))
            blackRating = game.summary.blackElo ?? parseRating(PGNParser.extractHeader(from: pgnText, key: "BlackElo"))
            await viewModel.loadAnalysis(gameId: game.id)
            await loadAvatars()
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func loadAvatars() async {
        let api = ChessComAPI(token: settings.token)
        async let whitePlayer = try? api.fetchPlayer(username: game.summary.whitePlayer)
        async let blackPlayer = try? api.fetchPlayer(username: game.summary.blackPlayer)
        if let whitePlayer = await whitePlayer, let avatar = whitePlayer.avatar {
            whiteAvatarURL = URL(string: avatar)
        }
        if let blackPlayer = await blackPlayer, let avatar = blackPlayer.avatar {
            blackAvatarURL = URL(string: avatar)
        }
    }

    private func buildPositions(pgn: String) -> [ChessPosition] {
        let moves = PGNParser.extractMoves(from: pgn)
        var position = ChessPosition.startPosition()
        var result = [position]
        for san in moves {
            if let move = try? SANParser.moveFromSAN(san, position: position) {
                position = MoveGenerator.apply(move: move, to: position)
                result.append(position)
            }
        }
        return result
    }

    private func accuracyByColor() -> (white: Double, black: Double) {
        guard !viewModel.analyses.isEmpty else { return (0, 0) }
        let whiteScores = expectedScoreLosses(for: .white, rating: whiteRating)
        let blackScores = expectedScoreLosses(for: .black, rating: blackRating)
        return (accuracyFromLosses(whiteScores), accuracyFromLosses(blackScores))
    }

    private func classificationCounts() -> [String: (white: Int, black: Int)] {
        var counts: [String: (white: Int, black: Int)] = [:]
        for (index, move) in viewModel.analyses.enumerated() {
            let key = move.classification.lowercased()
            let current = counts[key] ?? (0, 0)
            if index % 2 == 0 {
                counts[key] = (current.white + 1, current.black)
            } else {
                counts[key] = (current.white, current.black + 1)
            }
        }
        return counts
    }

    private func estimatedRating(_ accuracy: Double) -> Int {
        min(3000, max(0, Int(accuracy * 4.2)))
    }

    private func phaseClassifications() -> (
        opening: (white: String?, black: String?),
        middle: (white: String?, black: String?),
        end: (white: String?, black: String?)
    ) {
        let count = viewModel.analyses.count
        let openingRange = 0..<min(count, 20)
        let middleStart = min(20, count)
        let middleEnd = min(count, 40)
        let middleRange = middleStart..<middleEnd
        let endStart = min(40, count)
        let endRange = endStart..<count
        return (
            opening: phaseClassification(range: openingRange),
            middle: phaseClassification(range: middleRange),
            end: phaseClassification(range: endRange)
        )
    }

    private func phaseClassification(range: Range<Int>) -> (white: String?, black: String?) {
        guard !range.isEmpty else { return (nil, nil) }
        let moves = viewModel.analyses
        let whiteLosses = range.compactMap { index in
            index < moves.count && index % 2 == 0 ? moves[index].loss : nil
        }
        let blackLosses = range.compactMap { index in
            index < moves.count && index % 2 == 1 ? moves[index].loss : nil
        }
        return (lossToClassification(whiteLosses), lossToClassification(blackLosses))
    }

    private func lossToClassification(_ losses: [Int]) -> String? {
        guard !losses.isEmpty else { return nil }
        let avg = Double(losses.reduce(0, +)) / Double(losses.count)
        if avg <= 15 { return MoveClassification.best.rawValue }
        if avg <= 50 { return MoveClassification.good.rawValue }
        if avg <= 120 { return MoveClassification.inaccuracy.rawValue }
        if avg <= 250 { return MoveClassification.mistake.rawValue }
        return MoveClassification.blunder.rawValue
    }

    private func expectedScoreLosses(for color: PieceColor, rating: Int) -> [Double] {
        viewModel.analyses.enumerated().compactMap { index, move in
            let mover = index % 2 == 0 ? PieceColor.white : PieceColor.black
            guard mover == color else { return nil }
            let before = expectedPoints(evalWhiteCp: move.evalBefore, mover: mover, rating: rating)
            let after = expectedPoints(evalWhiteCp: move.evalAfter, mover: mover, rating: rating)
            return max(0, before - after)
        }
    }

    private func accuracyFromLosses(_ losses: [Double]) -> Double {
        guard !losses.isEmpty else { return 0 }
        let avgLoss = losses.reduce(0, +) / Double(losses.count)
        let score = 100.0 * exp(-avgLoss * 3.2)
        return (score * 10).rounded() / 10.0
    }

    private func expectedPoints(evalWhiteCp: Int, mover: PieceColor, rating: Int) -> Double {
        let signedEval = mover == .white ? evalWhiteCp : -evalWhiteCp
        let evalPawns = max(-10.0, min(10.0, Double(signedEval) / 100.0))
        let clampedRating = max(800, min(2800, rating))
        let slope = 1.0 + (Double(clampedRating - 800) / 2000.0) * 0.7
        let value = 1.0 / (1.0 + exp(-slope * evalPawns))
        return min(max(value, 0.0), 1.0)
    }

    private func parseRating(_ header: String?) -> Int {
        guard let header, let value = Int(header) else { return 1200 }
        return value
    }
}

private struct PlayerSummaryView: View {
    let name: String
    let rating: Int?
    let avatarURL: URL?

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
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image("default")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(name)
                    .font(.headline)
                if let rating {
                    Text("(\(rating))")
                        .font(.caption)
                        .fontWeight(.light)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

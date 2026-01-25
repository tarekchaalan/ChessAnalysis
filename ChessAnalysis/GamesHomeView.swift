import SwiftUI

struct GamesHomeView: View {
    @StateObject private var viewModel = GamesViewModel()
    @ObservedObject var settings: AppSettings
    @State private var segment: Int = 0
    @State private var searchText: String = ""
    @State private var timeControlFilter: TimeControlFilter = .all
    @State private var endFilter: EndFilter = .all
    @State private var resultFilter: ResultFilter = .all
    @State private var colorFilter: ColorFilter = .all
    @State private var moveCountFilter: MoveCountFilter = .all
    @State private var dateFrom: Date? = nil
    @State private var dateTo: Date? = nil
    @State private var showFiltersModal = false
    @State private var showPGNPaste = false
    @State private var pgnInput = ""
    @State private var showPGNError = false
    @State private var showReportComposer = false
    @State private var mailUnavailableAlert = false
    @State private var reportToSend: AnalysisErrorReport?
    @State private var isRefreshing = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("", selection: $segment) {
                    Text("All Games").tag(0)
                    Text("Analyzed Games").tag(1)
                }
                .pickerStyle(.segmented)
                .padding([.top, .horizontal])
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search players", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(10)
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)
                filterBar
                if let error = viewModel.errorMessage, !error.lowercased().contains("cancel") {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(error)
                                .foregroundColor(.red)
                                .font(.caption)
                            if let report = viewModel.lastAnalysisError {
                                Button("Report") {
                                    if MailComposer.canSendMail {
                                        reportToSend = report
                                        showReportComposer = true
                                    } else {
                                        mailUnavailableAlert = true
                                    }
                                }
                                .font(.caption)
                            }
                        }
                        Spacer()
                        Button {
                            viewModel.errorMessage = nil
                            viewModel.lastAnalysisError = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)
                }

                if segment == 0 {
                    remoteList
                } else {
                    downloadedList
                }
                Spacer(minLength: 0)
            }
            .navigationTitle(settings.username.isEmpty ? "Games" : "\(settings.username)'s Games")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showPGNPaste = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    if isRefreshing {
                        ProgressView()
                    } else {
                        Button("Refresh") {
                            Task {
                                isRefreshing = true
                                await refresh()
                                isRefreshing = false
                            }
                        }
                    }
                }
            }
            .task {
                await refresh()
            }
            .alert("Mail is not available on this device.", isPresented: $mailUnavailableAlert) {
                Button("OK", role: .cancel) {}
            }
            .alert("Paste a PGN to import.", isPresented: $showPGNError) {
                Button("OK", role: .cancel) {}
            }
            .sheet(isPresented: $showReportComposer) {
                if let reportToSend {
                    MailComposer(
                        recipients: ["tchaalan23@icloud.com"],
                        subject: "ChessAnalysis PGN Error Report",
                        body: "See attached report.",
                        attachment: MailAttachment(
                            data: Data(reportToSend.reportText.utf8),
                            mimeType: "text/plain",
                            fileName: "chessanalysis-pgn-report.txt"
                        )
                    )
                }
            }
            .sheet(isPresented: $showPGNPaste) {
                NavigationStack {
                    VStack(spacing: 12) {
                        TextEditor(text: $pgnInput)
                            .font(.system(.body, design: .monospaced))
                            .padding(8)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .padding()
                        Spacer()
                    }
                    .navigationTitle("Paste PGN")
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Cancel") {
                                showPGNPaste = false
                                pgnInput = ""
                            }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Import") {
                                if pgnInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    showPGNError = true
                                    return
                                }
                                Task {
                                    await viewModel.importPGN(pgnInput, settings: settings)
                                    pgnInput = ""
                                    showPGNPaste = false
                                    segment = 1 // Switch to Analyzed Games tab
                                }
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showFiltersModal) {
                FiltersModal(
                    timeControlFilter: $timeControlFilter,
                    endFilter: $endFilter,
                    resultFilter: $resultFilter,
                    colorFilter: $colorFilter,
                    moveCountFilter: $moveCountFilter,
                    dateFrom: $dateFrom,
                    dateTo: $dateTo
                )
            }
        }
    }

    private var remoteList: some View {
        Group {
            if settings.username.isEmpty {
                LoginView(settings: settings) {
                    Task { await refresh() }
                }
            } else if viewModel.isLoading {
                ProgressView("Fetching games...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.remoteGames.isEmpty {
                Text("No games found.")
                    .foregroundColor(.secondary)
            } else {
                let downloadedIndex = Dictionary(uniqueKeysWithValues: viewModel.downloadedGames.map { ($0.remoteId, $0) })
                let filtered = viewModel.remoteGames.filter { game in
                    let moveCount = viewModel.remoteMoveCounts[game.id]
                    return matchesSearch(
                        white: game.whitePlayer,
                        black: game.blackPlayer
                    )
                    && matchesTimeControl(timeClass: game.timeClass, timeControl: game.timeControl)
                    && matchesEndType(remoteId: game.id, fallbackPGN: game.pgn)
                    && matchesDate(gameDate: game.gameDate)
                    && matchesResult(result: game.result, white: game.whitePlayer, black: game.blackPlayer)
                    && matchesColor(white: game.whitePlayer, black: game.blackPlayer)
                    && matchesMoveCount(moveCount: moveCount)
                }
                List {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, game in
                        let showSeparator = index == 0 || filtered[index - 1].gameDate != game.gameDate
                        if showSeparator {
                            dateSeparator(game.gameDate)
                        }
                        let downloadedGame = downloadedIndex[game.id]
                        let isAnalyzing = downloadedGame.map { viewModel.analyzingIds.contains($0.id) } ?? false
                        let isFullyAnalyzed = downloadedGame?.lastAnalyzedAt != nil
                        let isIncomplete = downloadedGame != nil && !isFullyAnalyzed && !isAnalyzing
                        let progress = downloadedGame.flatMap { viewModel.analyzingProgress[$0.id] }
                        let moveCount = viewModel.remoteMoveCounts[game.id]
                        let endType = viewModel.remoteEndTypes[game.id] ?? GameEndType.fromPGN(game.pgn)
                        RemoteGameRow(
                            game: game,
                            username: settings.username,
                            isFullyAnalyzed: isFullyAnalyzed,
                            isIncomplete: isIncomplete,
                            isDownloading: viewModel.downloadingIds.contains(game.id),
                            isAnalyzing: isAnalyzing,
                            progressPercent: progress,
                            moveCount: moveCount,
                            endType: endType,
                            onDownload: {
                                Task { await viewModel.download(game: game, settings: settings) }
                            },
                            onRetry: {
                                if let gameMetadata = downloadedGame {
                                    Task { await viewModel.retryAnalysis(gameId: gameMetadata.id, settings: settings) }
                                }
                            }
                        )
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var downloadedList: some View {
        Group {
            if viewModel.downloadedGames.isEmpty {
                Text("No downloaded games yet.")
                    .foregroundColor(.secondary)
            } else {
                // Show all downloaded games: fully analyzed, currently analyzing, or incomplete
                let analyzedGames = viewModel.downloadedGames
                let filtered = analyzedGames.filter { game in
                    let moveCount = viewModel.downloadedMoveCounts[game.id]
                    return matchesSearch(
                        white: game.summary.whitePlayer,
                        black: game.summary.blackPlayer
                    )
                    && matchesTimeControl(timeClass: nil, timeControl: game.summary.timeControl)
                    && matchesEndType(gameId: game.id, pgnPath: game.pgnPath)
                    && matchesDate(gameDate: game.summary.gameDate)
                    && matchesResult(result: game.summary.result, white: game.summary.whitePlayer, black: game.summary.blackPlayer)
                    && matchesColor(white: game.summary.whitePlayer, black: game.summary.blackPlayer)
                    && matchesMoveCount(moveCount: moveCount)
                }
                if filtered.isEmpty {
                    Text("No analyzed games yet.")
                        .foregroundColor(.secondary)
                } else {
                    List {
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { index, game in
                            let showSeparator = index == 0 || filtered[index - 1].summary.gameDate != game.summary.gameDate
                            if showSeparator {
                                dateSeparator(game.summary.gameDate)
                            }
                            let isAnalyzing = viewModel.analyzingIds.contains(game.id)
                            let isIncomplete = game.lastAnalyzedAt == nil && !isAnalyzing
                            NavigationLink {
                                GameDetailView(game: game, settings: settings)
                            } label: {
                                let progress = viewModel.analyzingProgress[game.id]
                                let moveCount = viewModel.downloadedMoveCounts[game.id]
                                let endType = viewModel.downloadedEndTypes[game.id]
                                DownloadedGameRow(
                                    game: game,
                                    username: settings.username,
                                    pgnPath: game.pgnPath,
                                    isIncomplete: isIncomplete,
                                    progressPercent: progress,
                                    moveCount: moveCount,
                                    endType: endType,
                                    onRetry: {
                                        Task { await viewModel.retryAnalysis(gameId: game.id, settings: settings) }
                                    }
                                )
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task { await viewModel.deleteAnalysis(gameId: game.id) }
                                } label: {
                                    Text("Delete")
                                }
                                .disabled(isAnalyzing)
                                if isIncomplete {
                                    Button {
                                        Task { await viewModel.retryAnalysis(gameId: game.id, settings: settings) }
                                    } label: {
                                        Text("Retry")
                                    }
                                    .tint(.orange)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
        }
    }

    private func refresh() async {
        await viewModel.loadDownloadedGames()
        await viewModel.loadRemoteGames(username: settings.username, token: settings.token)
    }
}

struct RemoteGameRow: View {
    let game: RemoteGame
    let username: String
    let isFullyAnalyzed: Bool
    let isIncomplete: Bool
    let isDownloading: Bool
    let isAnalyzing: Bool
    let progressPercent: Int?
    let moveCount: Int?
    let endType: GameEndType
    let onDownload: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TimeControlIcon(timeClass: game.timeClass, timeControl: game.timeControl)
                playerNamesWithRatings
                Spacer()
                Text(game.result)
                    .font(.subheadline)
            }
            HStack {
                Text("\(moveCount.map(String.init) ?? "--") moves")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let outcomeText = gameOutcomeText {
                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(outcomeText)
                        .font(.caption)
                        .foregroundColor(outcomeColor)
                }
                Spacer()
                statusIcon
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusIcon: some View {
        if isDownloading || isAnalyzing {
            let percent = progressPercent ?? 0
            Text("\(percent)%")
                .font(.caption)
                .foregroundColor(.secondary)
        } else if isFullyAnalyzed {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        } else if isIncomplete {
            // Downloaded but analysis was interrupted - show retry button
            Button {
                onRetry()
            } label: {
                Image(systemName: "arrow.clockwise.circle")
                    .foregroundColor(.orange)
            }
            .buttonStyle(.plain)
        } else {
            // Not downloaded at all
            Button {
                onDownload()
            } label: {
                Image(systemName: "arrow.down.circle")
            }
            .buttonStyle(.plain)
        }
    }

    private var gameOutcomeText: String? {
        let result = game.result
        if result == "1/2-1/2" { return "Draw" }
        guard result != "*" else { return nil }
        let whiteWon = result == "1-0"
        let userIsWhite = username.lowercased() == game.whitePlayer.lowercased()
        let userIsBlack = username.lowercased() == game.blackPlayer.lowercased()
        let userWon: Bool?
        if userIsWhite {
            userWon = whiteWon
        } else if userIsBlack {
            userWon = !whiteWon
        } else {
            userWon = nil
        }
        let reason = endType.displayName
        if let userWon {
            return userWon ? "Won by \(reason)" : "Lost by \(reason)"
        } else {
            let winner = whiteWon ? game.whitePlayer : game.blackPlayer
            return "\(winner) won by \(reason)"
        }
    }

    private var outcomeColor: Color {
        let result = game.result
        if result == "1/2-1/2" || result == "*" { return .secondary }
        let whiteWon = result == "1-0"
        let userIsWhite = username.lowercased() == game.whitePlayer.lowercased()
        let userIsBlack = username.lowercased() == game.blackPlayer.lowercased()
        if userIsWhite {
            return whiteWon ? .green : .red
        } else if userIsBlack {
            return whiteWon ? .red : .green
        }
        return .secondary
    }

    private var playerNamesWithRatings: some View {
        HStack(spacing: 2) {
            Text(game.whitePlayer)
                .font(.headline)
            if let elo = game.whiteElo {
                Text("(\(elo))")
                    .font(.caption)
                    .fontWeight(.light)
                    .foregroundColor(.secondary)
            }
            Text(" vs ")
                .font(.headline)
            Text(game.blackPlayer)
                .font(.headline)
            if let elo = game.blackElo {
                Text("(\(elo))")
                    .font(.caption)
                    .fontWeight(.light)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct DownloadedGameRow: View {
    let game: GameMetadata
    let username: String
    let pgnPath: String
    let isIncomplete: Bool
    let progressPercent: Int?
    let moveCount: Int?
    let endType: GameEndType?
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TimeControlIcon(timeClass: nil, timeControl: game.summary.timeControl)
                playerNamesWithRatings
                Spacer()
                Text(game.summary.result)
                    .font(.subheadline)
            }
            HStack {
                Text("\(moveCount.map(String.init) ?? "--") moves")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let outcomeText = gameOutcomeText {
                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(outcomeText)
                        .font(.caption)
                        .foregroundColor(outcomeColor)
                }
                Spacer()
                if let progressPercent {
                    Text("Analyzing: \(progressPercent)%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if isIncomplete {
                    HStack(spacing: 4) {
                        Text("Incomplete")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Button {
                            onRetry()
                        } label: {
                            Image(systemName: "arrow.clockwise.circle")
                                .foregroundColor(.orange)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var gameOutcomeText: String? {
        let result = game.summary.result
        if result == "1/2-1/2" { return "Draw" }
        guard result != "*" else { return nil }
        let whiteWon = result == "1-0"
        let userIsWhite = username.lowercased() == game.summary.whitePlayer.lowercased()
        let userIsBlack = username.lowercased() == game.summary.blackPlayer.lowercased()
        let userWon: Bool?
        if userIsWhite {
            userWon = whiteWon
        } else if userIsBlack {
            userWon = !whiteWon
        } else {
            userWon = nil
        }
        let reason = endType?.displayName ?? "resignation"
        if let userWon {
            return userWon ? "Won by \(reason)" : "Lost by \(reason)"
        } else {
            let winner = whiteWon ? game.summary.whitePlayer : game.summary.blackPlayer
            return "\(winner) won by \(reason)"
        }
    }

    private var outcomeColor: Color {
        let result = game.summary.result
        if result == "1/2-1/2" || result == "*" { return .secondary }
        let whiteWon = result == "1-0"
        let userIsWhite = username.lowercased() == game.summary.whitePlayer.lowercased()
        let userIsBlack = username.lowercased() == game.summary.blackPlayer.lowercased()
        if userIsWhite {
            return whiteWon ? .green : .red
        } else if userIsBlack {
            return whiteWon ? .red : .green
        }
        return .secondary
    }

    private var playerNamesWithRatings: some View {
        HStack(spacing: 2) {
            Text(game.summary.whitePlayer)
                .font(.headline)
            if let elo = game.summary.whiteElo {
                Text("(\(elo))")
                    .font(.caption)
                    .fontWeight(.light)
                    .foregroundColor(.secondary)
            }
            Text(" vs ")
                .font(.headline)
            Text(game.summary.blackPlayer)
                .font(.headline)
            if let elo = game.summary.blackElo {
                Text("(\(elo))")
                    .font(.caption)
                    .fontWeight(.light)
                    .foregroundColor(.secondary)
            }
        }
    }
}

fileprivate enum TimeControlFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case bullet = "Bullet"
    case blitz = "Blitz"
    case rapid = "Rapid"

    var id: String { rawValue }
}

fileprivate enum ResultFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case win = "Win"
    case loss = "Loss"
    case draw = "Draw"

    var id: String { rawValue }
}

fileprivate enum ColorFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case white = "White"
    case black = "Black"

    var id: String { rawValue }
}

fileprivate enum MoveCountFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case short = "Short (<30)"
    case medium = "Medium"
    case long = "Long (>60)"

    var id: String { rawValue }
}

// GameEndType is declared in GameEndType.swift

private extension GamesHomeView {
    func dateSeparator(_ dateString: String) -> some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(height: 1)
            Text(formatDateForSeparator(dateString))
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .fixedSize()
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(height: 1)
        }
        .padding(.vertical, 8)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
    }

    func formatDateForSeparator(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let date = formatter.date(from: dateString) else { return dateString }
        let display = DateFormatter()
        display.dateFormat = "MMMM d, yyyy"
        return display.string(from: date)
    }

    var activeFilterCount: Int {
        var count = 0
        if timeControlFilter != .all { count += 1 }
        if endFilter != .all { count += 1 }
        if resultFilter != .all { count += 1 }
        if colorFilter != .all { count += 1 }
        if moveCountFilter != .all { count += 1 }
        if dateFrom != nil || dateTo != nil { count += 1 }
        return count
    }

    var filterBar: some View {
        HStack {
            Button {
                showFiltersModal = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    Text("Filters")
                    if activeFilterCount > 0 {
                        Text("\(activeFilterCount)")
                            .font(.caption2.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                    }
                }
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.12))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            Spacer()
            if activeFilterCount > 0 {
                Button("Clear All") {
                    timeControlFilter = .all
                    endFilter = .all
                    resultFilter = .all
                    colorFilter = .all
                    moveCountFilter = .all
                    dateFrom = nil
                    dateTo = nil
                }
                .font(.caption)
                .foregroundColor(.accentColor)
            }
        }
        .padding(.horizontal)
    }

    func matchesSearch(white: String, black: String) -> Bool {
        searchText.isEmpty
            || white.localizedCaseInsensitiveContains(searchText)
            || black.localizedCaseInsensitiveContains(searchText)
    }

    func matchesTimeControl(timeClass: String?, timeControl: String) -> Bool {
        guard timeControlFilter != .all else { return true }
        if let timeClass {
            return timeClass.localizedCaseInsensitiveContains(timeControlFilter.rawValue)
        }
        let baseSeconds = timeControl.split(separator: "+").first.flatMap { Int($0) } ?? 0
        switch timeControlFilter {
        case .bullet: return baseSeconds > 0 && baseSeconds <= 180
        case .blitz: return baseSeconds > 180 && baseSeconds <= 600
        case .rapid: return baseSeconds > 600
        case .all: return true
        }
    }

    func matchesEndType(remoteId: String, fallbackPGN: String) -> Bool {
        guard endFilter != .all else { return true }
        if let endType = _viewModel.wrappedValue.remoteEndTypes[remoteId] {
            return endType.matches(filter: endFilter)
        }
        let endType = GameEndType.fromPGN(fallbackPGN)
        return endType.matches(filter: endFilter)
    }

    func matchesEndType(gameId: UUID, pgnPath: String) -> Bool {
        guard endFilter != .all else { return true }
        if let endType = _viewModel.wrappedValue.downloadedEndTypes[gameId] {
            return endType.matches(filter: endFilter)
        }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: pgnPath)),
              let pgn = String(data: data, encoding: .utf8) else {
            return true
        }
        return GameEndType.fromPGN(pgn).matches(filter: endFilter)
    }

    func matchesDate(gameDate: String) -> Bool {
        guard dateFrom != nil || dateTo != nil else { return true }
        guard let date = parseGameDate(gameDate) else { return false }
        if let from = dateFrom, date < Calendar.current.startOfDay(for: from) { return false }
        if let to = dateTo {
            let endOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: to) ?? to
            if date > endOfDay { return false }
        }
        return true
    }

    func matchesResult(result: String, white: String, black: String) -> Bool {
        guard resultFilter != .all else { return true }
        let username = settings.username.lowercased()
        let userIsWhite = username == white.lowercased()
        let userIsBlack = username == black.lowercased()

        switch resultFilter {
        case .all:
            return true
        case .win:
            if result == "1-0" && userIsWhite { return true }
            if result == "0-1" && userIsBlack { return true }
            return false
        case .loss:
            if result == "0-1" && userIsWhite { return true }
            if result == "1-0" && userIsBlack { return true }
            return false
        case .draw:
            return result == "1/2-1/2"
        }
    }

    func matchesColor(white: String, black: String) -> Bool {
        guard colorFilter != .all else { return true }
        let username = settings.username.lowercased()

        switch colorFilter {
        case .all:
            return true
        case .white:
            return username == white.lowercased()
        case .black:
            return username == black.lowercased()
        }
    }

    func matchesMoveCount(moveCount: Int?) -> Bool {
        guard moveCountFilter != .all else { return true }
        guard let count = moveCount else { return true }

        switch moveCountFilter {
        case .all:
            return true
        case .short:
            return count < 30
        case .medium:
            return count >= 30 && count <= 60
        case .long:
            return count > 60
        }
    }

    func parseGameDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: value)
    }
}

// MARK: - Filters Modal

private struct FiltersModal: View {
    @Binding var timeControlFilter: TimeControlFilter
    @Binding var endFilter: EndFilter
    @Binding var resultFilter: ResultFilter
    @Binding var colorFilter: ColorFilter
    @Binding var moveCountFilter: MoveCountFilter
    @Binding var dateFrom: Date?
    @Binding var dateTo: Date?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Time Control") {
                    Picker("Time Control", selection: $timeControlFilter) {
                        ForEach(TimeControlFilter.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Result") {
                    Picker("Result", selection: $resultFilter) {
                        ForEach(ResultFilter.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Color Played") {
                    Picker("Color", selection: $colorFilter) {
                        ForEach(ColorFilter.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Game Length") {
                    Picker("Move Count", selection: $moveCountFilter) {
                        ForEach(MoveCountFilter.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Game Ending") {
                    Picker("End Type", selection: $endFilter) {
                        ForEach(EndFilter.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Date Range") {
                    DatePicker(
                        "From",
                        selection: Binding(
                            get: { dateFrom ?? Date() },
                            set: { dateFrom = $0 }
                        ),
                        displayedComponents: [.date]
                    )

                    DatePicker(
                        "To",
                        selection: Binding(
                            get: { dateTo ?? Date() },
                            set: { dateTo = $0 }
                        ),
                        displayedComponents: [.date]
                    )

                    if dateFrom != nil || dateTo != nil {
                        Button("Clear Date Range") {
                            dateFrom = nil
                            dateTo = nil
                        }
                        .foregroundColor(.red)
                    }
                }

                Section {
                    Button("Reset All Filters") {
                        timeControlFilter = .all
                        endFilter = .all
                        resultFilter = .all
                        colorFilter = .all
                        moveCountFilter = .all
                        dateFrom = nil
                        dateTo = nil
                    }
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

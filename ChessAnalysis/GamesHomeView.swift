import SwiftUI

struct GamesHomeView: View {
    @StateObject private var viewModel = GamesViewModel()
    @ObservedObject var settings: AppSettings
    @State private var segment: Int = 0
    @State private var searchText: String = ""
    @State private var timeControlFilter: TimeControlFilter = .all
    @State private var endFilter: EndFilter = .all
    @State private var showDateFilter = false
    @State private var dateFrom: Date? = nil
    @State private var dateTo: Date? = nil
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
                let downloadedIndex = Dictionary(uniqueKeysWithValues: viewModel.downloadedGames.map { ($0.remoteId, $0.id) })
                let filtered = viewModel.remoteGames.filter { game in
                    matchesSearch(
                        white: game.whitePlayer,
                        black: game.blackPlayer
                    )
                    && matchesTimeControl(timeClass: game.timeClass, timeControl: game.timeControl)
                    && matchesEndType(remoteId: game.id, fallbackPGN: game.pgn)
                    && matchesDate(gameDate: game.gameDate)
                }
                List {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, game in
                        let showSeparator = index == 0 || filtered[index - 1].gameDate != game.gameDate
                        if showSeparator {
                            dateSeparator(game.gameDate)
                        }
                        let isDownloaded = downloadedIndex[game.id] != nil
                        let isAnalyzing = downloadedIndex[game.id].map { viewModel.analyzingIds.contains($0) } ?? false
                        let progress = downloadedIndex[game.id].flatMap { viewModel.analyzingProgress[$0] }
                        let moveCount = viewModel.remoteMoveCounts[game.id]
                        let endType = viewModel.remoteEndTypes[game.id] ?? GameEndType.fromPGN(game.pgn)
                        RemoteGameRow(
                            game: game,
                            username: settings.username,
                            isDownloaded: isDownloaded,
                            isDownloading: viewModel.downloadingIds.contains(game.id),
                            isAnalyzing: isAnalyzing,
                            progressPercent: progress,
                            moveCount: moveCount,
                            endType: endType
                        ) {
                            Task { await viewModel.download(game: game, settings: settings) }
                        }
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
                let analyzedGames = viewModel.downloadedGames.filter {
                    $0.lastAnalyzedAt != nil || viewModel.analyzingIds.contains($0.id)
                }
                let filtered = analyzedGames.filter { game in
                    matchesSearch(
                        white: game.summary.whitePlayer,
                        black: game.summary.blackPlayer
                    )
                    && matchesTimeControl(timeClass: nil, timeControl: game.summary.timeControl)
                    && matchesEndType(gameId: game.id, pgnPath: game.pgnPath)
                    && matchesDate(gameDate: game.summary.gameDate)
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
                                    progressPercent: progress,
                                    moveCount: moveCount,
                                    endType: endType
                                )
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task { await viewModel.deleteAnalysis(gameId: game.id) }
                                } label: {
                                    Text("Delete Analysis")
                                }
                                .disabled(viewModel.analyzingIds.contains(game.id))
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
    let isDownloaded: Bool
    let isDownloading: Bool
    let isAnalyzing: Bool
    let progressPercent: Int?
    let moveCount: Int?
    let endType: GameEndType
    let onDownload: () -> Void

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
                if isDownloading || isAnalyzing {
                    let percent = progressPercent ?? 0
                    Text("\(percent)%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if isDownloaded {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Button {
                        onDownload()
                    } label: {
                        Image(systemName: "arrow.down.circle")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 2)
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
    let progressPercent: Int?
    let moveCount: Int?
    let endType: GameEndType?

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

    var filterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Menu {
                        Picker("Time Control", selection: $timeControlFilter) {
                            ForEach(TimeControlFilter.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                    } label: {
                        filterChip(label: "Time: \(timeControlFilter.rawValue)")
                    }
                    Menu {
                        Picker("Game End", selection: $endFilter) {
                            ForEach(EndFilter.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                    } label: {
                        filterChip(label: "End: \(endFilter.rawValue)")
                    }
                    Button {
                        showDateFilter.toggle()
                    } label: {
                        filterChip(label: showDateFilter ? "Date: Custom" : "Date: Any")
                    }
                }
                .padding(.horizontal)
            }

            if showDateFilter {
                HStack(spacing: 12) {
                    DatePicker("From", selection: Binding(
                        get: { dateFrom ?? Date() },
                        set: { dateFrom = $0 }
                    ), displayedComponents: [.date])
                    .datePickerStyle(.compact)

                    DatePicker("To", selection: Binding(
                        get: { dateTo ?? Date() },
                        set: { dateTo = $0 }
                    ), displayedComponents: [.date])
                    .datePickerStyle(.compact)

                    Button("Clear") {
                        dateFrom = nil
                        dateTo = nil
                        showDateFilter = false
                    }
                    .font(.caption)
                }
                .padding(.horizontal)
            }
        }
    }

    func filterChip(label: String) -> some View {
        Text(label)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.12))
            .clipShape(Capsule())
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

    func parseGameDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: value)
    }
}

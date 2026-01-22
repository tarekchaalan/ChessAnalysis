import Foundation
import Combine

@MainActor
final class GamesViewModel: ObservableObject {
    @Published var remoteGames: [RemoteGame] = []
    @Published var downloadedGames: [GameMetadata] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var downloadingIds: Set<String> = []
    @Published var analyzingIds: Set<UUID> = []
    @Published var analyzingProgress: [UUID: Int] = [:]
    @Published var lastAnalysisError: AnalysisErrorReport?
    @Published var remoteMoveCounts: [String: Int] = [:]
    @Published var remoteEndTypes: [String: GameEndType] = [:]
    @Published var downloadedMoveCounts: [UUID: Int] = [:]
    @Published var downloadedEndTypes: [UUID: GameEndType] = [:]

    private let store = GameStore.shared
    private let analyzer = AnalysisService.shared
    private let cache = RemoteGamesCache()
    private let queue = AnalysisQueue.shared
    private let latestImportedKey = "chesscom.latestImported"

    func loadRemoteGames(username: String, token: String) async {
        guard !username.isEmpty else {
            remoteGames = []
            return
        }
        let cached = cache.load(username: username) ?? []
        if !cached.isEmpty {
            remoteGames = cached
        }
        isLoading = remoteGames.isEmpty
        do {
            let api = ChessComAPI(token: token.isEmpty ? nil : token)
            // Only use 'since' optimization if we have cached games
            let since = cached.isEmpty ? nil : latestImportedDate()
            let newGames = try await api.fetchAllGames(username: username, limitMonths: nil, since: since)
            // Merge new games with cached games, avoiding duplicates
            let existingIds = Set(cached.map { $0.id })
            let uniqueNewGames = newGames.filter { !existingIds.contains($0.id) }
            let allGames = (cached + uniqueNewGames).sorted { ($0.endTime ?? .distantPast) > ($1.endTime ?? .distantPast) }
            remoteGames = allGames
            cache.save(username: username, games: allGames)
            computeRemoteMetadata(games: allGames)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func loadDownloadedGames() async {
        do {
            let games = try await store.fetchDownloadedGames()
            downloadedGames = games.sorted { lhs, rhs in
                let lhsDate = parseGameDate(lhs.summary.gameDate) ?? lhs.downloadedAt
                let rhsDate = parseGameDate(rhs.summary.gameDate) ?? rhs.downloadedAt
                return lhsDate > rhsDate
            }
            computeDownloadedMetadata(games: downloadedGames)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteAnalysis(gameId: UUID) async {
        do {
            try await store.deleteAnalysis(gameId: gameId)
            await loadDownloadedGames()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importPGN(_ pgn: String, settings: AppSettings) async {
        let trimmed = pgn.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let remoteGame = remoteGameFromPGN(trimmed)
        await download(game: remoteGame, settings: settings)
    }

    func download(game: RemoteGame, settings: AppSettings) async {
        do {
            guard !downloadingIds.contains(game.id),
                  !downloadedGames.contains(where: { $0.remoteId == game.id }) else {
                return
            }
            downloadingIds.insert(game.id)
            lastAnalysisError = nil
            let pgnData = Data(game.pgn.utf8)
            let capBytes = Int64(settings.storageCapMB) * 1_048_576
            try await store.enforceStorageLimit(extraBytes: Int64(pgnData.count), capBytes: capBytes)
            let metadata = try await store.saveDownloadedGame(remote: game, pgnData: pgnData)
            await loadDownloadedGames()
            downloadingIds.remove(game.id)
            analyzingIds.insert(metadata.id)
            analyzingProgress[metadata.id] = 0
            updateLatestImportedDateIfNeeded(for: game)
            await queue.enqueue { [weak self] in
                guard let self else { return }
                await self.analyzeDownloadedGame(game: metadata, pgn: game.pgn, coachLines: settings.coachLines)
            }
        } catch is CancellationError {
            return
        } catch {
            downloadingIds.remove(game.id)
            errorMessage = error.localizedDescription
        }
    }

    private func analyzeDownloadedGame(game: GameMetadata, pgn: String, coachLines: Bool) async {
        do {
            let existing = try await store.fetchAnalysis(gameId: game.id)
            guard existing.isEmpty else { return }
            let moves = PGNParser.extractMoves(from: pgn)
            if moves.isEmpty {
                try await store.replaceAnalysis(gameId: game.id, analyses: [])
                analyzingIds.remove(game.id)
                analyzingProgress.removeValue(forKey: game.id)
                await loadDownloadedGames()
                return
            }
            lastAnalysisError = nil
            _ = try await analyzer.analyzeGame(
                pgn: pgn,
                gameId: game.id,
                coachLines: coachLines,
                progress: { [weak self] completed, total in
                    guard let self else { return }
                    let percent = Int((Double(completed) / Double(max(total, 1))) * 100.0)
                    Task { @MainActor in
                        self.analyzingProgress[game.id] = min(100, max(0, percent))
                    }
                }
            )
            analyzingIds.remove(game.id)
            analyzingProgress.removeValue(forKey: game.id)
            lastAnalysisError = nil
            await loadDownloadedGames()
        } catch is CancellationError {
            analyzingIds.remove(game.id)
            analyzingProgress.removeValue(forKey: game.id)
            return
        } catch {
            analyzingIds.remove(game.id)
            analyzingProgress.removeValue(forKey: game.id)
            if let message = analysisErrorMessage(for: error) {
                errorMessage = message
                lastAnalysisError = AnalysisErrorReport(
                    gameId: game.id,
                    remoteId: game.remoteId,
                    message: message,
                    pgn: pgn
                )
            }
        }
    }

    private func analysisErrorMessage(for error: Error) -> String? {
        if error is CancellationError { return nil }
        let desc = error.localizedDescription.lowercased()
        if desc.contains("cancel") { return nil }
        if let sanError = error as? SANError {
            return sanError.localizedDescription
        }
        return error.localizedDescription
    }

    private func parseGameDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: value)
    }

    private func computeRemoteMetadata(games: [RemoteGame]) {
        Task.detached { [games] in
            let parsed = await MainActor.run {
                games.map { game in
                    (game.id,
                     PGNParser.extractMoves(from: game.pgn).count,
                     GameEndType.fromPGN(game.pgn))
                }
            }
            let moveCounts = Dictionary(uniqueKeysWithValues: parsed.map { ($0.0, $0.1) })
            let endTypes = Dictionary(uniqueKeysWithValues: parsed.map { ($0.0, $0.2) })
            await MainActor.run {
                self.remoteMoveCounts.merge(moveCounts) { _, new in new }
                self.remoteEndTypes.merge(endTypes) { _, new in new }
            }
        }
    }

    private func computeDownloadedMetadata(games: [GameMetadata]) {
        Task.detached { [games] in
            let parsed = await MainActor.run {
                games.compactMap { game -> (UUID, Int, GameEndType)? in
                    guard let data = try? Data(contentsOf: URL(fileURLWithPath: game.pgnPath)),
                          let pgn = String(data: data, encoding: .utf8) else { return nil }
                    return (game.id,
                            PGNParser.extractMoves(from: pgn).count,
                            GameEndType.fromPGN(pgn))
                }
            }
            let moveCounts = Dictionary(uniqueKeysWithValues: parsed.map { ($0.0, $0.1) })
            let endTypes = Dictionary(uniqueKeysWithValues: parsed.map { ($0.0, $0.2) })
            await MainActor.run {
                self.downloadedMoveCounts.merge(moveCounts) { _, new in new }
                self.downloadedEndTypes.merge(endTypes) { _, new in new }
            }
        }
    }

    private func latestImportedDate() -> Date? {
        let timestamp = UserDefaults.standard.double(forKey: latestImportedKey)
        if timestamp == 0 { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    private func updateLatestImportedDateIfNeeded(for game: RemoteGame) {
        guard !game.id.hasPrefix("local-") else { return }
        let gameDate = game.endTime ?? parseGameDate(game.gameDate)
        guard let gameDate else { return }
        let current = latestImportedDate() ?? .distantPast
        if gameDate > current {
            UserDefaults.standard.set(gameDate.timeIntervalSince1970, forKey: latestImportedKey)
        }
    }

    private func remoteGameFromPGN(_ pgn: String) -> RemoteGame {
        let white = PGNParser.extractHeader(from: pgn, key: "White") ?? "White"
        let black = PGNParser.extractHeader(from: pgn, key: "Black") ?? "Black"
        let whiteEloStr = PGNParser.extractHeader(from: pgn, key: "WhiteElo")
        let blackEloStr = PGNParser.extractHeader(from: pgn, key: "BlackElo")
        let result = PGNParser.extractHeader(from: pgn, key: "Result") ?? "*"
        let gameDate = PGNParser.extractHeader(from: pgn, key: "Date") ?? ""
        let timeControl = PGNParser.extractHeader(from: pgn, key: "TimeControl") ?? ""
        let timeClass = timeClassFrom(timeControl)
        return RemoteGame(
            id: "local-\(UUID().uuidString)",
            pgn: pgn,
            whitePlayer: white,
            blackPlayer: black,
            whiteElo: whiteEloStr.flatMap { Int($0) },
            blackElo: blackEloStr.flatMap { Int($0) },
            result: result,
            gameDate: gameDate,
            timeControl: timeControl,
            timeClass: timeClass,
            endTime: nil,
            url: ""
        )
    }

    private func timeClassFrom(_ timeControl: String) -> String {
        let baseSeconds = timeControl.split(separator: "+").first.flatMap { Int($0) } ?? 0
        if baseSeconds == 0 { return "" }
        if baseSeconds <= 180 { return "bullet" }
        if baseSeconds <= 600 { return "blitz" }
        if baseSeconds <= 1800 { return "rapid" }
        return "classical"
    }
}

struct AnalysisErrorReport: Hashable {
    let gameId: UUID
    let remoteId: String
    let message: String
    let pgn: String

    var reportText: String {
        var lines: [String] = []
        lines.append("ChessAnalysis PGN Error Report")
        lines.append("Game ID: \(gameId.uuidString)")
        lines.append("Remote ID: \(remoteId)")
        lines.append("Error: \(message)")
        lines.append("")
        lines.append("PGN:")
        lines.append(pgn)
        return lines.joined(separator: "\n")
    }
}

private struct RemoteGamesCache {
    private struct Payload: Codable {
        let username: String
        let updatedAt: Date
        let games: [RemoteGame]
    }

    func load(username: String) -> [RemoteGame]? {
        guard let url = cacheURL(username: username),
              let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let payload = try? decoder.decode(Payload.self, from: data),
              payload.username == username.lowercased() else { return nil }
        return payload.games
    }

    func save(username: String, games: [RemoteGame]) {
        guard let url = cacheURL(username: username) else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let payload = Payload(username: username.lowercased(), updatedAt: Date(), games: games)
        guard let data = try? encoder.encode(payload) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func cacheURL(username: String) -> URL? {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let safe = username.lowercased().replacingOccurrences(of: "/", with: "_")
        return dir.appendingPathComponent("remote_games_\(safe).json")
    }
}

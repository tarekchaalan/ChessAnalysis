import Foundation

struct ChessComAPI {
    private let baseURL = URL(string: "https://api.chess.com/pub")!
    private let session: URLSession
    private let token: String?

    init(token: String? = nil) {
        self.token = token
        let configuration = URLSessionConfiguration.default
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Local Chess Analyzer iOS/1.0"
        ]
        session = URLSession(configuration: configuration)
    }

    func fetchMonthlyArchives(username: String) async throws -> [URL] {
        let url = baseURL.appendingPathComponent("player/\(username.lowercased())/games/archives")
        var request = URLRequest(url: url)
        addAuthHeader(to: &request)
        let (data, _) = try await session.data(for: request)
        let decoder = JSONDecoder()
        let response = try decoder.decode(ArchivesResponse.self, from: data)
        return response.archives.compactMap { URL(string: $0) }
    }

    func fetchGamesFromArchive(_ archiveURL: URL) async throws -> [RemoteGame] {
        var request = URLRequest(url: archiveURL)
        addAuthHeader(to: &request)
        let (data, _) = try await session.data(for: request)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let response = try decoder.decode(ArchiveGamesResponse.self, from: data)
        return response.games.map { mapRemoteGame($0) }
    }

    func fetchAllGames(username: String, limitMonths: Int?, since: Date? = nil) async throws -> [RemoteGame] {
        var archives = try await fetchMonthlyArchives(username: username)
        if let since {
            archives = archives.filter { archiveIsOnOrAfter(archiveURL: $0, date: since) }
        }
        if let limitMonths, limitMonths > 0, archives.count > limitMonths {
            archives = Array(archives.suffix(limitMonths))
        }

        var allGames: [RemoteGame] = []
        for archive in archives {
            let games = try await fetchGamesFromArchive(archive)
            if let since {
                allGames.append(contentsOf: games.filter { ($0.endTime ?? .distantPast) >= since })
            } else {
                allGames.append(contentsOf: games)
            }
        }
        return allGames
    }

    func fetchPlayer(username: String) async throws -> ChessComPlayer {
        let url = baseURL.appendingPathComponent("player/\(username.lowercased())")
        var request = URLRequest(url: url)
        addAuthHeader(to: &request)
        let (data, _) = try await session.data(for: request)
        let decoder = JSONDecoder()
        return try decoder.decode(ChessComPlayer.self, from: data)
    }

    private func addAuthHeader(to request: inout URLRequest) {
        guard let token, !token.isEmpty else { return }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    private func archiveIsOnOrAfter(archiveURL: URL, date: Date) -> Bool {
        let parts = archiveURL.path.split(separator: "/")
        guard parts.count >= 2,
              let year = Int(parts[parts.count - 2]),
              let month = Int(parts[parts.count - 1]) else {
            return true
        }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        let archiveDate = Calendar.current.date(from: components) ?? .distantPast
        let sinceMonth = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: date)) ?? date
        return archiveDate >= sinceMonth
    }

    private func mapRemoteGame(_ game: ArchiveGame) -> RemoteGame {
        let white = game.white.username
        let black = game.black.username
        let gameDate = game.endTime.map { ISO8601DateFormatter().string(from: $0) } ?? ""
        let remoteId = game.url.split(separator: "/").last.map(String.init)
            ?? "\(white)_\(black)_\(game.endTime?.timeIntervalSince1970 ?? 0)"
        let whiteElo = game.white.rating ?? parseElo(from: game.pgn, key: "WhiteElo")
        let blackElo = game.black.rating ?? parseElo(from: game.pgn, key: "BlackElo")
        return RemoteGame(
            id: remoteId,
            pgn: game.pgn,
            whitePlayer: white,
            blackPlayer: black,
            whiteElo: whiteElo,
            blackElo: blackElo,
            result: parseResult(from: game.pgn),
            gameDate: parseDate(from: game.pgn) ?? gameDate,
            timeControl: game.timeControl,
            timeClass: game.timeClass,
            endTime: game.endTime,
            url: game.url
        )
    }

    private func parseResult(from pgn: String) -> String {
        PGNParser.extractHeader(from: pgn, key: "Result") ?? "*"
    }

    private func parseDate(from pgn: String) -> String? {
        PGNParser.extractHeader(from: pgn, key: "Date")
    }

    private func parseElo(from pgn: String, key: String) -> Int? {
        guard let value = PGNParser.extractHeader(from: pgn, key: key) else { return nil }
        return Int(value)
    }
}

private struct ArchivesResponse: Codable {
    let archives: [String]
}

private struct ArchiveGamesResponse: Codable {
    let games: [ArchiveGame]
}

private struct ArchiveGame: Codable {
    let url: String
    let pgn: String
    let timeControl: String
    let timeClass: String
    let endTime: Date?
    let white: ArchivePlayer
    let black: ArchivePlayer

    enum CodingKeys: String, CodingKey {
        case url
        case pgn
        case timeControl = "time_control"
        case timeClass = "time_class"
        case endTime = "end_time"
        case white
        case black
    }
}

private struct ArchivePlayer: Codable {
    let username: String
    let rating: Int?
}

struct ChessComPlayer: Codable {
    let username: String
    let avatar: String?
}

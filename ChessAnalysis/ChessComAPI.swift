import Foundation

enum ChessComAPIError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int, message: String?)
    case userNotFound(username: String)
    case rateLimited
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from Chess.com server."
        case .httpError(let statusCode, let message):
            if let message {
                return "Chess.com error (\(statusCode)): \(message)"
            }
            return "Chess.com request failed with status \(statusCode)."
        case .userNotFound(let username):
            return "User '\(username)' not found on Chess.com."
        case .rateLimited:
            return "Too many requests. Please wait a moment and try again."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

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
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        // Disable URL caching to always get fresh data from Chess.com
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }

    func fetchMonthlyArchives(username: String) async throws -> [URL] {
        let url = baseURL.appendingPathComponent("player/\(username.lowercased())/games/archives")
        var request = URLRequest(url: url)
        addAuthHeader(to: &request)
        let (data, response) = try await performRequest(request)
        try validateResponse(response, for: username)
        let decoder = JSONDecoder()
        let archivesResponse = try decoder.decode(ArchivesResponse.self, from: data)
        return archivesResponse.archives.compactMap { URL(string: $0) }
    }

    func fetchGamesFromArchive(_ archiveURL: URL) async throws -> [RemoteGame] {
        // Add cache-busting parameter to bypass Chess.com's CDN cache
        var components = URLComponents(url: archiveURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "_t", value: String(Int(Date().timeIntervalSince1970)))]
        var request = URLRequest(url: components.url!)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        addAuthHeader(to: &request)
        let (data, response) = try await performRequest(request)
        try validateResponse(response, for: nil)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let archiveResponse = try decoder.decode(ArchiveGamesResponse.self, from: data)
        return archiveResponse.games.map { mapRemoteGame($0) }
    }

    func fetchAllGames(username: String, limitMonths: Int?, since: Date? = nil) async throws -> [RemoteGame] {
        var archives = try await fetchMonthlyArchives(username: username)

        // Always include the current month's archive to catch recent games
        // Chess.com archives are sorted oldest to newest, so last archive is current month
        let currentMonthArchive = archives.last

        #if DEBUG
        print("[ChessComAPI] Total archives: \(archives.count), current month: \(currentMonthArchive?.lastPathComponent ?? "none")")
        if let since {
            print("[ChessComAPI] Using since filter: \(since)")
        }
        #endif

        if let since {
            archives = archives.filter { archiveIsOnOrAfter(archiveURL: $0, date: since) }
            // Ensure current month is always included even if 'since' would filter it out
            if let current = currentMonthArchive, !archives.contains(current) {
                archives.append(current)
            }
        }
        if let limitMonths, limitMonths > 0, archives.count > limitMonths {
            archives = Array(archives.suffix(limitMonths))
        }

        #if DEBUG
        print("[ChessComAPI] Fetching \(archives.count) archives")
        #endif

        var allGames: [RemoteGame] = []
        for archive in archives {
            // Add small delay between requests to avoid rate limiting
            if !allGames.isEmpty {
                try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
            let games = try await fetchGamesFromArchive(archive)
            #if DEBUG
            print("[ChessComAPI] Archive \(archive.lastPathComponent): \(games.count) games")
            if let newest = games.max(by: { ($0.endTime ?? .distantPast) < ($1.endTime ?? .distantPast) }) {
                print("[ChessComAPI]   Newest in archive: \(newest.whitePlayer) vs \(newest.blackPlayer), endTime: \(newest.endTime?.description ?? "nil")")
            }
            #endif
            if let since {
                // For current month, always include all games (don't filter by since)
                // This ensures we catch games that were just played
                let isCurrentMonth = archive == currentMonthArchive
                if isCurrentMonth {
                    allGames.append(contentsOf: games)
                } else {
                    allGames.append(contentsOf: games.filter { ($0.endTime ?? .distantPast) >= since })
                }
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
        let (data, response) = try await performRequest(request)
        try validateResponse(response, for: username)
        let decoder = JSONDecoder()
        return try decoder.decode(ChessComPlayer.self, from: data)
    }

    private func performRequest(_ request: URLRequest, maxRetries: Int = 3) async throws -> (Data, URLResponse) {
        var lastError: Error?
        var delay: UInt64 = 500_000_000 // Start with 500ms

        for attempt in 0..<maxRetries {
            do {
                try Task.checkCancellation()
                let (data, response) = try await session.data(for: request)

                // Check if we should retry based on status code
                if let httpResponse = response as? HTTPURLResponse {
                    switch httpResponse.statusCode {
                    case 429: // Rate limited - retry with backoff
                        if attempt < maxRetries - 1 {
                            try await Task.sleep(nanoseconds: delay * 2) // Longer delay for rate limiting
                            delay *= 2
                            continue
                        }
                    case 500...599: // Server error - retry
                        if attempt < maxRetries - 1 {
                            try await Task.sleep(nanoseconds: delay)
                            delay *= 2
                            continue
                        }
                    default:
                        break
                    }
                }

                return (data, response)
            } catch is CancellationError {
                throw CancellationError()
            } catch let urlError as URLError where urlError.code == .timedOut || urlError.code == .networkConnectionLost {
                // Retry on timeout or connection lost
                lastError = urlError
                if attempt < maxRetries - 1 {
                    try await Task.sleep(nanoseconds: delay)
                    delay *= 2
                    continue
                }
            } catch {
                lastError = error
                // Don't retry other errors
                break
            }
        }

        throw ChessComAPIError.networkError(lastError ?? URLError(.unknown))
    }

    private func validateResponse(_ response: URLResponse, for username: String?) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ChessComAPIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return // Success
        case 404:
            if let username {
                throw ChessComAPIError.userNotFound(username: username)
            }
            throw ChessComAPIError.httpError(statusCode: 404, message: "Resource not found")
        case 429:
            throw ChessComAPIError.rateLimited
        default:
            throw ChessComAPIError.httpError(statusCode: httpResponse.statusCode, message: nil)
        }
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

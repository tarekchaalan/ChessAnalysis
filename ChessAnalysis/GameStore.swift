import CoreData
import Foundation

actor GameStore {
    @MainActor static let shared = GameStore(controller: PersistenceController())

    private let controller: PersistenceController
    private let analysisVersion = 1
    private let filenameAllowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))

    init(controller: PersistenceController) {
        self.controller = controller
    }

    func saveDownloadedGame(remote: RemoteGame, pgnData: Data) async throws -> GameMetadata {
        let directory = try ensureGamesDirectory()
        let safeId = safeFilename(remote.id)
        let filename = "\(safeId).pgn"
        let pgnURL = directory.appendingPathComponent(filename)
        try pgnData.write(to: pgnURL, options: .atomic)
        let bytes = Int64((try? FileManager.default.attributesOfItem(atPath: pgnURL.path)[.size] as? NSNumber)?.int64Value ?? 0)
        let summary = GameSummary(
            whitePlayer: remote.whitePlayer,
            blackPlayer: remote.blackPlayer,
            whiteElo: remote.whiteElo,
            blackElo: remote.blackElo,
            result: remote.result,
            gameDate: remote.gameDate,
            timeControl: remote.timeControl
        )

        let context = controller.container.newBackgroundContext()
        return try await context.perform {
            let fetch: NSFetchRequest<GameEntity> = GameEntity.fetchRequest()
            fetch.predicate = NSPredicate(format: "remoteId == %@", remote.id)
            let existing = try context.fetch(fetch).first
            let entity = existing ?? GameEntity(context: context)
            if existing == nil {
                entity.id = UUID()
                entity.remoteId = remote.id
            }
            // Store only the filename, not the full path (container UUID can change between launches)
            entity.pgnPath = filename
            entity.downloadedAt = Date()
            entity.analysisVersion = Int32(self.analysisVersion)
            entity.bytesOnDisk = bytes
            try context.save()
            // Return the full path for immediate use
            return GameMetadata(
                id: entity.id,
                remoteId: entity.remoteId,
                pgnPath: pgnURL.path,
                downloadedAt: entity.downloadedAt,
                lastAnalyzedAt: entity.lastAnalyzedAt,
                analysisVersion: Int(entity.analysisVersion),
                bytesOnDisk: entity.bytesOnDisk,
                summary: summary
            )
        }
    }

    func fetchDownloadedGames() async throws -> [GameMetadata] {
        let gamesDirectory = try ensureGamesDirectory()
        let context = controller.container.newBackgroundContext()
        return try await context.perform {
            let fetch: NSFetchRequest<GameEntity> = GameEntity.fetchRequest()
            fetch.sortDescriptors = [NSSortDescriptor(key: "downloadedAt", ascending: false)]
            let entities = try context.fetch(fetch)

            var needsSave = false
            var results: [GameMetadata] = []

            for entity in entities {
                // Migrate legacy absolute paths to relative filenames
                let (fullPath, didMigrate) = self.resolveAndMigratePath(
                    storedPath: entity.pgnPath,
                    gamesDirectory: gamesDirectory
                )

                if didMigrate {
                    // Update entity with relative filename
                    let filename = (fullPath as NSString).lastPathComponent
                    entity.pgnPath = filename
                    needsSave = true
                }

                // Try to read the PGN file
                guard let pgnData = try? Data(contentsOf: URL(fileURLWithPath: fullPath)),
                      let pgn = String(data: pgnData, encoding: .utf8)
                else {
                    // File doesn't exist - skip this game (it's orphaned)
                    continue
                }

                let whiteEloStr = PGNParser.extractHeader(from: pgn, key: "WhiteElo")
                let blackEloStr = PGNParser.extractHeader(from: pgn, key: "BlackElo")
                let summary = GameSummary(
                    whitePlayer: PGNParser.extractHeader(from: pgn, key: "White") ?? "White",
                    blackPlayer: PGNParser.extractHeader(from: pgn, key: "Black") ?? "Black",
                    whiteElo: whiteEloStr.flatMap { Int($0) },
                    blackElo: blackEloStr.flatMap { Int($0) },
                    result: PGNParser.extractHeader(from: pgn, key: "Result") ?? "*",
                    gameDate: PGNParser.extractHeader(from: pgn, key: "Date") ?? "",
                    timeControl: PGNParser.extractHeader(from: pgn, key: "TimeControl") ?? ""
                )

                results.append(GameMetadata(
                    id: entity.id,
                    remoteId: entity.remoteId,
                    pgnPath: fullPath,
                    downloadedAt: entity.downloadedAt,
                    lastAnalyzedAt: entity.lastAnalyzedAt,
                    analysisVersion: Int(entity.analysisVersion),
                    bytesOnDisk: entity.bytesOnDisk,
                    summary: summary
                ))
            }

            // Save migrated paths
            if needsSave {
                try? context.save()
            }

            return results
        }
    }

    /// Resolves a stored path to a full filesystem path, migrating legacy paths.
    /// Returns (fullPath, didMigrate) where didMigrate is true if the path was a legacy absolute path.
    private nonisolated func resolveAndMigratePath(storedPath: String, gamesDirectory: URL) -> (String, Bool) {
        // If it's already a relative filename, just construct the full path
        if !storedPath.hasPrefix("/") {
            return (gamesDirectory.appendingPathComponent(storedPath).path, false)
        }

        // Legacy absolute path - extract filename and use current games directory
        let filename = (storedPath as NSString).lastPathComponent
        let newPath = gamesDirectory.appendingPathComponent(filename).path
        return (newPath, true)
    }

    /// Resolves a stored path to a full filesystem path (for use in other methods).
    private nonisolated func resolveFullPath(storedPath: String, gamesDirectory: URL) -> String {
        let (path, _) = resolveAndMigratePath(storedPath: storedPath, gamesDirectory: gamesDirectory)
        return path
    }

    func fetchAnalysis(gameId: UUID) async throws -> [MoveAnalysis] {
        let context = controller.container.newBackgroundContext()
        return try await context.perform {
            let fetch: NSFetchRequest<MoveAnalysisEntity> = MoveAnalysisEntity.fetchRequest()
            fetch.predicate = NSPredicate(format: "game.id == %@", gameId as CVarArg)
            fetch.sortDescriptors = [NSSortDescriptor(key: "ply", ascending: true)]
            let entities = try context.fetch(fetch)
            return entities.map { entity in
                MoveAnalysis(
                    ply: Int(entity.ply),
                    fen: entity.fen,
                    playedUci: entity.playedUci,
                    bestUci: entity.bestUci,
                    evalBefore: Int(entity.evalBefore),
                    evalAfter: Int(entity.evalAfter),
                    loss: Int(entity.loss),
                    classification: entity.classification,
                    pv: entity.pv ?? ""
                )
            }
        }
    }

    func replaceAnalysis(gameId: UUID, analyses: [MoveAnalysis]) async throws {
        let gamesDirectory = try ensureGamesDirectory()
        let context = controller.container.newBackgroundContext()
        try await context.perform {
            let gameFetch: NSFetchRequest<GameEntity> = GameEntity.fetchRequest()
            gameFetch.predicate = NSPredicate(format: "id == %@", gameId as CVarArg)
            guard let game = try context.fetch(gameFetch).first else { return }

            let fetch: NSFetchRequest<MoveAnalysisEntity> = MoveAnalysisEntity.fetchRequest()
            fetch.predicate = NSPredicate(format: "game.id == %@", gameId as CVarArg)
            let existing = try context.fetch(fetch)
            for item in existing {
                context.delete(item)
            }

            for analysis in analyses {
                let entity = MoveAnalysisEntity(context: context)
                entity.game = game
                entity.ply = Int32(analysis.ply)
                entity.fen = analysis.fen
                entity.playedUci = analysis.playedUci
                entity.bestUci = analysis.bestUci
                entity.evalBefore = Int32(analysis.evalBefore)
                entity.evalAfter = Int32(analysis.evalAfter)
                entity.loss = Int32(analysis.loss)
                entity.classification = analysis.classification
                entity.pv = analysis.pv
            }

            let fullPath = self.resolveFullPath(storedPath: game.pgnPath, gamesDirectory: gamesDirectory)
            let pgnBytes = (try? FileManager.default.attributesOfItem(atPath: fullPath)[.size] as? NSNumber)?.int64Value ?? 0
            let analysisBytes = analyses.reduce(Int64(0)) { sum, analysis in
                sum + Int64(analysis.fen.count + analysis.playedUci.count + analysis.bestUci.count + analysis.pv.count) + 32
            }
            game.bytesOnDisk = pgnBytes + analysisBytes
            game.lastAnalyzedAt = Date()
            try context.save()
        }
    }

    func deleteAnalysis(gameId: UUID) async throws {
        let gamesDirectory = try ensureGamesDirectory()
        let context = controller.container.newBackgroundContext()
        try await context.perform {
            let gameFetch: NSFetchRequest<GameEntity> = GameEntity.fetchRequest()
            gameFetch.predicate = NSPredicate(format: "id == %@", gameId as CVarArg)
            guard let game = try context.fetch(gameFetch).first else { return }

            let fetch: NSFetchRequest<MoveAnalysisEntity> = MoveAnalysisEntity.fetchRequest()
            fetch.predicate = NSPredicate(format: "game.id == %@", gameId as CVarArg)
            let existing = try context.fetch(fetch)
            for item in existing {
                context.delete(item)
            }

            let fullPath = self.resolveFullPath(storedPath: game.pgnPath, gamesDirectory: gamesDirectory)
            let pgnBytes = (try? FileManager.default.attributesOfItem(atPath: fullPath)[.size] as? NSNumber)?.int64Value ?? 0
            game.bytesOnDisk = pgnBytes
            game.lastAnalyzedAt = nil
            try context.save()
        }
    }

    func deleteGame(gameId: UUID) async throws {
        let gamesDirectory = try ensureGamesDirectory()
        let context = controller.container.newBackgroundContext()
        try await context.perform {
            let fetch: NSFetchRequest<GameEntity> = GameEntity.fetchRequest()
            fetch.predicate = NSPredicate(format: "id == %@", gameId as CVarArg)
            guard let game = try context.fetch(fetch).first else { return }

            let fullPath = self.resolveFullPath(storedPath: game.pgnPath, gamesDirectory: gamesDirectory)

            // Delete from database first
            context.delete(game)
            try context.save()

            // Only delete file after database save succeeds
            // This prevents orphaned DB records if file deletion fails
            if FileManager.default.fileExists(atPath: fullPath) {
                do {
                    try FileManager.default.removeItem(atPath: fullPath)
                } catch {
                    // Log but don't fail - orphaned file is better than orphaned DB record
                    print("[GameStore] Failed to delete PGN file at \(fullPath): \(error)")
                }
            }
        }
    }

    func deleteIncompleteDownloads() async throws {
        let gamesDirectory = try ensureGamesDirectory()
        let context = controller.container.newBackgroundContext()
        try await context.perform {
            let fetch: NSFetchRequest<GameEntity> = GameEntity.fetchRequest()
            fetch.predicate = NSPredicate(format: "lastAnalyzedAt == nil")
            let games = try context.fetch(fetch)
            for game in games {
                let analysisFetch: NSFetchRequest<MoveAnalysisEntity> = MoveAnalysisEntity.fetchRequest()
                analysisFetch.predicate = NSPredicate(format: "game.id == %@", game.id as CVarArg)
                let analyses = try context.fetch(analysisFetch)
                for item in analyses {
                    context.delete(item)
                }
                let fullPath = self.resolveFullPath(storedPath: game.pgnPath, gamesDirectory: gamesDirectory)
                if FileManager.default.fileExists(atPath: fullPath) {
                    try? FileManager.default.removeItem(atPath: fullPath)
                }
                context.delete(game)
            }
            try context.save()
        }
    }

    func enforceStorageLimit(extraBytes: Int64, capBytes: Int64) async throws {
        let gamesDirectory = try ensureGamesDirectory()
        let context = controller.container.newBackgroundContext()
        try await context.perform {
            let fetch: NSFetchRequest<GameEntity> = GameEntity.fetchRequest()
            let games = try context.fetch(fetch)
            let totalBytes = games.reduce(Int64(0)) { $0 + $1.bytesOnDisk }
            let projected = totalBytes + extraBytes
            if projected <= capBytes, Double(projected) / Double(capBytes) < 0.95 {
                return
            }

            let analyzed = games.filter { $0.lastAnalyzedAt != nil }
                .sorted {
                    let lhs = $0.lastAnalyzedAt ?? $0.downloadedAt
                    let rhs = $1.lastAnalyzedAt ?? $1.downloadedAt
                    return lhs < rhs
                }
            let notAnalyzed = games.filter { $0.lastAnalyzedAt == nil }
                .sorted { $0.downloadedAt < $1.downloadedAt }

            var ordered = analyzed + notAnalyzed
            var runningTotal = totalBytes
            while runningTotal + extraBytes > capBytes || Double(runningTotal + extraBytes) / Double(capBytes) >= 0.95 {
                guard let next = ordered.first else { break }
                ordered.removeFirst()
                let fullPath = self.resolveFullPath(storedPath: next.pgnPath, gamesDirectory: gamesDirectory)
                if FileManager.default.fileExists(atPath: fullPath) {
                    try FileManager.default.removeItem(atPath: fullPath)
                }
                runningTotal -= next.bytesOnDisk
                context.delete(next)
            }
            try context.save()
        }
    }

    func totalStorageBytes() async throws -> Int64 {
        let context = controller.container.newBackgroundContext()
        return try await context.perform {
            let fetch: NSFetchRequest<GameEntity> = GameEntity.fetchRequest()
            let games = try context.fetch(fetch)
            return games.reduce(Int64(0)) { $0 + $1.bytesOnDisk }
        }
    }

    private func ensureGamesDirectory() throws -> URL {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw GameStoreError.documentsDirectoryUnavailable
        }
        let dir = docs.appendingPathComponent("games", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func safeFilename(_ raw: String) -> String {
        let sanitized = String(raw.unicodeScalars.map { scalar in
            filenameAllowed.contains(scalar) ? Character(scalar) : "_"
        })
        let trimmed = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "_-"))
        return trimmed.isEmpty ? UUID().uuidString : trimmed
    }
}

private enum GameStoreError: LocalizedError {
    case documentsDirectoryUnavailable

    var errorDescription: String? {
        switch self {
        case .documentsDirectoryUnavailable:
            return "Unable to access the documents directory."
        }
    }
}

extension GameEntity {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<GameEntity> {
        NSFetchRequest<GameEntity>(entityName: "GameEntity")
    }
}

extension MoveAnalysisEntity {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<MoveAnalysisEntity> {
        NSFetchRequest<MoveAnalysisEntity>(entityName: "MoveAnalysisEntity")
    }
}

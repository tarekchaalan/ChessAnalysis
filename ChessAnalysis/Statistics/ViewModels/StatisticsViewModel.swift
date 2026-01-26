//
//  StatisticsViewModel.swift
//  ChessAnalysis
//

import Combine
import Foundation

@MainActor
final class StatisticsViewModel: ObservableObject {
    @Published var statistics: AggregatedStatistics = .empty
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedTimeRange: TimeRange = .allTime
    @Published var selectedTimeClass: TimeClassFilter = .all

    private let service = StatisticsService.shared

    // Cached DateFormatter for performance
    private static let gameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    // Debounce mechanism to prevent multiple simultaneous refreshes
    private var refreshTask: Task<Void, Never>?

    enum TimeRange: String, CaseIterable, Identifiable {
        case lastWeek = "7 Days"
        case lastMonth = "30 Days"
        case last3Months = "3 Months"
        case lastYear = "1 Year"
        case allTime = "All Time"

        var id: String { rawValue }

        var days: Int? {
            switch self {
            case .lastWeek: return 7
            case .lastMonth: return 30
            case .last3Months: return 90
            case .lastYear: return 365
            case .allTime: return nil
            }
        }
    }

    enum TimeClassFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case bullet = "Bullet"
        case blitz = "Blitz"
        case rapid = "Rapid"
        case classical = "Classical"

        var id: String { rawValue }
    }

    /// Debounced refresh that cancels any pending refresh and schedules a new one
    func scheduleRefresh(
        remoteGames: [RemoteGame],
        downloadedGames: [GameMetadata],
        username: String,
        delay: Duration = .milliseconds(150)
    ) {
        // Cancel any pending refresh
        refreshTask?.cancel()

        refreshTask = Task {
            // Wait for debounce delay
            try? await Task.sleep(for: delay)

            // Check if cancelled during wait
            guard !Task.isCancelled else { return }

            await loadStatistics(
                remoteGames: remoteGames,
                downloadedGames: downloadedGames,
                username: username
            )
        }
    }

    func loadStatistics(
        remoteGames: [RemoteGame],
        downloadedGames: [GameMetadata],
        username: String
    ) async {
        guard !username.isEmpty else {
            statistics = .empty
            return
        }

        isLoading = true
        errorMessage = nil

        // Filter games by time range and time class
        let filteredRemote = filterGames(remoteGames)
        let filteredDownloaded = filterDownloadedGames(downloadedGames, remoteGames: remoteGames)

        statistics = await service.computeStatistics(
            remoteGames: filteredRemote,
            downloadedGames: filteredDownloaded,
            username: username
        )

        isLoading = false
    }

    private func filterGames(_ games: [RemoteGame]) -> [RemoteGame] {
        var filtered = games

        // Filter by time range
        if let days = selectedTimeRange.days {
            let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
            filtered = filtered.filter { game in
                if let endTime = game.endTime {
                    return endTime >= cutoff
                }
                // Try parsing game date if endTime is nil
                if let date = parseGameDate(game.gameDate) {
                    return date >= cutoff
                }
                return false
            }
        }

        // Filter by time class
        if selectedTimeClass != .all {
            filtered = filtered.filter { game in
                game.timeClass.lowercased() == selectedTimeClass.rawValue.lowercased()
            }
        }

        return filtered
    }

    private func filterDownloadedGames(_ downloadedGames: [GameMetadata], remoteGames: [RemoteGame]) -> [GameMetadata] {
        // First, apply the same filters based on game metadata
        var filtered = downloadedGames

        // Filter by time range
        if let days = selectedTimeRange.days {
            let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
            filtered = filtered.filter { game in
                if let date = parseGameDate(game.summary.gameDate) {
                    return date >= cutoff
                }
                return false
            }
        }

        // Filter by time class - need to parse time control to determine class
        if selectedTimeClass != .all {
            filtered = filtered.filter { game in
                let timeClass = timeClassFrom(game.summary.timeControl)
                return timeClass.lowercased() == selectedTimeClass.rawValue.lowercased()
            }
        }

        return filtered
    }

    private func parseGameDate(_ value: String) -> Date? {
        Self.gameDateFormatter.date(from: value)
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

//
//  StatsCardViews.swift
//  ChessAnalysis
//

import SwiftUI
import Charts

// MARK: - Reusable Card Container

struct StatsCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.accentColor)
                Text(title)
                    .font(.headline)
            }
            content()
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Overall Performance Card

struct OverallPerformanceCard: View {
    let stats: OverallStats

    var body: some View {
        StatsCard(title: "Overall Performance", icon: "chart.pie.fill") {
            HStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("\(stats.totalGames)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    Text("Games")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()
                    .frame(height: 60)

                VStack(alignment: .leading, spacing: 4) {
                    StatRow(label: "Wins", value: stats.wins, color: .green, percentage: stats.winRate)
                    StatRow(label: "Losses", value: stats.losses, color: .red, percentage: stats.lossRate)
                    StatRow(label: "Draws", value: stats.draws, color: .gray, percentage: stats.drawRate)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct StatRow: View {
    let label: String
    let value: Int
    let color: Color
    let percentage: Double

    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
                .font(.subheadline)
            Spacer()
            Text("\(value)")
                .font(.subheadline)
                .fontWeight(.semibold)
            Text("(\(percentage, specifier: "%.1f")%)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Color Stats Card

struct ColorStatsCard: View {
    let stats: ColorStats

    var body: some View {
        StatsCard(title: "Performance by Color", icon: "circle.lefthalf.filled") {
            HStack(spacing: 20) {
                ColorStatColumn(
                    title: "As White",
                    stats: stats.asWhite,
                    pieceIcon: "square.fill"
                )
                Divider()
                    .frame(height: 80)
                ColorStatColumn(
                    title: "As Black",
                    stats: stats.asBlack,
                    pieceIcon: "square.fill"
                )
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct ColorStatColumn: View {
    let title: String
    let stats: OverallStats
    let pieceIcon: String

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: pieceIcon)
                    .foregroundColor(title == "As White" ? .white : .black)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(title == "As White" ? Color.black.opacity(0.2) : Color.white.opacity(0.2))
                            .frame(width: 18, height: 18)
                    )
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            Text("\(stats.totalGames)")
                .font(.title2)
                .fontWeight(.bold)
            Text("games")
                .font(.caption2)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                MiniStat(value: stats.wins, label: "W", color: .green)
                MiniStat(value: stats.losses, label: "L", color: .red)
                MiniStat(value: stats.draws, label: "D", color: .gray)
            }

            Text("\(stats.winRate, specifier: "%.1f")% win rate")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct MiniStat: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Time Control Stats Card

struct TimeControlStatsCard: View {
    let stats: TimeControlStats

    var body: some View {
        StatsCard(title: "Performance by Time Control", icon: "clock.fill") {
            VStack(spacing: 12) {
                TimeControlRow(name: "Bullet", icon: "bolt.fill", stats: stats.bullet)
                TimeControlRow(name: "Blitz", icon: "hare.fill", stats: stats.blitz)
                TimeControlRow(name: "Rapid", icon: "tortoise.fill", stats: stats.rapid)
                if stats.classical.totalGames > 0 {
                    TimeControlRow(name: "Classical", icon: "clock.fill", stats: stats.classical)
                }
            }
        }
    }
}

struct TimeControlRow: View {
    let name: String
    let icon: String
    let stats: OverallStats

    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundColor(.accentColor)
            Text(name)
                .font(.subheadline)
            Spacer()
            Text("\(stats.totalGames) games")
                .font(.caption)
                .foregroundColor(.secondary)
            WinRateBar(winRate: stats.winRate, width: 60)
            Text("\(stats.winRate, specifier: "%.0f")%")
                .font(.caption)
                .fontWeight(.medium)
                .frame(width: 40, alignment: .trailing)
        }
    }
}

struct WinRateBar: View {
    let winRate: Double
    let width: CGFloat

    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: width, height: 8)
                RoundedRectangle(cornerRadius: 2)
                    .fill(winRate >= 50 ? Color.green : Color.orange)
                    .frame(width: width * CGFloat(winRate / 100), height: 8)
            }
        }
        .frame(width: width, height: 8)
    }
}

// MARK: - Rating Trend Card

struct RatingTrendCard: View {
    let dataPoints: [RatingDataPoint]

    /// Minimum number of games required to show a time control's line
    private let minimumGamesForLine = 5

    /// Downsample data points to reduce visual noise while preserving trends
    private func downsampledPoints(for timeClass: String, from points: [RatingDataPoint]) -> [RatingDataPoint] {
        let filtered = points.filter { $0.timeClass.lowercased() == timeClass.lowercased() }

        // If few points, return as-is
        guard filtered.count > 50 else { return filtered }

        // Downsample to ~50 points by averaging windows
        let windowSize = max(1, filtered.count / 50)
        var result: [RatingDataPoint] = []

        for i in stride(from: 0, to: filtered.count, by: windowSize) {
            let window = Array(filtered[i..<min(i + windowSize, filtered.count)])
            if let last = window.last {
                // Use the last date in window, average the ratings
                let avgRating = window.reduce(0) { $0 + $1.rating } / window.count
                result.append(RatingDataPoint(
                    date: last.date,
                    rating: avgRating,
                    timeClass: timeClass
                ))
            }
        }

        return result
    }

    /// Get time controls that have enough games to display
    private var validTimeControls: [String] {
        let grouped = Dictionary(grouping: dataPoints) { $0.timeClass.lowercased() }
        return grouped.filter { $0.value.count >= minimumGamesForLine }.keys.sorted()
    }

    /// Processed data points for chart display
    private var chartDataPoints: [RatingDataPoint] {
        var result: [RatingDataPoint] = []
        for timeClass in validTimeControls {
            result.append(contentsOf: downsampledPoints(for: timeClass, from: dataPoints))
        }
        return result
    }

    /// Get the most recent rating from valid time controls
    private var currentRating: (rating: Int, change: Int)? {
        // Find the most recent data point across all valid time controls
        let validPoints = dataPoints.filter { validTimeControls.contains($0.timeClass.lowercased()) }
        guard let last = validPoints.last else { return nil }

        // Find first point of same time control for change calculation
        let sameTimeClass = validPoints.filter { $0.timeClass.lowercased() == last.timeClass.lowercased() }
        guard let first = sameTimeClass.first else { return nil }

        return (last.rating, last.rating - first.rating)
    }

    var body: some View {
        StatsCard(title: "Rating Trend", icon: "chart.line.uptrend.xyaxis") {
            if dataPoints.isEmpty || validTimeControls.isEmpty {
                Text("No rating data available")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    // Summary
                    if let current = currentRating {
                        HStack {
                            Text("Current: \(current.rating)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Spacer()
                            Text(current.change >= 0 ? "+\(current.change)" : "\(current.change)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(current.change >= 0 ? .green : .red)
                        }
                    }

                    // Chart with smoothed data
                    Chart(chartDataPoints) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Rating", point.rating)
                        )
                        .foregroundStyle(by: .value("Time Control", point.timeClass.capitalized))
                        .interpolationMethod(.catmullRom)  // Smooth curves
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 150)

                    // Show hidden time controls note if any were filtered out
                    let hiddenCount = Set(dataPoints.map { $0.timeClass.lowercased() }).count - validTimeControls.count
                    if hiddenCount > 0 {
                        Text("\(hiddenCount) time control(s) hidden (< \(minimumGamesForLine) games)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Openings Card

struct OpeningsCard: View {
    let openings: [OpeningStats]
    @State private var isExpanded = false

    private var displayedOpenings: [OpeningStats] {
        isExpanded ? Array(openings.prefix(20)) : Array(openings.prefix(5))
    }

    var body: some View {
        StatsCard(title: "Opening Repertoire", icon: "book.fill") {
            if openings.isEmpty {
                Text("No opening data available")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 8) {
                    ForEach(displayedOpenings) { opening in
                        OpeningRow(opening: opening)
                    }

                    if openings.count > 5 {
                        Button {
                            withAnimation {
                                isExpanded.toggle()
                            }
                        } label: {
                            Text(isExpanded ? "Show Less" : "Show More (\(openings.count - 5) more)")
                                .font(.caption)
                                .foregroundColor(.accentColor)
                        }
                    }
                }
            }
        }
    }
}

struct OpeningRow: View {
    let opening: OpeningStats

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(opening.openingName)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(opening.ecoCode)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text("\(opening.gamesPlayed)")
                .font(.caption)
                .foregroundColor(.secondary)
            WinRateBar(winRate: opening.winRate, width: 50)
            Text("\(opening.winRate, specifier: "%.0f")%")
                .font(.caption)
                .fontWeight(.medium)
                .frame(width: 36, alignment: .trailing)
        }
    }
}

// MARK: - Move Quality Card

struct MoveQualityCard: View {
    let stats: MoveQualityStats

    var body: some View {
        StatsCard(title: "Move Quality", icon: "target") {
            if stats.analyzedGameCount == 0 {
                Text("Analyze games to see move quality statistics")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 12) {
                    // Average accuracy
                    HStack {
                        Text("Average Accuracy")
                            .font(.subheadline)
                        Spacer()
                        Text("\(stats.averageAccuracy, specifier: "%.1f")%")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(accuracyColor(stats.averageAccuracy))
                    }

                    Divider()

                    // Classification breakdown
                    VStack(spacing: 6) {
                        ClassificationRow(
                            label: "Best Moves",
                            count: stats.bestMoves,
                            total: stats.totalMoves,
                            color: .green
                        )
                        ClassificationRow(
                            label: "Good Moves",
                            count: stats.goodMoves,
                            total: stats.totalMoves,
                            color: .blue
                        )
                        ClassificationRow(
                            label: "Inaccuracies",
                            count: stats.inaccuracies,
                            total: stats.totalMoves,
                            color: .yellow
                        )
                        ClassificationRow(
                            label: "Mistakes",
                            count: stats.mistakes,
                            total: stats.totalMoves,
                            color: .orange
                        )
                        ClassificationRow(
                            label: "Blunders",
                            count: stats.blunders,
                            total: stats.totalMoves,
                            color: .red
                        )
                    }

                    Text("Based on \(stats.analyzedGameCount) analyzed games")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func accuracyColor(_ accuracy: Double) -> Color {
        if accuracy >= 90 { return .green }
        if accuracy >= 80 { return .blue }
        if accuracy >= 70 { return .yellow }
        if accuracy >= 60 { return .orange }
        return .red
    }
}

struct ClassificationRow: View {
    let label: String
    let count: Int
    let total: Int
    let color: Color

    private var percentage: Double {
        total > 0 ? Double(count) / Double(total) * 100 : 0
    }

    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption)
            Spacer()
            Text("\(count)")
                .font(.caption)
                .fontWeight(.medium)
            Text("(\(percentage, specifier: "%.1f")%)")
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .trailing)
        }
    }
}

// MARK: - Accuracy Trend Card

struct AccuracyTrendCard: View {
    let dataPoints: [AccuracyDataPoint]

    var body: some View {
        StatsCard(title: "Accuracy Trend", icon: "waveform.path.ecg") {
            if dataPoints.isEmpty {
                Text("Analyze games to see accuracy trend")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                Chart(dataPoints) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Accuracy", point.accuracy)
                    )
                    .foregroundStyle(.blue)

                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Accuracy", point.accuracy)
                    )
                    .foregroundStyle(.blue)
                }
                .chartYScale(domain: 0...100)
                .frame(height: 150)
            }
        }
    }
}

// MARK: - Opponents Card

struct OpponentsCard: View {
    let opponents: [OpponentStats]
    @State private var isExpanded = false

    private var displayedOpponents: [OpponentStats] {
        isExpanded ? Array(opponents.prefix(15)) : Array(opponents.prefix(5))
    }

    var body: some View {
        StatsCard(title: "Most Played Opponents", icon: "person.2.fill") {
            if opponents.isEmpty {
                Text("No opponent data available")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 8) {
                    ForEach(displayedOpponents) { opponent in
                        OpponentRow(opponent: opponent)
                    }

                    if opponents.count > 5 {
                        Button {
                            withAnimation {
                                isExpanded.toggle()
                            }
                        } label: {
                            Text(isExpanded ? "Show Less" : "Show More")
                                .font(.caption)
                                .foregroundColor(.accentColor)
                        }
                    }
                }
            }
        }
    }
}

struct OpponentRow: View {
    let opponent: OpponentStats

    var body: some View {
        HStack {
            Text(opponent.opponentName)
                .font(.subheadline)
                .lineLimit(1)
            Spacer()
            Text("\(opponent.wins)-\(opponent.losses)-\(opponent.draws)")
                .font(.caption)
                .fontWeight(.medium)
            Text("(\(opponent.gamesPlayed))")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Termination Stats Card

struct TerminationStatsCard: View {
    let stats: TerminationStats

    var body: some View {
        StatsCard(title: "How Games End", icon: "flag.checkered") {
            HStack(spacing: 20) {
                TerminationColumn(
                    title: "Wins",
                    breakdown: stats.winsBy,
                    color: .green
                )
                Divider()
                    .frame(height: 100)
                TerminationColumn(
                    title: "Losses",
                    breakdown: stats.lossesBy,
                    color: .red
                )
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct TerminationColumn: View {
    let title: String
    let breakdown: TerminationBreakdown
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(color)

            if breakdown.total == 0 {
                Text("No data")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                TerminationRow(
                    icon: "crown.fill",
                    label: "Checkmate",
                    count: breakdown.checkmate,
                    total: breakdown.total
                )
                TerminationRow(
                    icon: "flag.fill",
                    label: "Resignation",
                    count: breakdown.resignation,
                    total: breakdown.total
                )
                TerminationRow(
                    icon: "clock.fill",
                    label: "Timeout",
                    count: breakdown.timeout,
                    total: breakdown.total
                )
                if breakdown.other > 0 {
                    TerminationRow(
                        icon: "ellipsis.circle.fill",
                        label: "Other",
                        count: breakdown.other,
                        total: breakdown.total
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TerminationRow: View {
    let icon: String
    let label: String
    let count: Int
    let total: Int

    private var percentage: Double {
        total > 0 ? Double(count) / Double(total) * 100 : 0
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 16)
            Text(label)
                .font(.caption)
            Spacer()
            Text("\(count)")
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

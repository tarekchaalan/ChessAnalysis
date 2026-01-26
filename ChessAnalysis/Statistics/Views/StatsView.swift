//
//  StatsView.swift
//  ChessAnalysis
//

import SwiftUI

struct StatsView: View {
    @StateObject private var viewModel = StatisticsViewModel()
    @ObservedObject var gamesViewModel: GamesViewModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        NavigationStack {
            Group {
                if settings.username.isEmpty {
                    emptyStateView
                } else if viewModel.isLoading && viewModel.statistics.overall.totalGames == 0 {
                    loadingView
                } else if viewModel.statistics.overall.totalGames == 0 {
                    noGamesView
                } else {
                    statisticsContent
                }
            }
            .navigationTitle("Statistics")
            .refreshable {
                await refresh()
            }
            .task {
                await refresh()
            }
            .onChange(of: viewModel.selectedTimeRange) { _, _ in
                scheduleRefresh()
            }
            .onChange(of: viewModel.selectedTimeClass) { _, _ in
                scheduleRefresh()
            }
            .onChange(of: gamesViewModel.remoteGames.count) { _, _ in
                scheduleRefresh()
            }
            .onChange(of: gamesViewModel.downloadedGames.count) { _, _ in
                scheduleRefresh()
            }
        }
    }

    // MARK: - Main Content

    private var statisticsContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                filterSection

                OverallPerformanceCard(stats: viewModel.statistics.overall)

                ColorStatsCard(stats: viewModel.statistics.byColor)

                TimeControlStatsCard(stats: viewModel.statistics.byTimeControl)

                RatingTrendCard(dataPoints: viewModel.statistics.ratingHistory)

                OpeningsCard(openings: viewModel.statistics.openings)

                MoveQualityCard(stats: viewModel.statistics.moveQuality)

                if !viewModel.statistics.accuracyTrend.isEmpty {
                    AccuracyTrendCard(dataPoints: viewModel.statistics.accuracyTrend)
                }

                OpponentsCard(opponents: viewModel.statistics.opponents)

                TerminationStatsCard(stats: viewModel.statistics.terminations)

                // Footer
                Text("Statistics based on \(gamesViewModel.remoteGames.count) games")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }
            .padding()
        }
    }

    // MARK: - Filter Section

    private var filterSection: some View {
        VStack(spacing: 12) {
            // Time Range Picker
            HStack {
                Text("Time Range")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Picker("Time Range", selection: $viewModel.selectedTimeRange) {
                    ForEach(StatisticsViewModel.TimeRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.menu)
            }

            // Time Class Filter
            HStack {
                Text("Time Control")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Picker("Time Control", selection: $viewModel.selectedTimeClass) {
                    ForEach(StatisticsViewModel.TimeClassFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Empty States

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("No Username Set")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Enter your Chess.com username in Settings to see your statistics.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading statistics...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noGamesView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("No Games Found")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Play some games on Chess.com and they will appear here.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func refresh() async {
        await viewModel.loadStatistics(
            remoteGames: gamesViewModel.remoteGames,
            downloadedGames: gamesViewModel.downloadedGames,
            username: settings.username
        )
    }

    private func scheduleRefresh() {
        viewModel.scheduleRefresh(
            remoteGames: gamesViewModel.remoteGames,
            downloadedGames: gamesViewModel.downloadedGames,
            username: settings.username
        )
    }
}

#Preview {
    StatsView(
        gamesViewModel: GamesViewModel(),
        settings: AppSettings()
    )
}

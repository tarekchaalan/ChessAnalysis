//
//  ContentView.swift
//  ChessAnalysis
//
//  Created by Tarek Chaalan on 1/21/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var settings = AppSettings()
    @StateObject private var gamesViewModel = GamesViewModel()

    var body: some View {
        TabView {
            GamesHomeView(viewModel: gamesViewModel, settings: settings)
                .tabItem {
                    Label("Games", systemImage: "list.bullet.rectangle")
                }
            StatsView(gamesViewModel: gamesViewModel, settings: settings)
                .tabItem {
                    Label("Statistics", systemImage: "chart.bar.xaxis")
                }
            SettingsView(settings: settings)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
    }
}

#Preview {
    ContentView()
}

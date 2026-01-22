//
//  ContentView.swift
//  ChessAnalysis
//
//  Created by Tarek Chaalan on 1/21/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var settings = AppSettings()

    var body: some View {
        TabView {
            GamesHomeView(settings: settings)
                .tabItem {
                    Label("Games", systemImage: "list.bullet.rectangle")
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

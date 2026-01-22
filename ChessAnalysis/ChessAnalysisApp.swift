//
//  ChessAnalysisApp.swift
//  ChessAnalysis
//
//  Created by Tarek Chaalan on 1/21/26.
//

import SwiftUI
import UIKit
import Foundation
import Darwin

@main
struct ChessAnalysisApp: App {
    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    Task {
                        try? await GameStore.shared.deleteIncompleteDownloads()
                        await StockfishEngine.shared.runSmokeTest(seconds: 3)
                    }
                }
        }
    }
}

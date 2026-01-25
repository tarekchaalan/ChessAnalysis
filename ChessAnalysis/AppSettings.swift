import Foundation
import Combine
import UIKit

final class AppSettings: ObservableObject {
    private let lowPowerOverrideKey = "analysis.lowPower.override"
    private let tokenKeychainKey = "chesscom.token"

    @Published var username: String {
        didSet { UserDefaults.standard.set(username, forKey: "chesscom.username") }
    }
    @Published var token: String {
        didSet {
            // Store token securely in Keychain
            if token.isEmpty {
                KeychainHelper.delete(key: tokenKeychainKey)
            } else {
                try? KeychainHelper.save(key: tokenKeychainKey, value: token)
            }
        }
    }
    @Published var storageCapMB: Int {
        didSet { UserDefaults.standard.set(storageCapMB, forKey: "storage.cap.mb") }
    }
    @Published var coachLines: Bool {
        didSet { UserDefaults.standard.set(coachLines, forKey: "analysis.coachLines") }
    }
    @Published var lowPowerAnalysis: Bool {
        didSet { UserDefaults.standard.set(lowPowerAnalysis, forKey: "analysis.lowPower") }
    }

    init() {
        // Migrate token from UserDefaults to Keychain if needed
        KeychainHelper.migrateFromUserDefaults(
            userDefaultsKey: "chesscom.token",
            keychainKey: "chesscom.token"
        )

        let storedCap = UserDefaults.standard.integer(forKey: "storage.cap.mb")
        self.username = UserDefaults.standard.string(forKey: "chesscom.username") ?? ""
        // Load token from Keychain (secure storage)
        self.token = KeychainHelper.load(key: "chesscom.token") ?? ""
        self.storageCapMB = storedCap == 0 ? 500 : storedCap
        self.coachLines = UserDefaults.standard.bool(forKey: "analysis.coachLines")
        self.lowPowerAnalysis = UserDefaults.standard.bool(forKey: "analysis.lowPower")
        UserDefaults.standard.set(false, forKey: lowPowerOverrideKey)
        autoUpdateLowPowerIfNeeded()
    }

    func autoUpdateLowPowerIfNeeded() {
        if UserDefaults.standard.bool(forKey: lowPowerOverrideKey) {
            return
        }
        UIDevice.current.isBatteryMonitoringEnabled = true
        let batteryLevel = UIDevice.current.batteryLevel
        let isUnplugged = UIDevice.current.batteryState == .unplugged
        let batteryCritical = batteryLevel >= 0 && batteryLevel < 0.10 && isUnplugged
        lowPowerAnalysis = batteryCritical
    }

    func setLowPowerAnalysisFromUser(_ value: Bool) {
        UserDefaults.standard.set(true, forKey: lowPowerOverrideKey)
        lowPowerAnalysis = value
    }
}

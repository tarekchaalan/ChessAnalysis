import Foundation
import UIKit

/// Centralized device state monitoring for battery and thermal conditions
enum DeviceState {
    /// Get current battery and thermal state for resource management
    @MainActor
    static func currentPowerState() -> PowerState {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        let state = UIDevice.current.batteryState
        let unplugged = state == .unplugged
        let thermalState = ProcessInfo.processInfo.thermalState

        let batteryLow = level >= 0 && level < 0.2 && unplugged
        let batteryCritical = level >= 0 && level < 0.10 && unplugged

        // Check for manual low power override
        let overrideActive = UserDefaults.standard.bool(forKey: "analysis.lowPower.override")
        let lowPowerEnabled = overrideActive
            ? UserDefaults.standard.bool(forKey: "analysis.lowPower")
            : batteryCritical

        return PowerState(
            batteryLevel: level,
            isUnplugged: unplugged,
            isBatteryLow: batteryLow,
            isBatteryCritical: batteryCritical,
            isLowPowerEnabled: lowPowerEnabled,
            thermalState: thermalState,
            isThrottled: thermalState == .serious || thermalState == .critical
        )
    }

    struct PowerState {
        let batteryLevel: Float
        let isUnplugged: Bool
        let isBatteryLow: Bool
        let isBatteryCritical: Bool
        let isLowPowerEnabled: Bool
        let thermalState: ProcessInfo.ThermalState
        let isThrottled: Bool

        /// Whether the device is in a constrained state (low battery, hot, or low power mode)
        var isConstrained: Bool {
            isLowPowerEnabled || isThrottled || isBatteryLow
        }
    }
}

/// Configuration constants for the app
enum AppConfig {
    // MARK: - Analysis Settings
    static let analysisTimeLimitMs = 1000
    static let analysisDefaultMultiPV = 1
    static let analysisCoachMultiPV = 3

    // MARK: - Depth Caps
    static let depthCapNormal = 20
    static let depthCapThrottled = 14
    static let depthCapLowPower = 12

    // MARK: - Engine Settings
    static let engineIdleTimeoutSeconds: UInt64 = 3
    static let engineBaseThreads = 4
    static let engineBaseHash = 96
    static let engineLowPowerHash = 48
    static let engineThrottledHash = 64
    static let engineReadTimeoutSeconds: Double = 30

    // MARK: - Storage Settings
    static let defaultStorageCapMB = 500

    // MARK: - API Settings
    static let apiRequestTimeoutSeconds: TimeInterval = 30
    static let apiResourceTimeoutSeconds: TimeInterval = 60
    static let apiRateLimitDelayNs: UInt64 = 100_000_000 // 100ms

    // MARK: - PGN Settings
    static let pgnMaxSizeBytes = 1_000_000
}

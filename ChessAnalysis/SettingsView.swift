import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @AppStorage("review.showBestMove") private var showBestMove = false
    @State private var storageUsedBytes: Int64 = 0
    @State private var deviceStorage: DeviceStorageInfo = .empty

    var body: some View {
        NavigationStack {
            Form {
                Section("Chess.com") {
                    TextField("Username", text: $settings.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Analysis") {
                    Toggle("Coach lines (MultiPV 3)", isOn: $settings.coachLines)
                    Toggle("Low power analysis", isOn: Binding(
                        get: { settings.lowPowerAnalysis },
                        set: { settings.setLowPowerAnalysisFromUser($0) }
                    ))
                    Text("Less accurate analysis, but uses fewer system resources and is a lot faster to run. Auto-enabled under 10% battery.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Toggle("Show best move", isOn: $showBestMove)
                }

                Section("Board Theme") {
                    NavigationLink("Board Theme") {
                        BoardThemePickerView()
                    }
                }

                Section("Storage") {
                    Stepper(value: $settings.storageCapMB, in: 100...2000, step: 50) {
                        Text("Storage cap: \(settings.storageCapMB) MB")
                    }
                    storageUsageBar
                    Text("Oldest analyzed games are overwritten when you exceed the cap.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("Offline") {
                    Text("Downloaded games are the only ones stored locally. Analysis runs entirely on device.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                settings.autoUpdateLowPowerIfNeeded()
                Task { await refreshStorageUsage() }
            }
            .onChange(of: settings.storageCapMB) { _, _ in
                Task { await refreshStorageUsage() }
            }
        }
    }

    private var storageUsageBar: some View {
        let appBytes = min(storageUsedBytes, deviceStorage.totalBytes)
        let otherBytes = max(deviceStorage.totalBytes - deviceStorage.availableBytes - appBytes, 0)
        let availableBytes = deviceStorage.availableBytes
        let totalBytes = max(deviceStorage.totalBytes, 1)
        let appRatio = Double(appBytes) / Double(totalBytes)
        let otherRatio = Double(otherBytes) / Double(totalBytes)
        let greenColor = Color(red: 0.41, green: 0.57, blue: 0.24)
        let grayColor = Color.gray.opacity(0.6)
        let darkGrayColor = Color.gray.opacity(0.3)
        return VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let appWidth = width * CGFloat(appRatio)
                let otherWidth = width * CGFloat(otherRatio)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(darkGrayColor)
                    HStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(greenColor)
                            .frame(width: appWidth)
                        Rectangle()
                            .fill(grayColor)
                            .frame(width: otherWidth)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .frame(height: 8)
            VStack(spacing: 4) {
                storageLegendRow(color: greenColor, label: "ChessAnalysis", value: formatBytes(appBytes))
                storageLegendRow(color: grayColor, label: "Other", value: formatBytes(otherBytes))
                storageLegendRow(color: darkGrayColor, label: "Available", value: formatBytes(availableBytes))
            }
        }
    }

    private func storageLegendRow(color: Color, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
                .font(.caption)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 {
            return String(format: "%.1f GB", gb)
        }
        let mb = Double(bytes) / 1_048_576
        return String(format: "%.1f MB", mb)
    }

    private func refreshStorageUsage() async {
        Task.detached {
            let appBytes = await appStorageBytes()
            let device = DeviceStorageInfo.load()
            await MainActor.run {
                storageUsedBytes = appBytes
                deviceStorage = device
            }
        }
    }

    private func formatMB(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_048_576
        return String(format: "%.1f MB", mb)
    }

    private func formatGB(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        return String(format: "%.1f GB", gb)
    }

    private func appStorageBytes() async -> Int64 {
        let bundleBytes = directorySize(Bundle.main.bundleURL)
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        return bundleBytes
            + directorySize(documents)
            + directorySize(library)
            + directorySize(caches)
    }

    private func directorySize(_ url: URL?) -> Int64 {
        guard let url else { return 0 }
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: keys) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            let size = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0
            total += Int64(size)
        }
        return total
    }
}

private struct DeviceStorageInfo: Hashable {
    let totalBytes: Int64
    let availableBytes: Int64

    nonisolated static let empty = DeviceStorageInfo(totalBytes: 0, availableBytes: 0)

    nonisolated static func load() -> DeviceStorageInfo {
        guard let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]) else {
            return .empty
        }
        let total = Int64(values.volumeTotalCapacity ?? 0)
        let available = Int64(values.volumeAvailableCapacityForImportantUsage ?? 0)
        return DeviceStorageInfo(totalBytes: total, availableBytes: available)
    }
}

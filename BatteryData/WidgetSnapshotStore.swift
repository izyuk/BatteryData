import Foundation

enum WidgetSnapshotStore {
    static let appGroupID = "group.com.DmytroIziuk.BatteryData"
    static let snapshotFilename = "battery_widget_snapshot_v1.json"

    struct Payload: Codable {
        let percentage: Int?
        let isCharging: Bool?
        let onACPower: Bool?
        let timeToEmptyMin: Int?
        let timeToFullMin: Int?
        let watts: Double?
        let currentCapacitymAh: Int?
        let maxCapacitymAh: Int?
        let designCapacitymAh: Int?
        let cycleCount: Int?
        let updatedAt: Date
    }

    static func save(info: BatteryInfo, updatedAt: Date) {
        let payload = Payload(
            percentage: info.percentage,
            isCharging: info.isCharging,
            onACPower: info.onACPower,
            timeToEmptyMin: info.timeToEmptyMin,
            timeToFullMin: info.timeToFullMin,
            watts: info.watts,
            currentCapacitymAh: info.currentCapacity_mAh,
            maxCapacitymAh: info.maxCapacity_mAh,
            designCapacitymAh: info.designCapacity_mAh,
            cycleCount: info.cycleCount,
            updatedAt: updatedAt
        )

        guard let data = try? JSONEncoder().encode(payload) else { return }
        guard let fileURL = sharedFileURL() else { return }

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            return
        }
    }

    private static func sharedFileURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("Library/Caches", isDirectory: true)
            .appendingPathComponent(snapshotFilename)
    }
}

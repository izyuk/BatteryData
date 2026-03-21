import Foundation

enum WidgetSnapshotSharedStore {
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

    static func load() -> Payload? {
        guard let fileURL = sharedFileURL(),
              let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    private static func sharedFileURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("Library/Caches", isDirectory: true)
            .appendingPathComponent(snapshotFilename)
    }
}

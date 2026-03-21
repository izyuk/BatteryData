import Foundation
import IOKit
import IOKit.ps

struct BatteryWidgetSnapshot {
    let percentage: Int?
    let isCharging: Bool
    let onACPower: Bool
    let timeToEmptyMin: Int?
    let timeToFullMin: Int?
    let watts: Double?
    let currentCapacitymAh: Int?
    let maxCapacitymAh: Int?
    let designCapacitymAh: Int?
    let cycleCount: Int?
    let updatedAt: Date

    static let placeholder = BatteryWidgetSnapshot(
        percentage: 78,
        isCharging: false,
        onACPower: false,
        timeToEmptyMin: 164,
        timeToFullMin: nil,
        watts: -12.4,
        currentCapacitymAh: 4021,
        maxCapacitymAh: 5150,
        designCapacitymAh: 5600,
        cycleCount: 182,
        updatedAt: .now
    )

    static func load(now: Date = .now) -> BatteryWidgetSnapshot {
        if let shared = WidgetSnapshotSharedStore.load() {
            return BatteryWidgetSnapshot(
                percentage: shared.percentage,
                isCharging: shared.isCharging ?? false,
                onACPower: shared.onACPower ?? false,
                timeToEmptyMin: shared.timeToEmptyMin,
                timeToFullMin: shared.timeToFullMin,
                watts: shared.watts,
                currentCapacitymAh: shared.currentCapacitymAh,
                maxCapacitymAh: shared.maxCapacitymAh,
                designCapacitymAh: shared.designCapacitymAh,
                cycleCount: shared.cycleCount,
                updatedAt: shared.updatedAt
            )
        }

        guard let info = BatteryWidgetReader.read(now: now) else {
            return BatteryWidgetSnapshot(
                percentage: nil,
                isCharging: false,
                onACPower: false,
                timeToEmptyMin: nil,
                timeToFullMin: nil,
                watts: nil,
                currentCapacitymAh: nil,
                maxCapacitymAh: nil,
                designCapacitymAh: nil,
                cycleCount: nil,
                updatedAt: now
            )
        }
        return info
    }

    var percentageText: String {
        percentage.map { "\($0)%" } ?? "--"
    }

    var symbolName: String {
        if onACPower && isCharging { return "bolt.batteryblock.fill" }
        if onACPower { return "powerplug" }
        return "battery.100"
    }

    var primaryStatusLine: String {
        if onACPower && isCharging, let timeToFullMin, timeToFullMin > 0 {
            return "Charging, full in \(Self.format(mins: timeToFullMin))"
        }
        if onACPower {
            return "On AC power"
        }
        if let timeToEmptyMin, timeToEmptyMin > 0 {
            return "Battery, \(Self.format(mins: timeToEmptyMin)) left"
        }
        return "Battery status unavailable"
    }

    var secondaryStatusLine: String? {
        if let watts {
            return "Battery power \(Self.format(watts: watts))"
        }
        return nil
    }

    var tertiaryStatusLine: String? {
        guard let percentage else { return nil }
        if onACPower && isCharging {
            return "Current charge is \(percentage)% with external power connected."
        }
        if onACPower {
            return "Current charge is \(percentage)% while running on AC power."
        }
        return "Current charge is \(percentage)% while running on battery."
    }

    var wattsText: String {
        guard let watts else { return "--" }
        return Self.format(watts: watts)
    }

    var capacityText: String {
        guard let currentCapacitymAh else { return "--" }
        if let maxCapacitymAh {
            return "\(Self.format(mAh: currentCapacitymAh)) / \(Self.format(mAh: maxCapacitymAh))"
        }
        return Self.format(mAh: currentCapacitymAh)
    }

    var healthText: String {
        guard let designCapacitymAh, let maxCapacitymAh, designCapacitymAh > 0 else { return "--" }
        let health = Int((Double(maxCapacitymAh) / Double(designCapacitymAh) * 100.0).rounded())
        return "\(health)%"
    }

    var cyclesText: String {
        cycleCount.map(String.init) ?? "--"
    }

    var updatedText: String {
        updatedAt.formatted(date: .omitted, time: .shortened)
    }

    var batteryStateText: String {
        if onACPower && isCharging {
            return "Charging"
        }
        if onACPower {
            return "Plugged In"
        }
        return "On Battery"
    }

    var timeSummaryText: String {
        if onACPower && isCharging, let timeToFullMin, timeToFullMin > 0 {
            return "Full in \(Self.format(mins: timeToFullMin))"
        }
        if let timeToEmptyMin, timeToEmptyMin > 0 {
            return "\(Self.format(mins: timeToEmptyMin)) left"
        }
        return "--"
    }

    var designCapacityText: String {
        guard let designCapacitymAh else { return "--" }
        return Self.format(mAh: designCapacitymAh)
    }

    private static func format(mins: Int) -> String {
        let hours = mins / 60
        let minutes = mins % 60
        return hours > 0 ? "\(hours)h \(String(format: "%02dm", minutes))" : "\(minutes)m"
    }

    private static func format(watts: Double) -> String {
        let sign = watts >= 0 ? "+" : "-"
        return "\(sign)\(String(format: "%.1f", abs(watts))) W"
    }

    private static func format(mAh: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        return (formatter.string(from: NSNumber(value: mAh)) ?? "\(mAh)") + " mAh"
    }
}

private enum BatteryWidgetReader {
    static func read(now: Date) -> BatteryWidgetSnapshot? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        var percentage: Int?
        var isCharging = false
        var onACPower = false
        var timeToEmptyMin: Int?
        var timeToFullMin: Int?

        for powerSource in list {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, powerSource)?.takeUnretainedValue() as? [String: Any],
                  (desc[kIOPSTypeKey as String] as? String) == kIOPSInternalBatteryType as String
            else { continue }

            if let current = desc[kIOPSCurrentCapacityKey as String] as? Int,
               let max = desc[kIOPSMaxCapacityKey as String] as? Int,
               max > 0 {
                percentage = Int((Double(current) / Double(max)) * 100.0 + 0.5)
            }

            isCharging = desc[kIOPSIsChargingKey as String] as? Bool ?? false
            if let state = desc[kIOPSPowerSourceStateKey as String] as? String {
                onACPower = state == kIOPSACPowerValue
            }

            let unknown = kIOPSTimeRemainingUnknown
            let unlimited = kIOPSTimeRemainingUnlimited

            if let tte = desc[kIOPSTimeToEmptyKey as String] as? Double,
               tte != unknown, tte != unlimited {
                timeToEmptyMin = Int(tte)
            }

            if let ttf = desc[kIOPSTimeToFullChargeKey as String] as? Double,
               ttf != unknown, ttf != unlimited {
                timeToFullMin = Int(ttf)
            }
        }

        let sysEstimateSec = IOPSGetTimeRemainingEstimate()
        if sysEstimateSec != kIOPSTimeRemainingUnknown, sysEstimateSec != kIOPSTimeRemainingUnlimited {
            let minutes = max(0, Int((sysEstimateSec / 60.0).rounded()))
            if onACPower && isCharging {
                timeToFullMin = minutes
            } else {
                timeToEmptyMin = minutes
            }
        }

        let registry = readBatteryRegistry()
        return BatteryWidgetSnapshot(
            percentage: percentage,
            isCharging: isCharging,
            onACPower: onACPower,
            timeToEmptyMin: timeToEmptyMin,
            timeToFullMin: timeToFullMin,
            watts: registry.watts,
            currentCapacitymAh: registry.currentCapacitymAh,
            maxCapacitymAh: registry.maxCapacitymAh,
            designCapacitymAh: registry.designCapacitymAh,
            cycleCount: registry.cycleCount,
            updatedAt: now
        )
    }

    private struct BatteryRegistryData {
        let watts: Double?
        let currentCapacitymAh: Int?
        let maxCapacitymAh: Int?
        let designCapacitymAh: Int?
        let cycleCount: Int?
    }

    private static func readBatteryRegistry() -> BatteryRegistryData {
        guard let matching = IOServiceMatching("AppleSmartBattery") else {
            return BatteryRegistryData(watts: nil, currentCapacitymAh: nil, maxCapacitymAh: nil, designCapacitymAh: nil, cycleCount: nil)
        }

        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != IO_OBJECT_NULL else {
            return BatteryRegistryData(watts: nil, currentCapacitymAh: nil, maxCapacitymAh: nil, designCapacitymAh: nil, cycleCount: nil)
        }
        defer { IOObjectRelease(service) }

        var properties: Unmanaged<CFMutableDictionary>?
        let status = IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0)
        guard status == KERN_SUCCESS,
              let dictionary = properties?.takeRetainedValue() as? [String: Any] else {
            return BatteryRegistryData(watts: nil, currentCapacitymAh: nil, maxCapacitymAh: nil, designCapacitymAh: nil, cycleCount: nil)
        }

        let millivolts = dictionary["Voltage"] as? Int
        let milliamps = (dictionary["Amperage"] as? Int) ?? (dictionary["InstantAmperage"] as? Int)
        let watts: Double?
        if let millivolts, let milliamps {
            watts = (Double(millivolts) * Double(milliamps)) / 1_000_000.0
        } else {
            watts = nil
        }

        return BatteryRegistryData(
            watts: watts,
            currentCapacitymAh: pickCapacity([
                dictionary["CurrentCapacity"] as? Int,
                dictionary["AppleRawCurrentCapacity"] as? Int,
                dictionary["RemainingCapacity"] as? Int
            ]),
            maxCapacitymAh: pickCapacity([
                dictionary["MaxCapacity"] as? Int,
                dictionary["FullChargeCapacity"] as? Int,
                dictionary["AppleRawMaxCapacity"] as? Int
            ]),
            designCapacitymAh: pickCapacity([
                dictionary["DesignCapacity"] as? Int,
                dictionary["NominalChargeCapacity"] as? Int,
                dictionary["AppleRawDesignCapacity"] as? Int
            ]),
            cycleCount: dictionary["CycleCount"] as? Int
        )
    }

    private static func pickCapacity(_ values: [Int?]) -> Int? {
        let validValues = values.compactMap { $0 }
        let picked = validValues.first(where: { $0 > 100 && $0 < 200_000 }) ?? validValues.max()
        guard let picked else { return nil }
        return picked >= 1_000_000 ? picked / 10 : picked
    }
}

//
//  BatteryReader.swift
//  BatteryData
//
//  Created by Dmytro Izyuk on 11.09.2025.
//

import Foundation
import IOKit
import IOKit.ps

enum AdapterKind: String {
    case magsafe = "MagSafe"
    case usbc    = "USB-C PD"
    case unknown = "AC"
}

struct BatteryInfo {
    var percentage: Int?
    var isCharging: Bool?
    var onACPower: Bool?
    var timeToEmptyMin: Int?
    var timeToFullMin: Int?

    // Electrical (IORegistry)
    var voltage_mV: Int?
    var amperage_mA: Int?
    var watts: Double? {                   // мВ * мА → Вт
        guard let v = voltage_mV, let a = amperage_mA else { return nil }
        return (Double(v) * Double(a)) / 1_000_000.0
    }
    var currentCapacity_mAh: Int?          // поточний заряд (для фолбек-ETA)

    // Health
    var cycleCount: Int?
    var designCapacity_mAh: Int?
    var maxCapacity_mAh: Int?
    var temperatureC: Double?
    var healthPercent: Int? {
        guard let d = designCapacity_mAh, let m = maxCapacity_mAh, d > 0 else { return nil }
        let h = (Double(m) / Double(d)) * 100.0
        guard h >= 5, h <= 150 else { return nil }
        return Int(h.rounded())
    }

    // Adapter
    var adapterWatts: Int?
    var adapterKind: AdapterKind?

    static let empty = BatteryInfo(
        percentage: nil, isCharging: nil, onACPower: nil,
        timeToEmptyMin: nil, timeToFullMin: nil,
        voltage_mV: nil, amperage_mA: nil, currentCapacity_mAh: nil,
        cycleCount: nil, designCapacity_mAh: nil, maxCapacity_mAh: nil,
        temperatureC: nil,
        adapterWatts: nil, adapterKind: nil
    )

    var statusText: String {
        if let onAC = onACPower, onAC { return (isCharging == true) ? "Charging (AC)" : "On AC Power" }
        return "On Battery"
    }

    var sfSymbol: String {
        if onACPower == true && isCharging == true { return "bolt.batteryblock.fill" }
        if onACPower == true { return "powerplug" }
        return "battery.100"
    }

    static func format(mins: Int) -> String {
        let h = mins / 60, m = mins % 60
        return h > 0 ? "\(h)h \(String(format: "%02dm", m))" : "\(m)m"
    }
}

enum BatteryReader {
    static func read() -> BatteryInfo? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        var info = BatteryInfo.empty

        // 1) IOPS description (%, AC/Charging, ETA)
        for ps in list {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, ps)?
                    .takeUnretainedValue() as? [String: Any],
                  (desc[kIOPSTypeKey as String] as? String) == kIOPSInternalBatteryType as String
            else { continue }

            if let cur = desc[kIOPSCurrentCapacityKey as String] as? Int,
               let max = desc[kIOPSMaxCapacityKey as String] as? Int, max > 0 {
                info.percentage = Int((Double(cur) / Double(max)) * 100.0 + 0.5)
            }

            info.isCharging = desc[kIOPSIsChargingKey as String] as? Bool
            if let state = desc[kIOPSPowerSourceStateKey as String] as? String {
                info.onACPower = (state == kIOPSACPowerValue)
            }

            let unknown = kIOPSTimeRemainingUnknown
            let unlimited = kIOPSTimeRemainingUnlimited

            if let tte = desc[kIOPSTimeToEmptyKey as String] as? Double,
               tte != unknown, tte != unlimited { info.timeToEmptyMin = Int(tte) }
            if let ttf = desc[kIOPSTimeToFullChargeKey as String] as? Double,
               ttf != unknown, ttf != unlimited { info.timeToFullMin = Int(ttf) }
        }

        // 2) System ETA (sec → min)
        let sec = IOPSGetTimeRemainingEstimate()
        if sec != kIOPSTimeRemainingUnknown, sec != kIOPSTimeRemainingUnlimited {
            let mins = max(0, Int((sec / 60.0).rounded()))
            if info.onACPower == false || info.isCharging == false { info.timeToEmptyMin = mins }
            else { info.timeToFullMin = mins }
        }

        // 3) IORegistry (electrical + health + current mAh)
        let e = readBatteryIORegistry()
        info.voltage_mV         = e.mV
        info.amperage_mA        = e.mA
        info.cycleCount         = e.cycleCount
        info.designCapacity_mAh = e.designCapacity
        info.maxCapacity_mAh    = e.maxCapacity
        info.temperatureC       = e.temperatureC
        info.currentCapacity_mAh = e.current_mAh

        // 4) Adapter (kind + rated watts)
        let (kind, watts) = readAdapterKindAndWatts()
        info.adapterKind  = kind
        info.adapterWatts = watts

        return info
    }
}

// MARK: - IORegistry helpers

private struct Electrical {
    let mV: Int?
    let mA: Int?
    let cycleCount: Int?
    let designCapacity: Int?
    let maxCapacity: Int?
    let temperatureC: Double?
    let current_mAh: Int?
}

private func readBatteryIORegistry() -> Electrical {
    guard let matching = IOServiceMatching("AppleSmartBattery") else {
        return .init(mV: nil, mA: nil, cycleCount: nil, designCapacity: nil, maxCapacity: nil, temperatureC: nil, current_mAh: nil)
    }
    let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
    guard service != IO_OBJECT_NULL else {
        return .init(mV: nil, mA: nil, cycleCount: nil, designCapacity: nil, maxCapacity: nil, temperatureC: nil, current_mAh: nil)
    }
    defer { IOObjectRelease(service) }

    var props: Unmanaged<CFMutableDictionary>?
    let kr = IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0)
    guard kr == KERN_SUCCESS, let dict = props?.takeRetainedValue() as? [String: Any] else {
        return .init(mV: nil, mA: nil, cycleCount: nil, designCapacity: nil, maxCapacity: nil, temperatureC: nil, current_mAh: nil)
    }

    let mV = dict["Voltage"] as? Int
    let mA = (dict["Amperage"] as? Int) ?? (dict["InstantAmperage"] as? Int)

    let designCandidates = [
        dict["DesignCapacity"] as? Int,
        dict["NominalChargeCapacity"] as? Int,
        dict["AppleRawDesignCapacity"] as? Int
    ].compactMap { $0 }
    let maxCandidates = [
        dict["MaxCapacity"] as? Int,
        dict["FullChargeCapacity"] as? Int,
        dict["AppleRawMaxCapacity"] as? Int
    ].compactMap { $0 }
    let currentCandidates = [
        dict["CurrentCapacity"] as? Int,
        dict["AppleRawCurrentCapacity"] as? Int,
        dict["RemainingCapacity"] as? Int
    ].compactMap { $0 }

    func pickCapacity(_ values: [Int]) -> Int? {
        values.first(where: { $0 > 100 && $0 < 200_000 }) ?? values.max()
    }

    var design = pickCapacity(designCandidates)
    var maxCap = pickCapacity(maxCandidates)
    if let d = design, d >= 1_000_000 { design = d / 10 }
    if let m = maxCap, m >= 1_000_000 { maxCap = m / 10 }

    let tempC: Double?
    if let t = dict["Temperature"] as? Int {
        tempC = Double(t) / 10.0 - 273.15
    } else { tempC = nil }

    return .init(
        mV: mV, mA: mA, cycleCount: dict["CycleCount"] as? Int,
        designCapacity: design, maxCapacity: maxCap, temperatureC: tempC,
        current_mAh: pickCapacity(currentCandidates)
    )
}

// MARK: - Adapter helpers

private func readAdapterKindAndWatts() -> (AdapterKind?, Int?) {
    var kind: AdapterKind? = nil
    var watts: Int? = nil

    if let det = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] {
        if let w = det[kIOPSPowerAdapterWattsKey as String] as? Int { watts = w }
        else if let w = det[kIOPSPowerAdapterWattsKey as String] as? Double { watts = Int(w.rounded()) }
    }

    if let matching = IOServiceMatching("AppleSmartBattery") {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        if service != IO_OBJECT_NULL {
            defer { IOObjectRelease(service) }
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = props?.takeRetainedValue() as? [String: Any] {
                let conn = (dict["ChargingConnector"] as? String ??
                            dict["ChargerConnector"] as? String ??
                            (dict["ChargerData"] as? [String: Any])?["ChargingConnector"] as? String)?
                    .lowercased()
                let typeCFlag = (dict["TypeCConnected"] as? Bool) ?? false

                if typeCFlag || conn?.contains("type-c") == true || conn?.contains("usb-c") == true {
                    kind = .usbc
                } else if conn?.contains("magsafe") == true {
                    kind = .magsafe
                }
            }
        }
    }

    if kind == nil { kind = .unknown }
    return (kind, watts)
}

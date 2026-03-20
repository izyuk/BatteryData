//
//  BatteryDataTests.swift
//  BatteryDataTests
//
//  Created by Dmytro Izyuk on 11.09.2025.
//

import Testing
@testable import BatteryData

struct BatteryDataTests {

    @Test func parseBatteryMatchesNormalizedAddress() throws {
        let json = """
        {
          "SPBluetoothDataType": [
            {
              "device_connected": [
                {
                  "AirPods Pro": {
                    "device_address": "A8:91:3D:0C:EB:EA",
                    "device_batteryLevelLeft": "94%",
                    "device_batteryLevelRight": "91%",
                    "device_batteryLevelCase": "67%"
                  }
                }
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let result = SystemProfilerBluetoothReader.parseBattery(
            jsonData: json,
            address: "a8-91-3d-0c-eb-ea",
            deviceName: nil
        )

        #expect(result == AirPodsBatterySnapshot(device: nil, left: 94, right: 91, casePct: 67))
    }

    @Test func parseBatteryCanFallbackToNameMatching() throws {
        let json = """
        {
          "SPBluetoothDataType": [
            {
              "device_connected": [
                {
                  "My AirPods Pro 2": {
                    "device_address": "11:22:33:44:55:66",
                    "device_batteryLevelLeft": "88%",
                    "device_batteryLevelRight": "86%"
                  }
                }
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let result = SystemProfilerBluetoothReader.parseBattery(
            jsonData: json,
            address: nil,
            deviceName: "AirPods Pro"
        )

        #expect(result == AirPodsBatterySnapshot(device: nil, left: 88, right: 86, casePct: nil))
    }

    @Test func parseBatteryRejectsUnmatchedDevices() throws {
        let json = """
        {
          "SPBluetoothDataType": [
            {
              "device_connected": [
                {
                  "Magic Mouse": {
                    "device_address": "AA:BB:CC:DD:EE:FF",
                    "device_batteryLevel": "72%"
                  }
                }
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let result = SystemProfilerBluetoothReader.parseBattery(
            jsonData: json,
            address: nil,
            deviceName: "AirPods"
        )

        #expect(result == nil)
    }
    
    @Test func batteryViewModelUsesFallbackEtaFromPercentageTrend() throws {
        var samples = [
            BatteryInfo(
                percentage: 80, isCharging: false, onACPower: false,
                timeToEmptyMin: nil, timeToFullMin: nil,
                voltage_mV: 12000, amperage_mA: -1000, currentCapacity_mAh: 4000,
                cycleCount: nil, designCapacity_mAh: nil, maxCapacity_mAh: nil,
                temperatureC: nil, adapterWatts: nil, adapterKind: nil
            ),
            BatteryInfo(
                percentage: 70, isCharging: false, onACPower: false,
                timeToEmptyMin: nil, timeToFullMin: nil,
                voltage_mV: 12000, amperage_mA: -1000, currentCapacity_mAh: 3500,
                cycleCount: nil, designCapacity_mAh: nil, maxCapacity_mAh: nil,
                temperatureC: nil, adapterWatts: nil, adapterKind: nil
            )
        ]
        let start = Date(timeIntervalSince1970: 1_000)
        var currentDate = start
        
        let vm = BatteryViewModel(
            autoStart: false,
            readBatteryInfo: { samples.removeFirst() },
            notify: { _, _ in },
            now: { currentDate }
        )
        
        vm.refresh()
        currentDate = start.addingTimeInterval(600)
        vm.refresh()
        
        #expect(vm.usedFallbackEstimate == true)
        #expect(vm.info.timeToEmptyMin == 70)
    }
    
    @Test func batteryViewModelNotifiesWhenFullyChargedForTenMinutes() throws {
        var samples = [
            BatteryInfo(
                percentage: 100, isCharging: false, onACPower: true,
                timeToEmptyMin: nil, timeToFullMin: nil,
                voltage_mV: nil, amperage_mA: nil, currentCapacity_mAh: nil,
                cycleCount: nil, designCapacity_mAh: nil, maxCapacity_mAh: nil,
                temperatureC: nil, adapterWatts: nil, adapterKind: nil
            ),
            BatteryInfo(
                percentage: 100, isCharging: false, onACPower: true,
                timeToEmptyMin: nil, timeToFullMin: nil,
                voltage_mV: nil, amperage_mA: nil, currentCapacity_mAh: nil,
                cycleCount: nil, designCapacity_mAh: nil, maxCapacity_mAh: nil,
                temperatureC: nil, adapterWatts: nil, adapterKind: nil
            )
        ]
        let start = Date(timeIntervalSince1970: 2_000)
        var currentDate = start
        var notifications: [(String, String)] = []
        
        let vm = BatteryViewModel(
            autoStart: false,
            readBatteryInfo: { samples.removeFirst() },
            notify: { title, body in notifications.append((title, body)) },
            now: { currentDate }
        )
        
        vm.refresh()
        currentDate = start.addingTimeInterval(601)
        vm.refresh()
        
        #expect(notifications.count == 1)
        #expect(notifications.first?.0 == "Fully Charged")
    }
    
    @Test func batteryViewModelNotifiesLowBatteryThresholdsOncePerDischargeSession() throws {
        var samples = [
            BatteryInfo(
                percentage: 9, isCharging: false, onACPower: false,
                timeToEmptyMin: nil, timeToFullMin: nil,
                voltage_mV: nil, amperage_mA: nil, currentCapacity_mAh: nil,
                cycleCount: nil, designCapacity_mAh: nil, maxCapacity_mAh: nil,
                temperatureC: nil, adapterWatts: nil, adapterKind: nil
            ),
            BatteryInfo(
                percentage: 9, isCharging: false, onACPower: false,
                timeToEmptyMin: nil, timeToFullMin: nil,
                voltage_mV: nil, amperage_mA: nil, currentCapacity_mAh: nil,
                cycleCount: nil, designCapacity_mAh: nil, maxCapacity_mAh: nil,
                temperatureC: nil, adapterWatts: nil, adapterKind: nil
            ),
            BatteryInfo(
                percentage: 9, isCharging: false, onACPower: true,
                timeToEmptyMin: nil, timeToFullMin: nil,
                voltage_mV: nil, amperage_mA: nil, currentCapacity_mAh: nil,
                cycleCount: nil, designCapacity_mAh: nil, maxCapacity_mAh: nil,
                temperatureC: nil, adapterWatts: nil, adapterKind: nil
            ),
            BatteryInfo(
                percentage: 9, isCharging: false, onACPower: false,
                timeToEmptyMin: nil, timeToFullMin: nil,
                voltage_mV: nil, amperage_mA: nil, currentCapacity_mAh: nil,
                cycleCount: nil, designCapacity_mAh: nil, maxCapacity_mAh: nil,
                temperatureC: nil, adapterWatts: nil, adapterKind: nil
            )
        ]
        var notifications: [(String, String)] = []
        
        let vm = BatteryViewModel(
            autoStart: false,
            readBatteryInfo: { samples.removeFirst() },
            notify: { title, body in notifications.append((title, body)) }
        )
        
        vm.refresh()
        vm.refresh()
        vm.refresh()
        vm.refresh()
        
        #expect(notifications.map(\.0) == ["Low Battery", "Low Battery", "Low Battery", "Low Battery", "Low Battery", "Low Battery"])
    }
    
    @Test func batteryViewModelDetectsPowerSpikeAfterTenSeconds() throws {
        var samples = [
            BatteryInfo(
                percentage: 50, isCharging: false, onACPower: false,
                timeToEmptyMin: nil, timeToFullMin: nil,
                voltage_mV: 12000, amperage_mA: -500, currentCapacity_mAh: nil,
                cycleCount: nil, designCapacity_mAh: nil, maxCapacity_mAh: nil,
                temperatureC: nil, adapterWatts: nil, adapterKind: nil
            ),
            BatteryInfo(
                percentage: 49, isCharging: false, onACPower: false,
                timeToEmptyMin: nil, timeToFullMin: nil,
                voltage_mV: 12000, amperage_mA: -2000, currentCapacity_mAh: nil,
                cycleCount: nil, designCapacity_mAh: nil, maxCapacity_mAh: nil,
                temperatureC: nil, adapterWatts: nil, adapterKind: nil
            )
        ]
        let start = Date(timeIntervalSince1970: 3_000)
        var currentDate = start
        var notifications: [(String, String)] = []
        
        let vm = BatteryViewModel(
            autoStart: false,
            readBatteryInfo: { samples.removeFirst() },
            notify: { title, body in notifications.append((title, body)) },
            now: { currentDate }
        )
        
        vm.refresh()
        currentDate = start.addingTimeInterval(11)
        vm.refresh()
        
        #expect(notifications.contains { $0.0 == "Power Spike" })
    }

}

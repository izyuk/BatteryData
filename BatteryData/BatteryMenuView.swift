//
//  BatteryMenuView.swift
//  BatteryData
//
//  Created by Dmytro Izyuk on 11.09.2025.
//

import SwiftUI

struct BatteryMenuView: View {
    @ObservedObject var macVm: BatteryViewModel
    @StateObject private var devicesVm = DevicesBatteryViewModel()

    @State private var selectedTab: Tab = .mac

    enum Tab: String, CaseIterable, Identifiable {
        case mac = "Mac"
        case devices = "Devices"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // Якщо немає підключених навушників — UI 1-в-1 як було
            if devicesVm.connectedHeadphones.isEmpty {
                MacBatteryMenuContentView(vm: macVm)
            } else {

                // Tabs (segmented) у меню
                Picker("", selection: $selectedTab) {
                    Text("Mac").tag(Tab.mac)
                    Text("Devices").tag(Tab.devices)
                }
                .pickerStyle(.segmented)

                Group {
                    switch selectedTab {
                    case .mac:
                        MacBatteryMenuContentView(vm: macVm)

                    case .devices:
                        DevicesMenuContentView(vm: devicesVm)
                    }
                }
            }
        }
        .frame(width: 300)
        .padding(10)
        .onAppear {
            devicesVm.start()
        }
        .onDisappear {
            devicesVm.stop()
        }
    }
}

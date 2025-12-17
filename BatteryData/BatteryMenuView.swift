//
//  BatteryMenuView.swift
//  BatteryData
//
//  Created by Dmytro Izyuk on 11.09.2025.
//

import SwiftUI

struct BatteryMenuView: View {
    @ObservedObject var macVm: BatteryViewModel
    @StateObject private var headphonesVm = HeadphonesBatteryViewModel()

    @State private var selectedTab: Tab = .mac

    enum Tab: String, CaseIterable, Identifiable {
        case mac = "Mac"
        case headphones = "Headphones"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // Якщо немає підключених навушників — UI 1-в-1 як було
            if headphonesVm.connectedHeadphones.isEmpty {
                MacBatteryMenuContentView(vm: macVm)
            } else {

                // Tabs (segmented) у меню
                Picker("", selection: $selectedTab) {
                    Text("Mac").tag(Tab.mac)
                    Text("Headphones").tag(Tab.headphones)
                }
                .pickerStyle(.segmented)

                Group {
                    switch selectedTab {
                    case .mac:
                        MacBatteryMenuContentView(vm: macVm)

                    case .headphones:
                        HeadphonesMenuContentView(vm: headphonesVm)
                    }
                }
            }
        }
        .frame(width: 300)
        .padding(10)
        .onAppear {
            headphonesVm.start()
        }
        .onDisappear {
            headphonesVm.stop()
        }
    }
}

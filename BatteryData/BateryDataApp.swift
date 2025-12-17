//
//  BatteryDataApp.swift
//  BatteryData
//
//  Created by Dmytro Izyuk on 11.09.2025.
//

import SwiftUI

@main
struct BatteryDataApp: App {
    
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

       init() {
           UserDefaults.standard.register(defaults: [
               PrefKeys.refreshIntervalSec:      5.0,
               PrefKeys.estimationWindowMin:     3.0,
               PrefKeys.showWattsInStatusBar:    true,
               PrefKeys.chartDurationMin:        60.0,
               
               PrefKeys.statusBarExpandedInfo:   false,     // icon-only за замовчуванням
           ])

           Notifier.requestAuthorization()
       }
    
    var body: some Scene {
            Settings {
                SettingsView()
                    .frame(width: 460)
                    .padding()
            }
        }
}

//
//  AppDelegate.swift
//  BatteryData
//
//  Created by Dmytro Izyuk on 17.12.2025.
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let vm = BatteryViewModel()
    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBar = StatusBarController(vm: vm)
    }
}

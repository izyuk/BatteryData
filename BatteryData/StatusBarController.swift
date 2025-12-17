//
//  StatusBarController.swift
//  BatteryData
//
//  Created by Dmytro Izyuk on 17.12.2025.
//

import AppKit
import SwiftUI
import Combine

@MainActor
final class StatusBarController {
    private let statusItem: NSStatusItem
    private let popover: NSPopover

    private let vm: BatteryViewModel
    private var cancellables = Set<AnyCancellable>()
    private var defaultsObserver: Any?

    init(vm: BatteryViewModel) {
        self.vm = vm

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 320, height: 520)
        popover.contentViewController = NSHostingController(rootView: BatteryMenuView(macVm: vm))

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "bolt.circle", accessibilityDescription: nil)
            button.target = self
            button.action = #selector(togglePopover(_:))
        }

        // оновлення title при refresh()
        vm.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.updateTitle() }
            .store(in: &cancellables)

        // оновлення title при зміні prefs (compact mode, watts, etc.)
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateTitle()
            }
        }

        updateTitle()
    }

    deinit {
        if let obs = defaultsObserver { NotificationCenter.default.removeObserver(obs) }
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func updateTitle() {
        let expanded = UserDefaults.standard.bool(forKey: PrefKeys.statusBarExpandedInfo)

        statusItem.length = NSStatusItem.variableLength
        statusItem.button?.title = expanded ? vm.statusBarTitle() : ""
    }
}

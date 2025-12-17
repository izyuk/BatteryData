//
//  BatteryMenuView.swift
//  BatteryData
//
//  Created by Dmytro Izyuk on 11.09.2025.
//

import SwiftUI
import ServiceManagement
import AppKit

struct BatteryMenuView: View {
    @ObservedObject var vm: BatteryViewModel
    @Environment(\.openSettings) private var openAppSettings

    @State private var launchAtLogin = (SMAppService.mainApp.status == .enabled)
    @State private var launchError: String?

    // MARK: - Helpers

    private func wattsText(_ w: Double?) -> String {
        guard let w else { return "—" }
        let sign = w >= 0 ? "+" : "−"
        return "\(sign)\(String(format: "%.1f", abs(w))) W"
    }

    private func formatmAh(_ v: Int?) -> String {
        guard let v else { return "—" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = " "
        f.maximumFractionDigits = 0
        return (f.string(from: NSNumber(value: v)) ?? "\(v)") + " mAh"
    }

    private func showSettingsWindow() {
        if #available(macOS 14.0, *) {
            // Активуємо апку і просимо відкрити/показати Settings.
            NSApp.activate(ignoringOtherApps: true)
            openAppSettings()
            // Ще раз активуємо на наступному циклі — щоб гарантовано опинилось зверху.
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
            }
        } else {
            SettingsWindowPresenter.shared.show()
        }
    }

    // MARK: - UI

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            // Header
            HStack {
                Text("Battery").font(.headline)
                Spacer()
                Text(vm.info.percentage.map { "\($0)%" } ?? "—")
                    .font(.title3).monospacedDigit()
            }

            // Status
            Label(vm.info.statusText, systemImage: vm.info.sfSymbol)

            // Capacity
            if let full = vm.info.maxCapacity_mAh, let design = vm.info.designCapacity_mAh {
                Label("Capacity: \(formatmAh(full)) (design \(formatmAh(design)))",
                      systemImage: "gauge.with.dots.needle.33percent")
            } else if let full = vm.info.maxCapacity_mAh {
                Label("Capacity: \(formatmAh(full))", systemImage: "gauge.with.dots.needle.33percent")
            } else if let design = vm.info.designCapacity_mAh {
                Label("Design capacity: \(formatmAh(design))", systemImage: "gauge.with.dots.needle.33percent")
            }

            // Adapter (kind + rated watts)
            if vm.info.onACPower == true {
                let kind = vm.info.adapterKind?.rawValue ?? "AC"
                if let w = vm.info.adapterWatts {
                    Label("Adapter: \(kind) · \(w)W", systemImage: "powerplug")
                } else {
                    Label("Adapter: \(kind)", systemImage: "powerplug")
                }
            }

            // Battery net power (for the battery)
            Label("Battery power: \(wattsText(vm.info.watts))", systemImage: "bolt")

            // Adapter deficit warning
            if vm.info.onACPower == true, let w = vm.info.watts, w < 0 {
                Label(String(format: "Adapter deficit: −%.1f W", abs(w)),
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }

            // ETA (prefer discharge ETA on deficit)
            if vm.info.onACPower == true, let w = vm.info.watts, w < 0,
               let t = vm.info.timeToEmptyMin, t > 0 {
                let approx = vm.usedFallbackEstimate ? "≈ " : ""
                Label("Time to empty: \(approx)\(BatteryInfo.format(mins: t))",
                      systemImage: "clock.badge.exclamationmark")
                    .foregroundStyle(.secondary)
            } else if vm.info.isCharging == true,
                      let t = vm.info.timeToFullMin, t > 0 {
                Label("Time to full: \(BatteryInfo.format(mins: t))",
                      systemImage: "clock.badge.checkmark")
                    .foregroundStyle(.secondary)
            } else if let t = vm.info.timeToEmptyMin, t > 0 {
                Label("Time remaining: \(BatteryInfo.format(mins: t))",
                      systemImage: "clock")
                    .foregroundStyle(.secondary)
            }

            // Health
            if let h = vm.info.healthPercent { Label("Health: \(h)%", systemImage: "heart") }
            if let c = vm.info.cycleCount   { Label("Cycles: \(c)", systemImage: "arrow.3.trianglepath") }
            if let t = vm.info.temperatureC {
                Label(String(format: "Temp: %.1f°C", t), systemImage: "thermometer")
            }

            // Chart
            HistoryChartView(samples: vm.history)
                .padding(.top, 4)

            Divider().padding(.vertical, 6)

            // Controls
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onAppear { launchAtLogin = (SMAppService.mainApp.status == .enabled) }
                .onChange(of: launchAtLogin, initial: false) { _, newValue in
                    Task { @MainActor in
                        do {
                            if newValue { try SMAppService.mainApp.register() }
                            else        { try SMAppService.mainApp.unregister() }
                            launchAtLogin = (SMAppService.mainApp.status == .enabled)
                        } catch {
                            launchError = error.localizedDescription
                            launchAtLogin = (SMAppService.mainApp.status == .enabled)
                        }
                    }
                }

            HStack {
                Button("Refresh") { vm.refresh() }
                Spacer()
                Button("Settings…") { showSettingsWindow() }
                Button("Energy Settings…") {
                    let urls = [
                        "x-apple.systempreferences:com.apple.Battery",
                        "x-apple.systempreferences:com.apple.Battery-Settings.extension",
                        "x-apple.systempreferences:com.apple.preference.energysaver" // pre-Ventura
                    ]
                    for u in urls {
                        if let url = URL(string: u), NSWorkspace.shared.open(url) {
                            break
                        }
                    }
                }
            }

            Button(role: .destructive) { NSApp.terminate(nil) } label: { Text("Quit \(Bundle.main.appName)") }
        }
        .frame(width: 300)
        .padding(10)
        .alert("Launch at login", isPresented: Binding(
            get: { launchError != nil },
            set: { if !$0 { launchError = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(launchError ?? "") }
    }
}

// MARK: - Settings window fallback

final class SettingsWindowPresenter {
    static let shared = SettingsWindowPresenter()
    private var window: NSWindow?

    func show() {
        if let w = window {
            // Якщо вже є: розгорнути, підняти і зробити ключовим.
            w.deminiaturize(nil)
            w.orderFrontRegardless()
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let vc = NSHostingController(rootView: SettingsView())
        let w = NSWindow(contentViewController: vc)
        w.title = "Settings"
        w.styleMask = [.titled, .closable, .miniaturizable]
        w.setContentSize(NSSize(width: 480, height: 520))
        w.center()
        w.isReleasedWhenClosed = false

        window = w

        // Показуємо вперше: теж гарантовано піднімаємо нагору.
        w.makeKeyAndOrderFront(nil)
        w.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Helpers

private extension Bundle {
    var appName: String {
        if let d = object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, !d.isEmpty { return d }
        if let n = object(forInfoDictionaryKey: "CFBundleName") as? String, !n.isEmpty { return n }
        return "App"
    }
}

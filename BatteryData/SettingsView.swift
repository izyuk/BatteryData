//
//  SettingsView.swift
//  BateryData
//
//  Created by Dmytro Izyuk on 11.09.2025.
//

import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage(PrefKeys.refreshIntervalSec)   private var refresh = 5.0
    @AppStorage(PrefKeys.estimationWindowMin)  private var window  = 3.0
    @AppStorage(PrefKeys.chartDurationMin)     private var chart   = 60.0
    @AppStorage(PrefKeys.showWattsInStatusBar) private var showW   = true
    @AppStorage(PrefKeys.statusBarExpandedInfo) private var expandedInfo = false


    // Launch at login (macOS 13+)
    @State private var launchAtLogin = (SMAppService.mainApp.status == .enabled)
    @State private var statusText = SettingsView.statusDescription(SMAppService.mainApp.status)
    @State private var errorText: String?

    var body: some View {
        Form {
            // ── Startup ───────────────────────────────────────────────────────────────
            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin, initial: false) { _, newValue in
                        Task { @MainActor in
                            do {
                                if newValue {
                                    try SMAppService.mainApp.register()
                                } else {
                                    try SMAppService.mainApp.unregister()
                                }
                                let s = SMAppService.mainApp.status
                                launchAtLogin = (s == .enabled)
                                statusText = Self.statusDescription(s)
                            } catch {
                                errorText = error.localizedDescription
                                launchAtLogin = (SMAppService.mainApp.status == .enabled)
                            }
                        }
                    }

                HStack {
                    Text("Status: \(statusText)")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Login Items…") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }

            // ── Refresh & Estimation ────────────────────────────────────────────────
            Section("Refresh & Estimation") {
                HStack {
                    Text("Refresh interval")
                    Spacer()
                    Text("\(Int(refresh)) s").monospacedDigit()
                }
                Slider(value: $refresh, in: 1...30, step: 1)

                HStack {
                        Text("Estimation window")
                        Spacer()
                        Text("\(Int(window)) min").monospacedDigit()
                    }
                    Slider(value: $window, in: 1...10, step: 1)

                    Text("Uses % trend only while discharging (on battery or when adapter deficit). Not used during charging; time to full comes from system.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true) // щоб переносився текст
            }

            // ── Status Bar ───────────────────────────────────────────────────────────
            Section("Status Bar") {
                Toggle("Expanded battery info in status bar", isOn: $expandedInfo)
            }

            // ── History Chart ────────────────────────────────────────────────────────
            Section("History Chart") {
                HStack {
                    Text("Chart duration")
                    Spacer()
                    Text("\(Int(chart)) min").monospacedDigit()
                }
                Slider(value: $chart, in: 10...120, step: 5)
            }

            // ── Notifications ────────────────────────────────────────────────────────
            Section("Notifications") {
                Button("Open System Notification Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .onAppear {
            let s = SMAppService.mainApp.status
            launchAtLogin = (s == .enabled)
            statusText = Self.statusDescription(s)
        }
        .alert("Launch at login", isPresented: Binding(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
        .frame(width: 460)
        .padding()
    }

    private static func statusDescription(_ s: SMAppService.Status) -> String {
        switch s {
        case .enabled: return "Enabled"
        case .requiresApproval: return "Requires approval in System Settings"
        case .notRegistered, .notFound: return "Disabled"
        @unknown default: return "Unknown"
        }
    }
}

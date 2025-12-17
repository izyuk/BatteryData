import SwiftUI

struct HeadphonesMenuContentView: View {
    @ObservedObject var vm: HeadphonesBatteryViewModel

    private func percentText(_ p: Int?) -> String {
        guard let p else { return "—" }
        return "\(p)%"
    }

    private func timeText(_ d: Date?) -> String {
        guard let d else { return "—" }
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: d)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            HStack {
                Text("Headphones").font(.headline)
                Spacer()
                Button("Refresh") { vm.refresh() }
            }

            if let e = vm.errorText, !e.isEmpty {
                Label(e, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }

            if vm.connectedHeadphones.isEmpty {
                Label("No headphones connected", systemImage: "airpods")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(vm.connectedHeadphones) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(item.name)
                                .font(.subheadline)
                                .lineLimit(1)
                            Spacer()
                            Text(percentText(item.batteryPercent))
                                .font(.title3)
                                .monospacedDigit()
                        }

                        HStack(spacing: 12) {
                            Label("Battery", systemImage: "battery.100")
                                .foregroundStyle(.secondary)

                            Text(percentText(item.batteryPercent))
                                .foregroundStyle(.secondary)

                            Spacer()

                            Text("Updated: \(timeText(item.lastUpdated))")
                                .foregroundStyle(.secondary)
                                .font(.footnote)
                        }
                    }

                    Divider().padding(.vertical, 4)
                }
            }
        }
    }
}

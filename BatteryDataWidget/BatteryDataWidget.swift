import SwiftUI
import WidgetKit

struct BatteryWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: BatteryWidgetSnapshot
}

struct BatteryWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> BatteryWidgetEntry {
        BatteryWidgetEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (BatteryWidgetEntry) -> Void) {
        completion(BatteryWidgetEntry(date: .now, snapshot: BatteryWidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BatteryWidgetEntry>) -> Void) {
        let entry = BatteryWidgetEntry(date: .now, snapshot: BatteryWidgetSnapshot.load())
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 5, to: .now) ?? .now.addingTimeInterval(300)
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }
}

struct BatteryDataWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family

    let entry: BatteryWidgetEntry

    var body: some View {
        switch family {
        case .systemLarge:
            largeView
        case .systemMedium:
            mediumView
        default:
            smallView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            Text(entry.snapshot.percentageText)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(entry.snapshot.primaryStatusLine)
                .font(.subheadline.weight(.semibold))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 2)

            VStack(alignment: .leading, spacing: 5) {
                metricLine(title: "Power", value: entry.snapshot.wattsText)
                metricLine(title: "Time", value: entry.snapshot.timeSummaryText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [
                    Color.green.opacity(0.18),
                    Color.blue.opacity(0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var mediumView: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                header

                Text(entry.snapshot.percentageText)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(entry.snapshot.primaryStatusLine)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let secondary = entry.snapshot.secondaryStatusLine {
                    Text(secondary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
            }
            .layoutPriority(1)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 6) {
                metricLine(title: "Power", value: entry.snapshot.wattsText)
                metricLine(title: "Capacity", value: entry.snapshot.capacityText)
                metricLine(title: "Health", value: entry.snapshot.healthText)
                metricLine(title: "Cycles", value: entry.snapshot.cyclesText)
                metricLine(title: "Time", value: entry.snapshot.timeSummaryText)
            }
            .frame(width: 136, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [
                    Color.green.opacity(0.18),
                    Color.blue.opacity(0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(entry.snapshot.percentageText)
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.45)

                    Text(entry.snapshot.primaryStatusLine)
                        .font(.title2.weight(.semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if let secondary = entry.snapshot.secondaryStatusLine {
                        Text(secondary)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }

                    if let tertiary = entry.snapshot.tertiaryStatusLine {
                        Text(tertiary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)
                    }
                }
                .layoutPriority(1)

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 8) {
                    metricLine(title: "Power", value: entry.snapshot.wattsText)
                    metricLine(title: "Capacity", value: entry.snapshot.capacityText)
                    metricLine(title: "Health", value: entry.snapshot.healthText)
                    metricLine(title: "Cycles", value: entry.snapshot.cyclesText)
                    metricLine(title: "Updated", value: entry.snapshot.updatedText)
                }
                .frame(width: 150, alignment: .leading)
            }

            HStack(spacing: 8) {
                footerBadge(title: "State", value: entry.snapshot.batteryStateText)
                footerBadge(title: "Time", value: entry.snapshot.timeSummaryText)
                footerBadge(title: "Design", value: entry.snapshot.designCapacityText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [
                    Color.green.opacity(0.18),
                    Color.blue.opacity(0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var header: some View {
        HStack {
            Label("Battery", systemImage: entry.snapshot.symbolName)
                .font(.headline)
            Spacer()
        }
    }

    private func metricLine(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
    }

    private func footerBadge(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(.white.opacity(0.28), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct BatteryDataWidget: Widget {
    let kind: String = "BatteryDataWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BatteryWidgetProvider()) { entry in
            BatteryDataWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Battery Overview")
        .description("Shows the current Mac battery status, ETA, power draw, and health.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct BatteryDataWidgetBundle: WidgetBundle {
    var body: some Widget {
        BatteryDataWidget()
    }
}

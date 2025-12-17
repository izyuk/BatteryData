//
//  HistoryChartView.swift
//  BateryData
//
//  Created by Dmytro Izyuk on 11.09.2025.
//

import SwiftUI
import Charts

struct HistorySample: Identifiable {
    let t: Date
    let percent: Int?
    let watts: Double?
    var id: Date { t }
}

private struct PercentPoint: Identifiable {
    let t: Date
    let p: Int
    var id: Date { t }
}

private struct WattsPoint: Identifiable {
    let t: Date
    let w: Double
    var id: Date { t }
}

struct HistoryChartView: View {
    let samples: [HistorySample]

    private var percentSeries: [PercentPoint] {
        samples.compactMap { s in
            guard let p = s.percent else { return nil }
            return PercentPoint(t: s.t, p: p)
        }
    }

    private var wattsSeries: [WattsPoint] {
        samples.compactMap { s in
            guard let w = s.watts else { return nil }
            return WattsPoint(t: s.t, w: w)
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            // % графік
            Chart(percentSeries) { pt in
                LineMark(
                    x: .value("Time", pt.t),
                    y: .value("%", pt.p)
                )
                .interpolationMethod(.linear)
            }
            .frame(height: 80)

            // W графік
            Chart(wattsSeries) { pt in
                LineMark(
                    x: .value("Time", pt.t),
                    y: .value("W", pt.w)
                )
                .foregroundStyle(Color.secondary)   // явно, щоб не було інференсу
                .interpolationMethod(.linear)
            }
            .frame(height: 80)
        }
    }
}

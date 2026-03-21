//
//  BatteryViewModel.swift
//  BatteryData
//
//  Created by Dmytro Izyuk on 11.09.2025.
//

import Foundation
import Combine
#if canImport(WidgetKit)
import WidgetKit
#endif

final class BatteryViewModel: ObservableObject {
    @Published private(set) var info = BatteryInfo.empty
    @Published private(set) var usedFallbackEstimate = false
    @Published private(set) var history: [HistorySample] = []
    
    private var timer: AnyCancellable?
    private var defaultsObserver: Any?
    
    // Notifications
    private var lowNotified: Set<Int> = []
    private var fullChargeStart: Date?
    private var fullNotified = false
    private var lastSpikeAt: Date?
    private var lastWidgetReloadAt: Date?
    private var lastWidgetReloadSignature: WidgetReloadSignature?
    
    // Prefs
    private var refreshIntervalSec: TimeInterval { UserDefaults.standard.double(forKey: PrefKeys.refreshIntervalSec) }
    private var estimationWindowSec: TimeInterval { UserDefaults.standard.double(forKey: PrefKeys.estimationWindowMin) * 60.0 }
    private var chartDurationSec: TimeInterval { UserDefaults.standard.double(forKey: PrefKeys.chartDurationMin) * 60.0 }
    //    private var showWattsInStatusBar: Bool { UserDefaults.standard.bool(forKey: PrefKeys.showWattsInStatusBar) }
    private var compactLabel: Bool { UserDefaults.standard.bool(forKey: PrefKeys.compactLabel) }
    
    // AC deficit: adapter doesn't cover load → battery discharges
    private var exactAdapterDeficit: Bool { info.onACPower == true && (info.watts ?? 0) < 0 }
    private var estimatedAdapterDeficit: Bool {
        guard info.onACPower == true, exactAdapterDeficit == false else { return false }
        guard info.isCharging != true else { return false }
        guard let timeToEmptyMin = info.timeToEmptyMin, timeToEmptyMin > 0 else { return false }
        return true
    }
    private var adapterDeficit: Bool { exactAdapterDeficit || estimatedAdapterDeficit }
    
    // Samples for trend ETA
    private var samplesForEta: [(t: Date, p: Int)] = []
    
    private let readBatteryInfo: () -> BatteryInfo?
    private let notify: (String, String) -> Void
    private let now: () -> Date
    
    init(
        autoStart: Bool = true,
        readBatteryInfo: @escaping () -> BatteryInfo? = { BatteryReader.read() },
        notify: @escaping (String, String) -> Void = { title, body in
            Notifier.notify(title: title, body: body)
        },
        now: @escaping () -> Date = Date.init
    ) {
        self.readBatteryInfo = readBatteryInfo
        self.notify = notify
        self.now = now
        
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.restartTimerIfNeeded()
            self?.objectWillChange.send()
        }
        if autoStart {
            refresh()
            startAutoRefresh()
        }
    }
    
    deinit {
        if let obs = defaultsObserver { NotificationCenter.default.removeObserver(obs) }
        timer?.cancel()
    }
    
    // MARK: - Timer
    
    private var lastInterval: TimeInterval = 0
    
    private func clampedRefreshInterval() -> TimeInterval {
        // 0.5…3600 сек — запобігаємо 0
        let v = refreshIntervalSec
        return min(max(v, 0.5), 3600)
    }
    
    func startAutoRefresh() {
        timer?.cancel()
        lastInterval = clampedRefreshInterval()
        refresh() // миттєве оновлення після зміни налаштувань
        timer = Timer.publish(every: lastInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }
    
    private func restartTimerIfNeeded() {
        let newInt = clampedRefreshInterval()
        if abs(newInt - lastInterval) > 0.001 {
            startAutoRefresh()
        } else {
            // якщо змінювались не інтервали, а інші prefs — все одно перерахуй
            refresh()
        }
    }
    
    // MARK: - Title formatting
    
    private func shortMins(_ mins: Int) -> String {
        let h = mins / 60, m = mins % 60
        return h > 0 ? "\(h)h \(String(format: "%02dm", m))" : "\(m)m"
    }
    
    private func shortWatts(_ w: Double?) -> String? {
        guard let w else { return nil }
        let sign = w >= 0 ? "+" : "−"
        return "\(sign)\(String(format: "%.1f", abs(w)))W"
    }
    
    /// Побудова ETA з урахуванням дефіциту/заряджання
    private func currentETAString(prefixApprox: Bool) -> String? {
        let approx = usedFallbackEstimate ? "≈ " : ""
        if adapterDeficit, let t = info.timeToEmptyMin { return (prefixApprox ? approx : "") + shortMins(t) }
        if info.isCharging == true, let t = info.timeToFullMin { return shortMins(t) }
        if let t = info.timeToEmptyMin { return (prefixApprox ? approx : "") + shortMins(t) }
        return nil
    }
    
    /// Базовий/компактний рядок (з можливістю приховати ETA або Watts)
    private func buildTitle() -> String {
        let pctValue = info.percentage
        let pct = pctValue.map { "\($0)%" } ?? "—"
        
        // ✅ 100% + AC → only %
        if pctValue == 100, info.onACPower == true {
            return " \(pct)"
        }
        
        //        let bolt = (info.isCharging == true) ? " ⚡︎" : ""
        let warn = adapterDeficit ? " ⚠︎" : ""
        let eta   = currentETAString(prefixApprox: true)
        let watts = shortWatts(info.watts)
        
        switch (eta, watts) {
        case let (e?, w?): return " \(pct) · \(e) · \(w)\(warn)"
        case let (e?, nil): return " \(pct) · \(e)\(warn)"
        case let (nil, w?): return " \(pct) · \(w)\(warn)"
        default:            return " \(pct) · \(warn)"
        }
    }
    
    func statusBarTitle() -> String {
        buildTitle()
    }

    var showsExactAdapterDeficit: Bool {
        exactAdapterDeficit
    }

    var showsEstimatedAdapterDeficit: Bool {
        estimatedAdapterDeficit
    }
    
    // MARK: - Refresh & ETA
    
    func refresh() {
        let previousInfo = info
        let previousFallback = usedFallbackEstimate
        let currentTime = now()
        usedFallbackEstimate = false
        let newInfo = readBatteryInfo() ?? .empty
        info = newInfo
        
        appendHistory(info: newInfo)
        
        if let p = newInfo.percentage {
            samplesForEta.append((currentTime, p))
            let cutoff = currentTime.addingTimeInterval(-estimationWindowSec)
            samplesForEta.removeAll { $0.t < cutoff }
        }
        
        // Discharge ETAs (на батареї або при дефіциті на AC)
        let needsDischargeETA = (newInfo.onACPower == false) ||
        (newInfo.onACPower == true && (newInfo.watts ?? 0) < 0)
        
        if needsDischargeETA, (newInfo.timeToEmptyMin == nil || newInfo.timeToEmptyMin == 0) {
            
            // 1) Тренд (%/хв)
            if let est = estimateMinutesLeftFromSamples(windowSec: estimationWindowSec) {
                var patched = newInfo
                patched.timeToEmptyMin = est
                info = patched
                usedFallbackEstimate = true
                
                // 2) Миттєва потужність: Wh / |W|
            } else if let cur = newInfo.currentCapacity_mAh,
                      let mv  = newInfo.voltage_mV,
                      let w   = newInfo.watts, w < 0
            {
                // залишкова енергія ≈ (mAh * mV) / 1e6 = Wh
                let remainingWh = (Double(cur) * Double(mv)) / 1_000_000.0
                let minutesD = (remainingWh / abs(w)) * 60.0
                if minutesD.isFinite, minutesD > 0 {
                    let minutes = Int(minutesD.rounded())
                    var patched = newInfo
                    patched.timeToEmptyMin = minutes
                    info = patched
                    usedFallbackEstimate = true
                }
            }
        }
        
        WidgetSnapshotStore.save(info: info, updatedAt: currentTime)
        handleNotifications(old: newInfo)
        reloadWidgetIfNeeded(previousInfo: previousInfo, previousFallback: previousFallback)
    }
    
    private func estimateMinutesLeftFromSamples(windowSec: TimeInterval) -> Int? {
        guard samplesForEta.count >= 2,
              let first = samplesForEta.first,
              let last = samplesForEta.last,
              last.t > first.t else { return nil }
        
        let dt = last.t.timeIntervalSince(first.t) / 60.0
        guard dt > 0, let pLast = samplesForEta.last?.p else { return nil }
        let dp = Double(pLast - first.p) // %
        let rate = dp / dt               // %/min
        if rate >= 0 { return nil }      // не розряджається
        let minutesLeft = Double(pLast) / abs(rate)
        return minutesLeft.isFinite && minutesLeft > 0 ? Int(minutesLeft.rounded()) : nil
    }
    
    private func appendHistory(info: BatteryInfo) {
        let currentTime = now()
        history.append(HistorySample(t: currentTime, percent: info.percentage, watts: info.watts))
        let cutoff = currentTime.addingTimeInterval(-chartDurationSec)
        history.removeAll { $0.t < cutoff }
    }
    
    // MARK: - Notifications
    
    private func handleNotifications(old newInfo: BatteryInfo) {
        let currentTime = now()
        
        // Low battery 20/10/5 — тільки на батареї
        if newInfo.onACPower == false, let p = newInfo.percentage {
            for th in [20, 10, 5] where p <= th && !lowNotified.contains(th) {
                notify("Low Battery", "Battery level is \(p)%")
                lowNotified.insert(th)
            }
        } else {
            if newInfo.onACPower == true { lowNotified.removeAll() }
        }
        
        // Fully charged: 100% і на AC ≥ 10 хв
        if newInfo.onACPower == true, (newInfo.percentage ?? 0) >= 100 {
            if fullChargeStart == nil { fullChargeStart = currentTime }
            if !fullNotified, let start = fullChargeStart, currentTime.timeIntervalSince(start) >= 600 {
                notify("Fully Charged", "Battery reached 100% and stayed on AC for 10+ minutes.")
                fullNotified = true
            }
        } else {
            fullChargeStart = nil
            fullNotified = false
        }
        
        // Стрибки потужності: |ΔW| > 10 Вт за < 10 c, cooldown 5 хв
        if let wNow = newInfo.watts {
            let tenSecAgo = currentTime.addingTimeInterval(-10)
            if let wPast = history.last(where: { $0.t <= tenSecAgo })?.watts,
               abs(wNow - (wPast ?? 0)) >= 10 {
                if lastSpikeAt == nil || currentTime.timeIntervalSince(lastSpikeAt!) > 300 {
                    let sign = wNow >= 0 ? "+" : "−"
                    notify("Power Spike",
                           "Power changed by \(sign)\(String(format: "%.1f", abs(wNow - (wPast ?? 0))))W")
                    lastSpikeAt = currentTime
                }
            }
        }
    }

    private struct WidgetReloadSignature: Equatable {
        let percentage: Int?
        let isCharging: Bool?
        let onACPower: Bool?
        let timeToEmptyMin: Int?
        let timeToFullMin: Int?
        let wattsRounded: Int?
        let usedFallbackEstimate: Bool

        init(info: BatteryInfo, usedFallbackEstimate: Bool) {
            self.percentage = info.percentage
            self.isCharging = info.isCharging
            self.onACPower = info.onACPower
            self.timeToEmptyMin = info.timeToEmptyMin
            self.timeToFullMin = info.timeToFullMin
            self.wattsRounded = info.watts.map { Int($0.rounded()) }
            self.usedFallbackEstimate = usedFallbackEstimate
        }
    }

    private func reloadWidgetIfNeeded(previousInfo: BatteryInfo, previousFallback: Bool) {
        #if canImport(WidgetKit)
        let oldSignature = WidgetReloadSignature(info: previousInfo, usedFallbackEstimate: previousFallback)
        let newSignature = WidgetReloadSignature(info: info, usedFallbackEstimate: usedFallbackEstimate)

        let changed = oldSignature != newSignature
        let neverReloaded = lastWidgetReloadSignature == nil
        let currentTime = now()
        let enoughTimePassed = lastWidgetReloadAt.map { currentTime.timeIntervalSince($0) >= 30 } ?? true

        guard (changed || neverReloaded), enoughTimePassed else { return }

        WidgetCenter.shared.reloadTimelines(ofKind: "BatteryDataWidget")
        lastWidgetReloadAt = currentTime
        lastWidgetReloadSignature = newSignature
        #endif
    }
}

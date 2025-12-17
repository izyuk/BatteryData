//
//  Prefs.swift
//  BateryData
//
//  Created by Dmytro Izyuk on 11.09.2025.
//

enum PrefKeys {
    static let refreshIntervalSec   = "pref_refreshIntervalSec"   // Double (1...30), default 5
    static let estimationWindowMin  = "pref_estimationWindowMin"  // Double (1...10), default 3
    static let showWattsInStatusBar = "pref_showWattsInStatusBar" // Bool, default true
    static let compactLabel         = "pref_compactLabel"         // Bool, default false
    static let chartDurationMin     = "pref_chartDurationMin"     // Double (10...120), default 60
    
    static let statusBarExpandedInfo = "statusBarExpandedInfo"
}

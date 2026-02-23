//
//  SignalBreakdown.swift
//  BistScreener
//
//  Created by Sedat Pala on 23.02.2026.
//

import Foundation

/// ✅ Legacy breakdown (geriye uyum için)
/// Eski snapshot’ları decode/encode edebilmek ve ScanResult.breakdown compile etsin diye duruyor.
/// Tomorrow BUY-only stratejisi bunu kullanmak zorunda değil.
struct SignalBreakdown: Codable, Equatable, Hashable {
    var patternScore: Int = 0
    var rsiScore: Int = 0
    var macdScore: Int = 0
    var emaScore: Int = 0
    var bbScore: Int = 0
    var volumeScore: Int = 0

    var rsiValue: Double = 0
    var macdHistLast: Double = 0
    var bbPercentB: Double = 0.5
    var relVolume: Double = 1.0
    var emaFast: Double = 0
    var emaSlow: Double = 0
    var atrRatio: Double = 0
}

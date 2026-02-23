//
//  AppServices.swift
//  BistScreener
//
//  Created by Sedat Pala on 20.02.2026.
//

import Foundation
import SwiftUI

@MainActor
final class AppServices: ObservableObject {
    let yahoo: YahooFinanceService
    let indexService: BorsaIstanbulIndexService
    let patternDetector: PatternDetector
    let candles: CandleRepository

    init(
        yahoo: YahooFinanceService = YahooFinanceService(),
        indexService: BorsaIstanbulIndexService = BorsaIstanbulIndexService(),
        patternDetector: PatternDetector = PatternDetector(),
        candlesTTLMinutes: Double = 10
    ) {
        self.yahoo = yahoo
        self.indexService = indexService
        self.patternDetector = patternDetector
        self.candles = CandleRepository(yahoo: yahoo, ttlMinutes: candlesTTLMinutes)
    }
}

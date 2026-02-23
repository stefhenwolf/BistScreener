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
    let candles: CandleRepository
    let cacheStats = CacheStats()
    let ticker = MarketTickerViewModel()

    init() {
        self.yahoo = YahooFinanceService()
        self.indexService = BorsaIstanbulIndexService()
        self.candles = CandleRepository(yahoo: yahoo, ttlMinutes: 10)
    }
}

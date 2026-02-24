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
    let portfolio: PortfolioViewModel
    let strategy: LiveStrategyStore

    init() {
        self.yahoo = YahooFinanceService()
        self.indexService = BorsaIstanbulIndexService()
        self.candles = CandleRepository(yahoo: yahoo, ttlMinutes: 10)
        self.portfolio = PortfolioViewModel(yahoo: yahoo)
        self.strategy = LiveStrategyStore(yahoo: yahoo, indexService: indexService, portfolioVM: portfolio)
    }
}

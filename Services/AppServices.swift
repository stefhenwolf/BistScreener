//
//  AppServices.swift
//  BistScreener
//
//  Created by Sedat Pala on 20.02.2026.
//

import Foundation
import SwiftUI
#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

@MainActor
final class AppServices: ObservableObject {
    let yahoo: YahooFinanceService
    let indexService: BorsaIstanbulIndexService
    let candles: CandleRepository
    let cacheStats = CacheStats()
    let ticker = MarketTickerViewModel()
    let portfolio: PortfolioViewModel
    let strategy: LiveStrategyStore
    let cloudRepository: any CloudDataRepository

    init() {
        self.yahoo = YahooFinanceService()
        self.indexService = BorsaIstanbulIndexService()
        self.candles = CandleRepository(yahoo: yahoo, ttlMinutes: 10)
#if canImport(FirebaseFirestore)
        let repository: any CloudDataRepository = FirestoreCloudDataRepository()
#else
        let repository: any CloudDataRepository = NoopCloudDataRepository()
#endif
        self.cloudRepository = repository
        self.portfolio = PortfolioViewModel(yahoo: yahoo, cloudRepository: repository)
        self.strategy = LiveStrategyStore(
            yahoo: yahoo,
            indexService: indexService,
            portfolioVM: portfolio,
            cloudRepository: repository
        )
    }
}

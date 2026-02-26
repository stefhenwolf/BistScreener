import Foundation
import Combine

// MARK: - Exit Configuration

/// Çok günlü pozisyon çıkış stratejisi parametreleri.
/// TP/SL + maksimum pozisyon süresi.
struct BacktestExitConfig: Codable, Equatable {
    /// 1. kâr al seviyesi (%)  — giriş fiyatından +%5
    var tp1Pct: Double = 5.0

    /// 2. kâr al seviyesi (%)  — giriş fiyatından +%10
    var tp2Pct: Double = 10.0

    /// TP1 seviyesinde satılacak oran (%)
    var tp1SellPercent: Double = 50.0

    /// Zarar kes seviyesi (%) — giriş fiyatından -%6 aşağı (pozitif sayı)
    var stopLossPct: Double = 6.0

    /// Maksimum pozisyon süresi (iş günü)
    var maxHoldDays: Int = 30

    /// Aynı hisse için yeniden giriş bekleme süresi (iş günü)
    var cooldownDays: Int = 3

    /// Komisyon (tek yön, bps). 10 bps = %0.10
    var commissionBps: Double = 12.0

    /// Slippage (tek yön, bps). 5 bps = %0.05
    var slippageBps: Double = 8.0

    /// Eski tek TP alanı uyumluluğu (TP2 = ana hedef)
    var takeProfitPct: Double {
        get { tp2Pct }
        set { tp2Pct = newValue }
    }

    enum CodingKeys: String, CodingKey {
        case tp1Pct
        case tp2Pct
        case tp1SellPercent
        case takeProfitPct
        case stopLossPct
        case maxHoldDays
        case cooldownDays
        case commissionBps
        case slippageBps
    }

    init() {}

    init(
        tp1Pct: Double = 5.0,
        tp2Pct: Double = 10.0,
        tp1SellPercent: Double = 50.0,
        stopLossPct: Double = 6.0,
        maxHoldDays: Int = 30,
        cooldownDays: Int = 3,
        commissionBps: Double = 12.0,
        slippageBps: Double = 8.0
    ) {
        self.tp1Pct = tp1Pct
        self.tp2Pct = tp2Pct
        self.tp1SellPercent = tp1SellPercent
        self.stopLossPct = stopLossPct
        self.maxHoldDays = maxHoldDays
        self.cooldownDays = cooldownDays
        self.commissionBps = commissionBps
        self.slippageBps = slippageBps
        normalize()
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let legacyTP = try c.decodeIfPresent(Double.self, forKey: .takeProfitPct) ?? 10.0
        tp2Pct = try c.decodeIfPresent(Double.self, forKey: .tp2Pct) ?? legacyTP
        tp1Pct = try c.decodeIfPresent(Double.self, forKey: .tp1Pct) ?? min(5.0, tp2Pct)
        tp1SellPercent = try c.decodeIfPresent(Double.self, forKey: .tp1SellPercent) ?? 50.0
        stopLossPct = try c.decodeIfPresent(Double.self, forKey: .stopLossPct) ?? 6.0
        maxHoldDays = try c.decodeIfPresent(Int.self, forKey: .maxHoldDays) ?? 30
        cooldownDays = try c.decodeIfPresent(Int.self, forKey: .cooldownDays) ?? 3
        commissionBps = try c.decodeIfPresent(Double.self, forKey: .commissionBps) ?? 12.0
        slippageBps = try c.decodeIfPresent(Double.self, forKey: .slippageBps) ?? 8.0
        normalize()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(tp1Pct, forKey: .tp1Pct)
        try c.encode(tp2Pct, forKey: .tp2Pct)
        try c.encode(tp1SellPercent, forKey: .tp1SellPercent)
        try c.encode(tp2Pct, forKey: .takeProfitPct)
        try c.encode(stopLossPct, forKey: .stopLossPct)
        try c.encode(maxHoldDays, forKey: .maxHoldDays)
        try c.encode(cooldownDays, forKey: .cooldownDays)
        try c.encode(commissionBps, forKey: .commissionBps)
        try c.encode(slippageBps, forKey: .slippageBps)
    }

    mutating func normalize() {
        tp2Pct = min(max(tp2Pct, 4), 50)
        tp1Pct = min(max(tp1Pct, 1), 40)
        if tp1Pct >= tp2Pct {
            tp1Pct = max(1, tp2Pct - 1)
        }
        tp1SellPercent = min(max(tp1SellPercent, 10), 90)
        stopLossPct = min(max(stopLossPct, 1), 25)
        maxHoldDays = min(max(maxHoldDays, 1), 180)
        cooldownDays = min(max(cooldownDays, 0), 30)
        commissionBps = min(max(commissionBps, 0), 100)
        slippageBps = min(max(slippageBps, 0), 100)
    }

    init(
        takeProfitPct: Double,
        stopLossPct: Double,
        maxHoldDays: Int,
        cooldownDays: Int
    ) {
        self.init(
            tp1Pct: min(5.0, takeProfitPct),
            tp2Pct: takeProfitPct,
            tp1SellPercent: 50.0,
            stopLossPct: stopLossPct,
            maxHoldDays: maxHoldDays,
            cooldownDays: cooldownDays
        )
    }

    // MARK: - Ultra Bounce Presets

    /// Ultra Quick Flip: 1-3 gün tutma, dar TP/SL
    static var ultraQuickFlip: BacktestExitConfig {
        BacktestExitConfig(
            tp1Pct: 3.0,
            tp2Pct: 5.0,
            tp1SellPercent: 60.0,
            stopLossPct: 2.5,
            maxHoldDays: 3,
            cooldownDays: 1
        )
    }

    /// Ultra Swing: 3-7 gün tutma, orta TP/SL
    static var ultraSwing: BacktestExitConfig {
        BacktestExitConfig(
            tp1Pct: 4.0,
            tp2Pct: 8.0,
            tp1SellPercent: 50.0,
            stopLossPct: 3.5,
            maxHoldDays: 7,
            cooldownDays: 2
        )
    }

    /// Ultra Dynamic: ATR-bazlı TP/SL
    static func ultraDynamic(candles: [Candle], config: UltraStrategyConfig = .hunter) -> BacktestExitConfig {
        guard let exits = UltraSignalScorer.calculateDynamicExits(candles: candles, config: config) else {
            return .ultraQuickFlip
        }
        return BacktestExitConfig(
            tp1Pct: exits.tpPct * 0.6,
            tp2Pct: exits.tpPct,
            tp1SellPercent: 50.0,
            stopLossPct: exits.slPct,
            maxHoldDays: 5,
            cooldownDays: 1
        )
    }
}

// MARK: - Portfolio Add-On Configuration

enum BacktestAddOnMode: Int, Codable, CaseIterable {
    case off = 0
    case free = 1
    case delayed = 2
}

struct BacktestPortfolioConfig: Codable, Equatable {
    var addOnMode: BacktestAddOnMode = .off
    var addOnWaitDays: Int = 5
}

// MARK: - Exit Reason

enum ExitReason: String, Codable, CaseIterable {
    case takeProfit    = "TP"
    case stopLoss      = "SL"
    case maxDays       = "Süre"
    case open          = "Açık"

    var label: String {
        switch self {
        case .takeProfit:   return "Kâr Al"
        case .stopLoss:     return "Zarar Kes"
        case .maxDays:      return "Süre Doldu"
        case .open:         return "Pozisyon Açık"
        }
    }

    var emoji: String {
        switch self {
        case .takeProfit:   return "🎯"
        case .stopLoss:     return "🛑"
        case .maxDays:      return "⏰"
        case .open:         return "🟡"
        }
    }
}

// MARK: - Trade Result (Multi-Day)

struct BacktestTradeResult: Identifiable, Codable {
    let id: UUID
    let symbol: String
    let entryDate: Date
    let entryPrice: Double
    let exitDate: Date
    let exitPrice: Double
    let returnPct: Double
    let daysHeld: Int
    let exitReason: ExitReason
    let signalScore: Int
    let signalQuality: String
    let reasons: [String]
    let proximity: Double
    let volumeTrend: Double
    let rangeCompression: Double
    let regime: String

    /// Peakten çıkış fiyatına kadar olan drawdown (%)
    let maxDrawdownPct: Double

    /// Pozisyon süresince ulaşılan en yüksek kâr (%)
    let peakReturnPct: Double

    /// TP1 tetiklendiyse gerçekleştiği gün (17:00 normalize)
    let tp1Date: Date?

    /// TP1'de gerçekleşen nakit çıkışı (kısmi satış tutarı)
    let tp1Proceeds: Double?

    var isWin: Bool { returnPct > 0 }

    init(
        symbol: String,
        entryDate: Date,
        entryPrice: Double,
        exitDate: Date,
        exitPrice: Double,
        daysHeld: Int,
        exitReason: ExitReason,
        score: Int,
        quality: String,
        reasons: [String],
        proximity: Double,
        volumeTrend: Double,
        rangeCompression: Double,
        regime: String = "Sideways",
        maxDrawdownPct: Double,
        peakReturnPct: Double,
        tp1Date: Date? = nil,
        tp1Proceeds: Double? = nil,
        returnPctOverride: Double? = nil
    ) {
        self.id = UUID()
        self.symbol = symbol
        self.entryDate = entryDate
        self.entryPrice = entryPrice
        self.exitDate = exitDate
        self.exitPrice = exitPrice
        self.returnPct = returnPctOverride ?? (entryPrice > 0 ? ((exitPrice - entryPrice) / entryPrice) * 100 : 0)
        self.daysHeld = daysHeld
        self.exitReason = exitReason
        self.signalScore = score
        self.signalQuality = quality
        self.reasons = reasons
        self.proximity = proximity
        self.volumeTrend = volumeTrend
        self.rangeCompression = rangeCompression
        self.regime = regime
        self.maxDrawdownPct = maxDrawdownPct
        self.peakReturnPct = peakReturnPct
        self.tp1Date = tp1Date
        self.tp1Proceeds = tp1Proceeds
    }
}

// MARK: - Backtest Summary

struct BacktestSummary {
    let totalSignals: Int
    let wins: Int
    let losses: Int
    let winRate: Double
    let avgReturn: Double
    let avgWinReturn: Double
    let avgLossReturn: Double
    let maxWin: Double
    let maxLoss: Double
    let profitFactor: Double
    let trades: [BacktestTradeResult]

    // ── v2 Multi-Day Metrics ──
    let avgDaysHeld: Double
    let tpCount: Int
    let slCount: Int
    let maxDaysCount: Int
    let openCount: Int
    let avgPeakReturn: Double
    let avgDrawdown: Double
    let expectancyPct: Double
    let maxDaysStrongCount: Int
    let maxDaysMediumCount: Int
    let maxDaysWeakCount: Int

    static let empty = BacktestSummary(
        totalSignals: 0, wins: 0, losses: 0,
        winRate: 0, avgReturn: 0, avgWinReturn: 0, avgLossReturn: 0,
        maxWin: 0, maxLoss: 0, profitFactor: 0, trades: [],
        avgDaysHeld: 0, tpCount: 0, slCount: 0,
        maxDaysCount: 0, openCount: 0, avgPeakReturn: 0, avgDrawdown: 0,
        expectancyPct: 0, maxDaysStrongCount: 0, maxDaysMediumCount: 0, maxDaysWeakCount: 0
    )

    static func from(trades: [BacktestTradeResult]) -> BacktestSummary {
        guard !trades.isEmpty else { return .empty }

        let winsArr = trades.filter { $0.isWin }
        let lossesArr = trades.filter { !$0.isWin }

        let winCount = winsArr.count
        let lossCount = lossesArr.count

        let avgReturn = trades.map(\.returnPct).reduce(0, +) / Double(trades.count)
        let avgWin = winsArr.isEmpty ? 0 : winsArr.map(\.returnPct).reduce(0, +) / Double(winCount)
        let avgLoss = lossesArr.isEmpty ? 0 : lossesArr.map(\.returnPct).reduce(0, +) / Double(lossCount)
        let maxW = trades.map(\.returnPct).max() ?? 0
        let maxL = trades.map(\.returnPct).min() ?? 0

        let totalProfit = winsArr.map(\.returnPct).reduce(0, +)
        let totalLoss = abs(lossesArr.map(\.returnPct).reduce(0, +))
        let pf = totalLoss > 0 ? (totalProfit / totalLoss) : (totalProfit > 0 ? 99 : 0)

        // ── Multi-Day Metrics ──
        let avgDays = Double(trades.map(\.daysHeld).reduce(0, +)) / Double(trades.count)
        let tpCount = trades.filter { $0.exitReason == .takeProfit }.count
        let slCount = trades.filter { $0.exitReason == .stopLoss }.count
        let maxDaysCount = trades.filter { $0.exitReason == .maxDays }.count
        let openCount = trades.filter { $0.exitReason == .open }.count
        let avgPeak = trades.map(\.peakReturnPct).reduce(0, +) / Double(trades.count)
        let avgDD = trades.map(\.maxDrawdownPct).reduce(0, +) / Double(trades.count)
        let expectancyPct = (Double(winCount) / Double(trades.count)) * avgWin - (Double(lossCount) / Double(trades.count)) * abs(avgLoss)
        let maxDaysTrades = trades.filter { $0.exitReason == .maxDays }
        let maxDaysStrong = maxDaysTrades.filter { $0.signalQuality == "A+" || $0.signalQuality == "A" }.count
        let maxDaysMedium = maxDaysTrades.filter { $0.signalQuality == "B" }.count
        let maxDaysWeak = max(0, maxDaysTrades.count - maxDaysStrong - maxDaysMedium)

        return BacktestSummary(
            totalSignals: trades.count,
            wins: winCount,
            losses: lossCount,
            winRate: Double(winCount) / Double(trades.count),
            avgReturn: avgReturn,
            avgWinReturn: avgWin,
            avgLossReturn: avgLoss,
            maxWin: maxW,
            maxLoss: maxL,
            profitFactor: pf,
            trades: trades.sorted { $0.entryDate > $1.entryDate },
            avgDaysHeld: avgDays,
            tpCount: tpCount,
            slCount: slCount,
            maxDaysCount: maxDaysCount,
            openCount: openCount,
            avgPeakReturn: avgPeak,
            avgDrawdown: avgDD,
            expectancyPct: expectancyPct,
            maxDaysStrongCount: maxDaysStrong,
            maxDaysMediumCount: maxDaysMedium,
            maxDaysWeakCount: maxDaysWeak
        )
    }
}

// MARK: - Backtest Engine (Multi-Day)

@MainActor
final class BacktestEngine: ObservableObject {
    @Published var isRunning: Bool = false
    @Published var progress: Double = 0
    @Published var progressText: String = ""
    @Published var errorText: String?
    @Published var summary: BacktestSummary = .empty

    private let services: AppServices
    private var task: Task<Void, Never>?

    init(services: AppServices) {
        self.services = services
    }

    func cancel() {
        task?.cancel()
        task = nil
        isRunning = false
        progressText = "İptal edildi."
    }

    func run(
        indexOption: IndexOption,
        preset: TomorrowPreset,
        strategyMode: ScanStrategyMode = .preBreakout,
        ultraPreset: UltraPreset = .hunter,
        exitConfig: BacktestExitConfig = BacktestExitConfig(),
        portfolioConfig: BacktestPortfolioConfig = BacktestPortfolioConfig()
    ) {
        if isRunning { return }

        errorText = nil
        summary = .empty
        progress = 0
        progressText = "Hazırlanıyor…"
        isRunning = true

        task?.cancel()
        let indexService = services.indexService
        let yahoo = services.yahoo

        task = Task.detached(priority: .background) { [weak self] in
            guard let engine = self else { return }

            do {
                let trades = try await BacktestEngine.runBacktestBackground(
                    indexService: indexService,
                    yahoo: yahoo,
                    indexOption: indexOption,
                    preset: preset,
                    strategyMode: strategyMode,
                    ultraPreset: ultraPreset,
                    exitConfig: exitConfig,
                    portfolioConfig: portfolioConfig
                ) { done, total, signalCount in
                    await MainActor.run {
                        engine.progress = Double(done) / Double(max(total, 1))
                        engine.progressText = "\(done)/\(total) sembol (\(signalCount) sinyal)"
                    }
                }

                if Task.isCancelled { throw CancellationError() }

                let sum = BacktestSummary.from(trades: trades)

                await MainActor.run {
                    engine.summary = sum
                    engine.progress = 1
                    engine.progressText = "Bitti. \(sum.totalSignals) sinyal, WR: \(String(format: "%.0f", sum.winRate * 100))%, Avg: \(String(format: "%+.1f", sum.avgReturn))%"
                    engine.isRunning = false
                }

            } catch is CancellationError {
                await MainActor.run {
                    engine.isRunning = false
                    engine.progressText = "İptal edildi."
                }
            } catch {
                await MainActor.run {
                    engine.isRunning = false
                    engine.errorText = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Background runner

    nonisolated static func runBacktestBackground(
        indexService: BorsaIstanbulIndexService,
        yahoo: YahooFinanceService,
        indexOption: IndexOption,
        preset: TomorrowPreset,
        strategyMode: ScanStrategyMode = .preBreakout,
        ultraPreset: UltraPreset = .hunter,
        exitConfig: BacktestExitConfig,
        portfolioConfig: BacktestPortfolioConfig,
        includeTodaySignals: Bool = false,
        onProgress: @Sendable @escaping (_ done: Int, _ total: Int, _ signalCount: Int) async -> Void
    ) async throws -> [BacktestTradeResult] {

        // 1) Symbol universe
        let snap = try await indexService.fetchSnapshot(indexCode: indexOption.rawValue)
        let symbolsAll = snap.yahooSymbols
        let symbols = symbolsAll.filter { $0.hasSuffix(".IS") }

        guard !symbols.isEmpty else {
            await onProgress(1, 1, 0)
            return []
        }

        let total = symbols.count
        var done = 0

        let baseConfig = StrategyConfig.load()
        let lookback = SignalScorer.effectiveLookback(
            preset: preset,
            configuredLookback: baseConfig.lookbackDays
        )

        // 2) Concurrency: tüm semboller için tek seferde task açma.
        // BIST ALL için de tek worker yerine 2 worker kullanarak "dondu" hissini azalt.
        let concurrency = (indexOption == .bistAll ? 2 : 3)
        let updateStride = max(1, total / 40) // UI tarafına ~40 güncellemeden fazlasını yollama
        await onProgress(0, total, 0)

        var collected: [BacktestTradeResult] = []
        collected.reserveCapacity(512)

        try await withThrowingTaskGroup(of: [BacktestTradeResult].self) { group in
            var nextSymbolIndex = 0
            let workerCount = min(concurrency, total)

            for _ in 0..<workerCount {
                let sym = symbols[nextSymbolIndex]
                nextSymbolIndex += 1
                group.addTask {
                    if Task.isCancelled { return [] }

                    return await BacktestEngine.backtestOneSymbolStatic(
                        yahoo: yahoo,
                        symbol: sym,
                        preset: preset,
                        strategyMode: strategyMode,
                        ultraPreset: ultraPreset,
                        baseConfig: baseConfig,
                        lookback: lookback,
                        exitConfig: exitConfig,
                        portfolioConfig: portfolioConfig,
                        includeTodaySignals: includeTodaySignals
                    )
                }
            }

            while let trades = try await group.next() {
                if Task.isCancelled { throw CancellationError() }

                done += 1
                collected.append(contentsOf: trades)

                if done == total || (done % updateStride == 0) {
                    await onProgress(done, total, collected.count)
                }
                if done % 2 == 0 { await Task.yield() }

                if nextSymbolIndex < total {
                    let sym = symbols[nextSymbolIndex]
                    nextSymbolIndex += 1
                    group.addTask {
                        if Task.isCancelled { return [] }
                        return await BacktestEngine.backtestOneSymbolStatic(
                            yahoo: yahoo,
                            symbol: sym,
                            preset: preset,
                            strategyMode: strategyMode,
                            ultraPreset: ultraPreset,
                            baseConfig: baseConfig,
                            lookback: lookback,
                            exitConfig: exitConfig,
                            portfolioConfig: portfolioConfig,
                            includeTodaySignals: includeTodaySignals
                        )
                    }
                }
            }
        }

        return collected
    }

    // MARK: - Single symbol backtest (multi-day)

    nonisolated private static func backtestOneSymbolStatic(
        yahoo: YahooFinanceService,
        symbol: String,
        preset: TomorrowPreset,
        strategyMode: ScanStrategyMode,
        ultraPreset: UltraPreset,
        baseConfig: StrategyConfig,
        lookback: Int,
        exitConfig: BacktestExitConfig,
        portfolioConfig: BacktestPortfolioConfig,
        includeTodaySignals: Bool
    ) async -> [BacktestTradeResult] {

        var trades: [BacktestTradeResult] = []

        do {
            let sym = symbol.normalizedBISTSymbol()

            let candles = try await fetchBacktestCandles(yahoo: yahoo, symbol: sym, minCount: 120)

            guard candles.count >= 80 else { return [] }

            let startIdx = max(55, lookback + 5)
            // Bugünün mumu sadece 17:00-18:00 aralığında yeni giriş sinyali üretsin.
            // Bu aralık dışında (17:00 öncesi ve 18:00 sonrası) yalnızca geçmiş günlerden giriş açılır.
            let lastIdx = candles.count - 1
            let deferTodayEntrySignals = includeTodaySignals
                ? false
                : Self.shouldDeferTodaySignalOutsideExecutionWindow(
                    lastCandleDate: candles.last?.date
                )
            let signalEndIdx = deferTodayEntrySignals ? (lastIdx - 1) : lastIdx
            guard signalEndIdx > startIdx else { return [] }

            // Her günün AL sinyalini bir kez hesapla; maxDays uzatma kuralında tekrar tekrar skor hesaplamayı önler.
            var signalsByDay: [TomorrowSignalScore?] = Array(repeating: nil, count: candles.count)
            var signalSlice = Array(candles[0...startIdx])
            var activeExitIdxs: [Int] = []
            var lastEntryIdx: Int?
            var cooldownUntilIdx = 0
            var scoringConfig = baseConfig
            scoringConfig.lookbackDays = lookback

            for dayIdx in startIdx...signalEndIdx {
                if Task.isCancelled { break }
                if dayIdx % 16 == 0 { await Task.yield() }
                if dayIdx > startIdx { signalSlice.append(candles[dayIdx]) }

                let regime = MarketRegimeDetector.detect(from: signalSlice)
                switch strategyMode {
                case .ultraBounce:
                    signalsByDay[dayIdx] = UltraSignalScorer.score(
                        candles: signalSlice,
                        config: ultraPreset.config,
                        regime: regime
                    )
                case .preBreakout:
                    scoringConfig.minScore = SignalScorer.dynamicMinScore(
                        for: preset,
                        regime: regime,
                        config: scoringConfig
                    )
                    signalsByDay[dayIdx] = SignalScorer.scoreWithConfig(
                        candles: signalSlice,
                        config: scoringConfig,
                        softMode: true
                    )
                case .ensemble:
                    scoringConfig.minScore = SignalScorer.dynamicMinScore(
                        for: preset,
                        regime: regime,
                        config: scoringConfig
                    )
                    let pb = SignalScorer.scoreWithConfig(
                        candles: signalSlice,
                        config: scoringConfig,
                        softMode: true
                    )
                    let ub = UltraSignalScorer.score(
                        candles: signalSlice,
                        config: ultraPreset.config,
                        regime: regime
                    )
                    signalsByDay[dayIdx] = blendEnsembleSignal(pb: pb, ub: ub)
                }
            }

            let hasBuySignalByDay: [Bool] = signalsByDay.map { $0 != nil }

            for dayIdx in startIdx...signalEndIdx {
                if Task.isCancelled { break }
                if dayIdx % 16 == 0 { await Task.yield() } // Uzun CPU döngülerinde UI'nin nefes almasını sağlar.

                // Önce kapanan pozisyonları temizle.
                let hadOpenBeforeCleanup = !activeExitIdxs.isEmpty
                var closedExitIdxMax: Int?
                activeExitIdxs.removeAll { exitIdx in
                    let isClosedBeforeToday = exitIdx <= dayIdx
                    if isClosedBeforeToday {
                        if let currentMax = closedExitIdxMax {
                            closedExitIdxMax = max(currentMax, exitIdx)
                        } else {
                            closedExitIdxMax = exitIdx
                        }
                    }
                    return isClosedBeforeToday
                }

                // Tamamen flat kaldıktan sonra cooldown uygula.
                if hadOpenBeforeCleanup, activeExitIdxs.isEmpty, let lastClosed = closedExitIdxMax {
                    cooldownUntilIdx = max(cooldownUntilIdx, lastClosed + exitConfig.cooldownDays)
                }

                let hasOpenPosition = !activeExitIdxs.isEmpty

                if !hasOpenPosition, dayIdx < cooldownUntilIdx {
                    let stillBuy = dayIdx < hasBuySignalByDay.count ? hasBuySignalByDay[dayIdx] : false
                    if !stillBuy {
                        continue
                    }
                }

                // Açık pozisyonda ek alım kuralı.
                if hasOpenPosition {
                    switch portfolioConfig.addOnMode {
                    case .off:
                        continue
                    case .free:
                        break
                    case .delayed:
                        guard let lastEntryIdx else { continue }
                        let waitDays = max(1, portfolioConfig.addOnWaitDays)
                        if dayIdx < lastEntryIdx + waitDays {
                            continue
                        }
                    }
                }

                guard let signal = signalsByDay[dayIdx] else { continue }

                // ── Multi-day Trade Simulation ──
                guard let sim = simulateTrade(
                    candles: candles,
                    signalIdx: dayIdx,
                    exitConfig: exitConfig,
                    hasBuySignalByDay: hasBuySignalByDay
                ) else { continue }

                let signalDay = candles[dayIdx]
                let entryDate = Self.strategyExecutionDate(for: signalDay.date, hour: 17)
                let exitDate = Self.strategyExecutionDate(for: candles[sim.finalExitIdx].date, hour: 18)
                let regimeAtEntry = MarketRegimeDetector.detect(
                    from: Array(candles.prefix(dayIdx + 1).suffix(220)),
                    config: baseConfig
                ).title

                let trade = BacktestTradeResult(
                    symbol: sym,
                    entryDate: entryDate,
                    entryPrice: signalDay.close,
                    exitDate: exitDate,
                    exitPrice: sim.effectiveExitPrice,
                    daysHeld: sim.daysHeld,
                    exitReason: sim.finalExitReason,
                    score: signal.total,
                    quality: signal.quality,
                    reasons: signal.reasons,
                    proximity: signal.breakdown.proximityPct,
                    volumeTrend: signal.breakdown.volumeTrend,
                    rangeCompression: signal.breakdown.rangeCompression,
                    regime: regimeAtEntry,
                    maxDrawdownPct: sim.maxDrawdownPct,
                    peakReturnPct: sim.peakReturnPct,
                    tp1Date: sim.tp1ExecutedIdx.map { Self.strategyExecutionDate(for: candles[$0].date, hour: 17) },
                    tp1Proceeds: sim.tp1Proceeds,
                    returnPctOverride: sim.realizedReturnPct
                )

                trades.append(trade)
                activeExitIdxs.append(sim.finalExitIdx)
                lastEntryIdx = dayIdx
            }

        } catch {
            return []
        }

        return trades
    }

    nonisolated private static func blendEnsembleSignal(
        pb: TomorrowSignalScore?,
        ub: TomorrowSignalScore?
    ) -> TomorrowSignalScore? {
        switch (pb, ub) {
        case let (p?, u?):
            let total = min(100, Int(round(Double(p.total) * 0.55 + Double(u.total) * 0.45 + 4.0)))
            let quality: String
            switch total {
            case 80...: quality = "A+"
            case 68...: quality = "A"
            case 55...: quality = "B"
            case 42...: quality = "C"
            default: quality = "D"
            }
            var seen = Set<String>()
            let reasons = (p.reasons + u.reasons).filter { seen.insert($0).inserted }
            var b = p.breakdown
            b.notes.append("Ensemble PB+UB")
            return TomorrowSignalScore(
                isBuy: true,
                total: total,
                quality: quality,
                signal: .buy,
                tier: p.tier,
                reasons: Array(reasons.prefix(3)),
                breakdown: b
            )
        case let (p?, nil):
            return p.total >= 68 ? p : nil
        case let (nil, u?):
            return u.total >= 70 ? u : nil
        default:
            return nil
        }
    }

    nonisolated private static func fetchBacktestCandles(
        yahoo: YahooFinanceService,
        symbol: String,
        minCount: Int
    ) async throws -> [Candle] {
        if let cached = await CandleCache.shared.load(symbol: symbol), !cached.isEmpty {
            let trimmed = Array(cached.suffix(max(minCount, 140)))
            return trimmed
        }

        let fetched = try await yahoo.fetchDailyCandles(symbol: symbol, range: "6mo")
        let trimmed = Array(fetched.suffix(max(minCount, 140)))
        if !trimmed.isEmpty {
            await CandleCache.shared.save(symbol: symbol, candles: trimmed)
        }
        return trimmed
    }

    nonisolated private static func shouldDeferTodaySignalOutsideExecutionWindow(
        lastCandleDate: Date?,
        now: Date = Date(),
        startHour: Int = 17,
        closeHour: Int = 18
    ) -> Bool {
        guard let lastCandleDate else { return false }
        let cal = Calendar.current
        guard cal.isDate(lastCandleDate, inSameDayAs: now) else { return false }
        let hour = cal.component(.hour, from: now)
        return hour < startHour || hour >= closeHour
    }

    nonisolated private static func strategyExecutionDate(
        for day: Date,
        hour: Int
    ) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
    }

    // MARK: - Trade Simulation

    private struct SimResult {
        let effectiveExitPrice: Double
        let finalExitIdx: Int
        let finalExitReason: ExitReason
        let daysHeld: Int
        let realizedReturnPct: Double
        let peakReturnPct: Double
        let maxDrawdownPct: Double
        let tp1ExecutedIdx: Int?
        let tp1Proceeds: Double
    }

    nonisolated private static func applyTransactionCosts(
        grossPrice: Double,
        isBuy: Bool,
        exitConfig: BacktestExitConfig
    ) -> Double {
        let totalBps = (exitConfig.commissionBps + exitConfig.slippageBps) / 10_000.0
        if isBuy {
            return grossPrice * (1.0 + totalBps)
        } else {
            return grossPrice * (1.0 - totalBps)
        }
    }

    /// Giriş gününden itibaren her günün OHLC'sini kontrol ederek TP/SL/MaxDays çıkışı simüle eder.
    /// maxDays dolduğunda güncel AL sinyali devam ediyorsa pozisyon kapanmaz; sinyal düşene kadar taşınır.
    /// - signalIdx: Sinyal günü indexi (giriş fiyatı = candles[signalIdx].close)
    /// - Returns: nil eğer sinyal gününden sonra yeterli veri yoksa
    nonisolated private static func simulateTrade(
        candles: [Candle],
        signalIdx: Int,
        exitConfig: BacktestExitConfig,
        hasBuySignalByDay: [Bool]
    ) -> SimResult? {

        let entryPrice = candles[signalIdx].close
        guard entryPrice > 0 else { return nil }

        let netEntryPrice = applyTransactionCosts(
            grossPrice: entryPrice,
            isBuy: true,
            exitConfig: exitConfig
        )

        let tp1Price = entryPrice * (1.0 + exitConfig.tp1Pct / 100.0)
        let tp2Price = entryPrice * (1.0 + exitConfig.tp2Pct / 100.0)
        let slPrice = entryPrice * (1.0 - exitConfig.stopLossPct / 100.0)

        var peakPrice = entryPrice
        var lowestPrice = entryPrice
        var remainingQty = 1.0
        var realizedProceeds = 0.0
        var tp1Executed = false
        var tp1ExecutedIdx: Int? = nil
        var tp1Proceeds = 0.0
        let lastIdx = candles.count - 1

        // Son gün sinyali: ertesi gün mumu yoksa pozisyonu "açık" olarak başlat.
        if signalIdx >= lastIdx {
            return SimResult(
                effectiveExitPrice: entryPrice,
                finalExitIdx: signalIdx,
                finalExitReason: .open,
                daysHeld: 0,
                realizedReturnPct: 0,
                peakReturnPct: 0,
                maxDrawdownPct: 0,
                tp1ExecutedIdx: nil,
                tp1Proceeds: 0
            )
        }

        for dayIdx in (signalIdx + 1)...lastIdx {
            let candle = candles[dayIdx]
            let daysHeld = dayIdx - signalIdx

            // Track peak & trough
            if candle.high > peakPrice { peakPrice = candle.high }
            if candle.low < lowestPrice { lowestPrice = candle.low }

            // ── 1. STOP LOSS (önce kontrol — kötü senaryo varsayımı) ──

            // Gap down: açılış SL'nin altında → open fiyatından çık
            if candle.open <= slPrice {
                let netExit = applyTransactionCosts(grossPrice: candle.open, isBuy: false, exitConfig: exitConfig)
                realizedProceeds += remainingQty * netExit
                let peakRet = (peakPrice - entryPrice) / entryPrice * 100
                let maxDD = (lowestPrice - entryPrice) / entryPrice * 100
                return SimResult(
                    effectiveExitPrice: realizedProceeds,
                    finalExitIdx: dayIdx,
                    finalExitReason: .stopLoss,
                    daysHeld: daysHeld,
                    realizedReturnPct: ((realizedProceeds - netEntryPrice) / netEntryPrice) * 100,
                    peakReturnPct: peakRet,
                    maxDrawdownPct: maxDD,
                    tp1ExecutedIdx: tp1ExecutedIdx,
                    tp1Proceeds: tp1Proceeds
                )
            }

            // Gün içi SL: low SL'ye değdi → SL fiyatından çık
            if candle.low <= slPrice {
                let netExit = applyTransactionCosts(grossPrice: slPrice, isBuy: false, exitConfig: exitConfig)
                realizedProceeds += remainingQty * netExit
                let peakRet = (peakPrice - entryPrice) / entryPrice * 100
                let maxDD = (slPrice - entryPrice) / entryPrice * 100
                return SimResult(
                    effectiveExitPrice: realizedProceeds,
                    finalExitIdx: dayIdx,
                    finalExitReason: .stopLoss,
                    daysHeld: daysHeld,
                    realizedReturnPct: ((realizedProceeds - netEntryPrice) / netEntryPrice) * 100,
                    peakReturnPct: peakRet,
                    maxDrawdownPct: maxDD,
                    tp1ExecutedIdx: tp1ExecutedIdx,
                    tp1Proceeds: tp1Proceeds
                )
            }

            // ── 2. TAKE PROFIT (kademeli TP1 / TP2) ──
            if !tp1Executed {
                if candle.open >= tp1Price {
                    let tp1Qty = remainingQty * (exitConfig.tp1SellPercent / 100.0)
                    let netExit = applyTransactionCosts(grossPrice: candle.open, isBuy: false, exitConfig: exitConfig)
                    let proceeds = tp1Qty * netExit
                    realizedProceeds += proceeds
                    tp1Proceeds += proceeds
                    remainingQty -= tp1Qty
                    tp1Executed = true
                    tp1ExecutedIdx = dayIdx
                } else if candle.high >= tp1Price {
                    let tp1Qty = remainingQty * (exitConfig.tp1SellPercent / 100.0)
                    let netExit = applyTransactionCosts(grossPrice: tp1Price, isBuy: false, exitConfig: exitConfig)
                    let proceeds = tp1Qty * netExit
                    realizedProceeds += proceeds
                    tp1Proceeds += proceeds
                    remainingQty -= tp1Qty
                    tp1Executed = true
                    tp1ExecutedIdx = dayIdx
                }
            }

            // TP1 alındığı gün TP2 kapatılmaz; TP2 en erken sonraki günlerde değerlendirilir.
            if tp1ExecutedIdx == dayIdx {
                continue
            }

            // Gap up: açılış TP2 üzerinde → kalan lotları open fiyatından çık
            if candle.open >= tp2Price {
                let netExit = applyTransactionCosts(grossPrice: candle.open, isBuy: false, exitConfig: exitConfig)
                realizedProceeds += remainingQty * netExit
                let peakRet = (candle.open - entryPrice) / entryPrice * 100
                let maxDD = (lowestPrice - entryPrice) / entryPrice * 100
                return SimResult(
                    effectiveExitPrice: realizedProceeds,
                    finalExitIdx: dayIdx,
                    finalExitReason: .takeProfit,
                    daysHeld: daysHeld,
                    realizedReturnPct: ((realizedProceeds - netEntryPrice) / netEntryPrice) * 100,
                    peakReturnPct: peakRet,
                    maxDrawdownPct: maxDD,
                    tp1ExecutedIdx: tp1ExecutedIdx,
                    tp1Proceeds: tp1Proceeds
                )
            }

            // Gün içi TP2: high TP2'ye değdi → kalan lotları TP2 fiyatından çık
            if candle.high >= tp2Price {
                let netExit = applyTransactionCosts(grossPrice: tp2Price, isBuy: false, exitConfig: exitConfig)
                realizedProceeds += remainingQty * netExit
                let peakRet = (peakPrice - entryPrice) / entryPrice * 100
                let maxDD = (lowestPrice - entryPrice) / entryPrice * 100
                return SimResult(
                    effectiveExitPrice: realizedProceeds,
                    finalExitIdx: dayIdx,
                    finalExitReason: .takeProfit,
                    daysHeld: daysHeld,
                    realizedReturnPct: ((realizedProceeds - netEntryPrice) / netEntryPrice) * 100,
                    peakReturnPct: peakRet,
                    maxDrawdownPct: maxDD,
                    tp1ExecutedIdx: tp1ExecutedIdx,
                    tp1Proceeds: tp1Proceeds
                )
            }

            // ── 3. MaxDays (AL sinyali sürüyorsa taşı) ──
            if daysHeld >= exitConfig.maxHoldDays {
                let stillBuy = dayIdx < hasBuySignalByDay.count ? hasBuySignalByDay[dayIdx] : false
                if !stillBuy {
                    let netExit = applyTransactionCosts(grossPrice: candle.close, isBuy: false, exitConfig: exitConfig)
                    realizedProceeds += remainingQty * netExit
                    let peakRet = (peakPrice - entryPrice) / entryPrice * 100
                    let maxDD = (lowestPrice - entryPrice) / entryPrice * 100
                    return SimResult(
                        effectiveExitPrice: realizedProceeds,
                        finalExitIdx: dayIdx,
                        finalExitReason: .maxDays,
                        daysHeld: daysHeld,
                        realizedReturnPct: ((realizedProceeds - netEntryPrice) / netEntryPrice) * 100,
                        peakReturnPct: peakRet,
                        maxDrawdownPct: maxDD,
                        tp1ExecutedIdx: tp1ExecutedIdx,
                        tp1Proceeds: tp1Proceeds
                    )
                }
            }

        }

        // Veri sonuna kadar TP/SL gelmedi ve AL sinyali sürdü/yeterli çıkış koşulu oluşmadıysa pozisyon açık kalır.
        let finalIdx = lastIdx
        let finalClose = candles[finalIdx].close
        let daysHeld = finalIdx - signalIdx
        let netExit = applyTransactionCosts(grossPrice: finalClose, isBuy: false, exitConfig: exitConfig)
        realizedProceeds += remainingQty * netExit
        let peakRet = (peakPrice - entryPrice) / entryPrice * 100
        let maxDD = (lowestPrice - entryPrice) / entryPrice * 100

        return SimResult(
            effectiveExitPrice: realizedProceeds,
            finalExitIdx: finalIdx,
            finalExitReason: .open,
            daysHeld: daysHeld,
            realizedReturnPct: ((realizedProceeds - netEntryPrice) / netEntryPrice) * 100,
            peakReturnPct: peakRet,
            maxDrawdownPct: maxDD,
            tp1ExecutedIdx: tp1ExecutedIdx,
            tp1Proceeds: tp1Proceeds
        )
    }
}

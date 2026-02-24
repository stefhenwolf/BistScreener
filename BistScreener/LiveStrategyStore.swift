import Foundation

enum LiveStrategyEventKind: String, Codable {
    case buy
    case sell
    case skip
}

struct LiveStrategyEvent: Identifiable, Codable {
    let id: UUID
    let date: Date
    let kind: LiveStrategyEventKind
    let symbol: String
    let amountTL: Double
    let cashAfterTL: Double
    let note: String
    let holdingsText: String

    init(
        id: UUID = UUID(),
        date: Date,
        kind: LiveStrategyEventKind,
        symbol: String,
        amountTL: Double,
        cashAfterTL: Double,
        note: String,
        holdingsText: String
    ) {
        self.id = id
        self.date = date
        self.kind = kind
        self.symbol = symbol
        self.amountTL = amountTL
        self.cashAfterTL = cashAfterTL
        self.note = note
        self.holdingsText = holdingsText
    }
}

struct LiveStrategyBuyFill: Codable, Hashable {
    let date: Date
    let quantity: Double
    let priceTL: Double
}

struct LiveStrategyHolding: Identifiable, Codable {
    let id: UUID
    let symbol: String
    let quantity: Double
    let avgCostTL: Double
    let entryDate: Date
    let signalScore: Int
    let signalQuality: String
    let lastPriceTL: Double
    let lastUpdated: Date
    let buyFills: [LiveStrategyBuyFill]
    let tp1Executed: Bool
    let tp1ExecutedAt: Date?

    init(
        id: UUID = UUID(),
        symbol: String,
        quantity: Double,
        avgCostTL: Double,
        entryDate: Date,
        signalScore: Int,
        signalQuality: String,
        lastPriceTL: Double,
        lastUpdated: Date,
        buyFills: [LiveStrategyBuyFill]? = nil,
        tp1Executed: Bool = false,
        tp1ExecutedAt: Date? = nil
    ) {
        self.id = id
        self.symbol = symbol
        self.quantity = quantity
        self.avgCostTL = avgCostTL
        self.entryDate = entryDate
        self.signalScore = signalScore
        self.signalQuality = signalQuality
        self.lastPriceTL = lastPriceTL
        self.lastUpdated = lastUpdated
        self.tp1Executed = tp1Executed
        self.tp1ExecutedAt = tp1ExecutedAt
        if let buyFills, !buyFills.isEmpty {
            self.buyFills = buyFills.sorted { $0.date < $1.date }
        } else {
            self.buyFills = [
                LiveStrategyBuyFill(date: entryDate, quantity: quantity, priceTL: avgCostTL)
            ]
        }
    }

    var marketValueTL: Double { quantity * lastPriceTL }
    var investedTL: Double { quantity * avgCostTL }
    var pnlTL: Double { marketValueTL - investedTL }
    var pnlPct: Double {
        let base = investedTL
        guard base > 0 else { return 0 }
        return ((marketValueTL / base) - 1.0) * 100.0
    }

    var firstBuyDate: Date { buyFills.first?.date ?? entryDate }
    var firstBuyPriceTL: Double { buyFills.first?.priceTL ?? avgCostTL }
    var lastBuyDate: Date { buyFills.last?.date ?? entryDate }
    var addOnCount: Int { max(0, buyFills.count - 1) }

    private enum CodingKeys: String, CodingKey {
        case id
        case symbol
        case quantity
        case avgCostTL
        case entryDate
        case signalScore
        case signalQuality
        case lastPriceTL
        case lastUpdated
        case buyFills
        case tp1Executed
        case tp1ExecutedAt
    }

    private static func normalizedStrategyExecutionTime(_ date: Date) -> Date {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: date)
        let minute = cal.component(.minute, from: date)
        let second = cal.component(.second, from: date)
        guard hour == 10, minute == 0, second == 0 else { return date }
        return cal.date(bySettingHour: 17, minute: 0, second: 0, of: date) ?? date
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        symbol = try c.decode(String.self, forKey: .symbol)
        quantity = try c.decode(Double.self, forKey: .quantity)
        avgCostTL = try c.decode(Double.self, forKey: .avgCostTL)
        let decodedEntryDate = try c.decode(Date.self, forKey: .entryDate)
        entryDate = Self.normalizedStrategyExecutionTime(decodedEntryDate)
        signalScore = try c.decode(Int.self, forKey: .signalScore)
        signalQuality = try c.decode(String.self, forKey: .signalQuality)
        lastPriceTL = try c.decode(Double.self, forKey: .lastPriceTL)
        lastUpdated = try c.decode(Date.self, forKey: .lastUpdated)
        tp1Executed = try c.decodeIfPresent(Bool.self, forKey: .tp1Executed) ?? false
        tp1ExecutedAt = try c.decodeIfPresent(Date.self, forKey: .tp1ExecutedAt)
        let decodedFills = (try c.decodeIfPresent([LiveStrategyBuyFill].self, forKey: .buyFills) ?? [])
            .map { fill in
                LiveStrategyBuyFill(
                    date: Self.normalizedStrategyExecutionTime(fill.date),
                    quantity: fill.quantity,
                    priceTL: fill.priceTL
                )
            }
        if decodedFills.isEmpty {
            buyFills = [LiveStrategyBuyFill(date: entryDate, quantity: quantity, priceTL: avgCostTL)]
        } else {
            buyFills = decodedFills.sorted { $0.date < $1.date }
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(symbol, forKey: .symbol)
        try c.encode(quantity, forKey: .quantity)
        try c.encode(avgCostTL, forKey: .avgCostTL)
        try c.encode(entryDate, forKey: .entryDate)
        try c.encode(signalScore, forKey: .signalScore)
        try c.encode(signalQuality, forKey: .signalQuality)
        try c.encode(lastPriceTL, forKey: .lastPriceTL)
        try c.encode(lastUpdated, forKey: .lastUpdated)
        try c.encode(buyFills, forKey: .buyFills)
        try c.encode(tp1Executed, forKey: .tp1Executed)
        try c.encodeIfPresent(tp1ExecutedAt, forKey: .tp1ExecutedAt)
    }
}

enum LiveStrategyPendingActionKind: String, Codable {
    case buy
    case sell
}

struct LiveStrategyPendingAction: Identifiable, Codable {
    let id: UUID
    let createdAt: Date
    let kind: LiveStrategyPendingActionKind
    let symbol: String
    let quantity: Double
    let priceTL: Double
    let amountTL: Double
    let note: String
    let signalScore: Int?
    let signalQuality: String?

    init(
        id: UUID = UUID(),
        createdAt: Date,
        kind: LiveStrategyPendingActionKind,
        symbol: String,
        quantity: Double,
        priceTL: Double,
        amountTL: Double,
        note: String,
        signalScore: Int? = nil,
        signalQuality: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.kind = kind
        self.symbol = symbol
        self.quantity = quantity
        self.priceTL = priceTL
        self.amountTL = amountTL
        self.note = note
        self.signalScore = signalScore
        self.signalQuality = signalQuality
    }
}

struct LiveStrategySettings: Codable, Equatable {
    var indexOption: IndexOption = .xu030
    var preset: TomorrowPreset = .normal
    var maxPerPositionTL: Double = 5_000
    var maxOpenPositions: Int = 8
    var tp1Pct: Double = 5
    var tp2Pct: Double = 10
    var tp1SellPercent: Double = 50
    var stopLossPct: Double = 6
    var maxHoldDays: Int = 30
    var cooldownDays: Int = 3
    var autoRefreshMinutes: Int = 5
    var requireTradeConfirmation: Bool = true

    enum CodingKeys: String, CodingKey {
        case indexOption
        case preset
        case maxPerPositionTL
        case maxOpenPositions
        case tp1Pct
        case tp2Pct
        case tp1SellPercent
        case takeProfitPct
        case stopLossPct
        case maxHoldDays
        case cooldownDays
        case autoRefreshMinutes
        case requireTradeConfirmation
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        indexOption = try c.decodeIfPresent(IndexOption.self, forKey: .indexOption) ?? indexOption
        preset = try c.decodeIfPresent(TomorrowPreset.self, forKey: .preset) ?? preset
        maxPerPositionTL = try c.decodeIfPresent(Double.self, forKey: .maxPerPositionTL) ?? maxPerPositionTL
        maxOpenPositions = try c.decodeIfPresent(Int.self, forKey: .maxOpenPositions) ?? maxOpenPositions
        let legacyTP = try c.decodeIfPresent(Double.self, forKey: .takeProfitPct) ?? tp2Pct
        tp2Pct = try c.decodeIfPresent(Double.self, forKey: .tp2Pct) ?? legacyTP
        tp1Pct = try c.decodeIfPresent(Double.self, forKey: .tp1Pct) ?? min(5, tp2Pct)
        tp1SellPercent = try c.decodeIfPresent(Double.self, forKey: .tp1SellPercent) ?? tp1SellPercent
        stopLossPct = try c.decodeIfPresent(Double.self, forKey: .stopLossPct) ?? stopLossPct
        maxHoldDays = try c.decodeIfPresent(Int.self, forKey: .maxHoldDays) ?? maxHoldDays
        cooldownDays = try c.decodeIfPresent(Int.self, forKey: .cooldownDays) ?? cooldownDays
        autoRefreshMinutes = try c.decodeIfPresent(Int.self, forKey: .autoRefreshMinutes) ?? autoRefreshMinutes
        requireTradeConfirmation = try c.decodeIfPresent(Bool.self, forKey: .requireTradeConfirmation) ?? requireTradeConfirmation
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(indexOption, forKey: .indexOption)
        try c.encode(preset, forKey: .preset)
        try c.encode(maxPerPositionTL, forKey: .maxPerPositionTL)
        try c.encode(maxOpenPositions, forKey: .maxOpenPositions)
        try c.encode(tp1Pct, forKey: .tp1Pct)
        try c.encode(tp2Pct, forKey: .tp2Pct)
        try c.encode(tp1SellPercent, forKey: .tp1SellPercent)
        try c.encode(tp2Pct, forKey: .takeProfitPct)
        try c.encode(stopLossPct, forKey: .stopLossPct)
        try c.encode(maxHoldDays, forKey: .maxHoldDays)
        try c.encode(cooldownDays, forKey: .cooldownDays)
        try c.encode(autoRefreshMinutes, forKey: .autoRefreshMinutes)
        try c.encode(requireTradeConfirmation, forKey: .requireTradeConfirmation)
    }

    func clamped() -> LiveStrategySettings {
        var out = self
        out.maxPerPositionTL = min(max(out.maxPerPositionTL, 1_000), 10_000)
        out.maxOpenPositions = min(max(out.maxOpenPositions, 1), 25)
        out.tp2Pct = min(max(out.tp2Pct, 4), 40)
        out.tp1Pct = min(max(out.tp1Pct, 1), 30)
        if out.tp1Pct >= out.tp2Pct {
            out.tp1Pct = max(1, out.tp2Pct - 1)
        }
        out.tp1SellPercent = min(max(out.tp1SellPercent, 10), 90)
        out.stopLossPct = min(max(out.stopLossPct, 2), 15)
        out.maxHoldDays = min(max(out.maxHoldDays, 5), 120)
        out.cooldownDays = min(max(out.cooldownDays, 0), 10)
        out.autoRefreshMinutes = min(max(out.autoRefreshMinutes, 1), 60)
        out.requireTradeConfirmation = true
        return out
    }
}

private struct StrategyPortfolioContributionRecord: Codable, Hashable {
    let assetID: UUID
    let symbol: String
    var quantity: Double
    var totalCostTL: Double
}

@MainActor
final class LiveStrategyStore: ObservableObject {
    @Published var isRunning: Bool = false
    @Published var isRefreshing: Bool = false
    @Published var errorText: String?
    @Published var settings: LiveStrategySettings = LiveStrategySettings() {
        didSet {
            if isHydrating { return }
            let clamped = settings.clamped()
            if clamped != settings {
                settings = clamped
                return
            }
            persist()
            restartAutoLoopIfNeeded()
            if isRunning {
                scheduleConfigRefresh(
                    reason: "Strateji ayarı değişti. Aktif strateji güncelleniyor.",
                    trigger: .settingsChanged
                )
            }
        }
    }

    @Published private(set) var startedAt: Date?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var sourceSnapshotDate: Date?
    @Published private(set) var initialCapitalTL: Double = 100_000
    @Published private(set) var cashTL: Double = 100_000
    @Published private(set) var holdings: [LiveStrategyHolding] = []
    @Published private(set) var events: [LiveStrategyEvent] = []
    @Published private(set) var pendingActions: [LiveStrategyPendingAction] = []
    @Published private(set) var skipBuyUntil: Date?
    private var portfolioContributionsByAssetID: [UUID: StrategyPortfolioContributionRecord] = [:]

    private struct Snapshot: Codable {
        let isRunning: Bool
        let startedAt: Date?
        let lastUpdated: Date?
        let sourceSnapshotDate: Date?
        let initialCapitalTL: Double
        let cashTL: Double
        let settings: LiveStrategySettings
        let holdings: [LiveStrategyHolding]
        let events: [LiveStrategyEvent]
        let pendingActions: [LiveStrategyPendingAction]
        let skipBuyUntil: Date?
        let portfolioContributions: [StrategyPortfolioContributionRecord]

        init(
            isRunning: Bool,
            startedAt: Date?,
            lastUpdated: Date?,
            sourceSnapshotDate: Date?,
            initialCapitalTL: Double,
            cashTL: Double,
            settings: LiveStrategySettings,
            holdings: [LiveStrategyHolding],
            events: [LiveStrategyEvent],
            pendingActions: [LiveStrategyPendingAction],
            skipBuyUntil: Date?,
            portfolioContributions: [StrategyPortfolioContributionRecord]
        ) {
            self.isRunning = isRunning
            self.startedAt = startedAt
            self.lastUpdated = lastUpdated
            self.sourceSnapshotDate = sourceSnapshotDate
            self.initialCapitalTL = initialCapitalTL
            self.cashTL = cashTL
            self.settings = settings
            self.holdings = holdings
            self.events = events
            self.pendingActions = pendingActions
            self.skipBuyUntil = skipBuyUntil
            self.portfolioContributions = portfolioContributions
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            isRunning = try c.decode(Bool.self, forKey: .isRunning)
            startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt)
            lastUpdated = try c.decodeIfPresent(Date.self, forKey: .lastUpdated)
            sourceSnapshotDate = try c.decodeIfPresent(Date.self, forKey: .sourceSnapshotDate)
            initialCapitalTL = try c.decode(Double.self, forKey: .initialCapitalTL)
            cashTL = try c.decode(Double.self, forKey: .cashTL)
            settings = try c.decode(LiveStrategySettings.self, forKey: .settings)
            holdings = try c.decode([LiveStrategyHolding].self, forKey: .holdings)
            events = try c.decode([LiveStrategyEvent].self, forKey: .events)
            pendingActions = try c.decodeIfPresent([LiveStrategyPendingAction].self, forKey: .pendingActions) ?? []
            skipBuyUntil = try c.decodeIfPresent(Date.self, forKey: .skipBuyUntil)
            portfolioContributions = try c.decodeIfPresent([StrategyPortfolioContributionRecord].self, forKey: .portfolioContributions) ?? []
        }
    }

    private struct SignalCandidate {
        let symbol: String
        let score: Int
        let quality: String
        let close: Double
    }

    private struct SellDecision {
        let reason: String
        let price: Double
        let sellFraction: Double
        let tp1ExecutedAfterSell: Bool
        let tp1ExecutedAtAfterSell: Date?

        var sellAll: Bool { sellFraction >= 0.999_999 }
    }

    enum RefreshTrigger {
        case manual
        case autoSchedule
        case settingsChanged
        case snapshotUpdated
        case historicalBootstrap
    }

    private let snapshotKey = "live.strategy.snapshot.v1"
    private let maxStoredEvents = 300
    private let maxStoredPendingActions = 120

    private let yahoo: YahooFinanceService
    private let indexService: BorsaIstanbulIndexService
    private let portfolioVM: PortfolioViewModel
    private var autoLoopTask: Task<Void, Never>?
    private var configRefreshTask: Task<Void, Never>?
    private var notificationObservers: [NSObjectProtocol] = []
    private var isHydrating = true

    init(yahoo: YahooFinanceService, indexService: BorsaIstanbulIndexService, portfolioVM: PortfolioViewModel) {
        self.yahoo = yahoo
        self.indexService = indexService
        self.portfolioVM = portfolioVM
        restore()
        isHydrating = false
        registerObservers()
        if isRunning {
            startAutoLoop()
        }
    }

    deinit {
        autoLoopTask?.cancel()
        configRefreshTask?.cancel()
        let center = NotificationCenter.default
        for token in notificationObservers {
            center.removeObserver(token)
        }
        notificationObservers.removeAll()
    }

    var openValueTL: Double {
        holdings.reduce(0) { $0 + $1.marketValueTL }
    }

    var totalValueTL: Double {
        cashTL + openValueTL
    }

    var totalReturnTL: Double {
        totalValueTL - initialCapitalTL
    }

    var totalReturnPct: Double {
        guard initialCapitalTL > 0 else { return 0 }
        return ((totalValueTL / initialCapitalTL) - 1.0) * 100.0
    }

    func startStrategy(initialCapitalThousands: Int, startDate: Date = Date()) {
        let clampedThousands = min(max(initialCapitalThousands, 10), 5_000)
        let cal = Calendar.current
        let now = Date()
        let startDay = cal.startOfDay(for: startDate)
        let clampedStart = min(startDay, now)

        initialCapitalTL = Double(clampedThousands) * 1_000.0
        cashTL = initialCapitalTL
        holdings = []
        events = []
        pendingActions = []
        skipBuyUntil = nil
        portfolioContributionsByAssetID.removeAll()
        startedAt = clampedStart
        sourceSnapshotDate = nil
        lastUpdated = nil
        errorText = nil
        isRunning = true
        persist()
        startAutoLoop()

        Task {
            let trigger: RefreshTrigger = cal.isDate(startDay, inSameDayAs: now) ? .manual : .historicalBootstrap
            await refreshNow(trigger: trigger)
        }
    }

    func stopStrategy() {
        let contributions = Array(portfolioContributionsByAssetID.values)
        isRunning = false
        autoLoopTask?.cancel()
        autoLoopTask = nil
        holdings = []
        events = []
        pendingActions = []
        skipBuyUntil = nil
        cashTL = initialCapitalTL
        startedAt = nil
        lastUpdated = nil
        sourceSnapshotDate = nil
        errorText = nil
        persist()

        guard !contributions.isEmpty else {
            return
        }

        Task { [weak self] in
            guard let self else { return }
            await self.rollbackPortfolioContributions(contributions)
        }
    }

    func resetStrategy() {
        stopStrategy()
        initialCapitalTL = 100_000
        cashTL = 100_000
        holdings = []
        events = []
        pendingActions = []
        skipBuyUntil = nil
        portfolioContributionsByAssetID.removeAll()
        startedAt = nil
        lastUpdated = nil
        sourceSnapshotDate = nil
        errorText = nil
        persist()
    }

    func refreshNow(trigger: RefreshTrigger = .manual) async {
        guard isRunning else { return }
        guard !isRefreshing else { return }

        isRefreshing = true
        errorText = nil
        defer {
            isRefreshing = false
            persist()
        }

        do {
            let wallClockNow = Date()
            let isHistoricalBootstrap = (trigger == .historicalBootstrap)
            if isHistoricalBootstrap {
                await runHistoricalBootstrap(until: wallClockNow)
                return
            }
            if Self.isWeekend(now: wallClockNow) {
                errorText = "Piyasa kapalı (Cumartesi/Pazar)."
                let alreadyLoggedWeekend = events.contains {
                    Calendar.current.isDate($0.date, inSameDayAs: wallClockNow) &&
                    $0.note.contains("Cumartesi/Pazar")
                }
                if !alreadyLoggedWeekend {
                    appendEvent(
                        LiveStrategyEvent(
                            date: wallClockNow,
                            kind: .skip,
                            symbol: "GENEL",
                            amountTL: 0,
                            cashAfterTL: cashTL,
                            note: "Piyasa kapalı (Cumartesi/Pazar).",
                            holdingsText: holdingsSummary(from: holdings)
                        )
                    )
                }
                return
            }
            let now = wallClockNow
            let enforceDailyMorningWindow = (trigger == .manual || trigger == .autoSchedule)
            if enforceDailyMorningWindow {
                if !Self.isMorningExecutionWindow(now: wallClockNow) {
                    errorText = "Strateji işlemleri günlük 17:00 seansında çalışır."
                    return
                }
                if let lastUpdated, Calendar.current.isDate(lastUpdated, inSameDayAs: wallClockNow) {
                    errorText = "Bugün strateji zaten çalıştı. Bir sonraki çalıştırma yarın 17:00."
                    return
                }
            }
            if !isHistoricalBootstrap, Self.isAfterMarketClose(now: wallClockNow) {
                errorText = "Borsa kapalı (18:00 sonrası). İşlemler bir sonraki seansta uygulanır."
                pendingActions.removeAll { $0.kind == .sell }
                return
            }
            let snapshot = try ScanSnapshotStore.load(forIndexRaw: settings.indexOption.rawValue)
            sourceSnapshotDate = snapshot.savedAt
            normalizeBuyFreeze(now: wallClockNow)
            let buyCutoffPassed = Self.isBuyCutoffPassed(now: wallClockNow) || isBuyFreezeActive(now: wallClockNow)
            if buyCutoffPassed {
                if isBuyFreezeActive(now: wallClockNow) {
                    errorText = "Geçmiş başlatma sonrası bugün yeni AL kapalı. Strateji yarın devam eder."
                } else {
                    errorText = "Canlı stratejide AL/ekleme sadece 17:00-18:00 arası yapılır."
                }
            }

            if !settings.requireTradeConfirmation, !pendingActions.isEmpty {
                let pendingIDs = pendingActions.map(\.id)
                for id in pendingIDs {
                    await approvePendingActionNow(id)
                }
            }

            let candidates = snapshot.results
                .compactMap { row -> SignalCandidate? in
                    guard let score = row.tomorrowTotal else { return nil }
                    if score < settings.preset.minBuyTotal { return nil }
                    if !settings.preset.allowsTierC, row.tomorrowTier == .c { return nil }
                    return SignalCandidate(
                        symbol: row.symbol.normalizedBISTSymbol(),
                        score: score,
                        quality: row.tomorrowQuality ?? "D",
                        close: row.lastClose
                    )
                }
                .sorted { lhs, rhs in
                    if lhs.score != rhs.score { return lhs.score > rhs.score }
                    return lhs.symbol < rhs.symbol
                }

            let symbolsToQuote = Set(holdings.map(\.symbol))
                .union(candidates.prefix(24).map(\.symbol))
            let quotes = await Self.fetchLatestQuotes(
                yahoo: yahoo,
                symbols: Array(symbolsToQuote)
            )
            guard isRunning else { return }
            let buySymbolSet = Set(candidates.map(\.symbol))
            sanitizePendingActions(
                openSymbols: Set(holdings.map(\.symbol)),
                buyCandidates: buySymbolSet
            )
            // Aynı gün AL sinyali olan hisselerde eski SAT onaylarını temizle.
            pendingActions.removeAll { $0.kind == .sell && buySymbolSet.contains($0.symbol) }

            var nextHoldings: [LiveStrategyHolding] = []
            nextHoldings.reserveCapacity(holdings.count)

            for holding in holdings {
                let price = quotes[holding.symbol] ?? holding.lastPriceTL
                if let sell = Self.sellDecision(
                    for: holding,
                    price: price,
                    now: now,
                    stillBuy: buySymbolSet.contains(holding.symbol),
                    settings: settings
                ) {
                    let rawSellQty = holding.quantity * min(max(sell.sellFraction, 0.0), 1.0)
                    let sellQty: Double = sell.sellAll
                        ? holding.quantity
                        : min(holding.quantity, max(1, floor(rawSellQty)))
                    if settings.requireTradeConfirmation {
                        if Self.isMarketSessionOpen(now: now) {
                            upsertPendingAction(
                                LiveStrategyPendingAction(
                                    createdAt: now,
                                    kind: .sell,
                                    symbol: holding.symbol,
                                    quantity: sellQty,
                                    priceTL: sell.price,
                                    amountTL: sellQty * sell.price,
                                    note: sell.reason
                                )
                            )
                        }

                        nextHoldings.append(
                            LiveStrategyHolding(
                                id: holding.id,
                                symbol: holding.symbol,
                                quantity: holding.quantity,
                                avgCostTL: holding.avgCostTL,
                                entryDate: holding.entryDate,
                                signalScore: holding.signalScore,
                                signalQuality: holding.signalQuality,
                                lastPriceTL: sell.price,
                                lastUpdated: now,
                                buyFills: holding.buyFills,
                                tp1Executed: holding.tp1Executed,
                                tp1ExecutedAt: holding.tp1ExecutedAt
                            )
                        )
                    } else {
                        let proceeds = sellQty * sell.price
                        cashTL += proceeds
                        let remainingQty = holding.quantity - sellQty
                        if remainingQty > 0.000_000_1 {
                            nextHoldings.append(
                                LiveStrategyHolding(
                                    id: holding.id,
                                    symbol: holding.symbol,
                                    quantity: remainingQty,
                                    avgCostTL: holding.avgCostTL,
                                    entryDate: holding.entryDate,
                                    signalScore: holding.signalScore,
                                    signalQuality: holding.signalQuality,
                                    lastPriceTL: sell.price,
                                    lastUpdated: now,
                                    buyFills: holding.buyFills,
                                    tp1Executed: sell.tp1ExecutedAfterSell,
                                    tp1ExecutedAt: sell.tp1ExecutedAtAfterSell
                                )
                            )
                        }
                        appendEvent(
                            LiveStrategyEvent(
                                date: now,
                                kind: .sell,
                                symbol: holding.symbol,
                                amountTL: proceeds,
                                cashAfterTL: cashTL,
                                note: sell.reason + (sell.sellAll ? "" : " • Kademeli"),
                                holdingsText: holdingsSummary(from: nextHoldings)
                            )
                        )
                    }
                } else {
                    nextHoldings.append(
                        LiveStrategyHolding(
                            id: holding.id,
                            symbol: holding.symbol,
                            quantity: holding.quantity,
                            avgCostTL: holding.avgCostTL,
                            entryDate: holding.entryDate,
                            signalScore: holding.signalScore,
                            signalQuality: holding.signalQuality,
                            lastPriceTL: price,
                            lastUpdated: now,
                            buyFills: holding.buyFills,
                            tp1Executed: holding.tp1Executed,
                            tp1ExecutedAt: holding.tp1ExecutedAt
                        )
                    )
                }
            }

            let openSymbols = Set(nextHoldings.map(\.symbol))
            let uniqueOpenCount = openSymbols.count
            let openSlots = max(0, settings.maxOpenPositions - uniqueOpenCount)
            var buysToPortfolio: [(symbol: String, quantity: Double, price: Double)] = []
            var reservedCash = pendingReservedCashTL()
            var spendableCash = max(0, cashTL - reservedCash)

            if !buyCutoffPassed, spendableCash > 0 {
                let buyCandidatesAll = candidates.filter { candidate in
                    !hasPendingAction(kind: .buy, symbol: candidate.symbol)
                }
                let addOnCandidates = buyCandidatesAll.filter { openSymbols.contains($0.symbol) }
                let newCandidates = buyCandidatesAll.filter { !openSymbols.contains($0.symbol) }

                let selectedAddOns = addOnCandidates
                let selectedNew = Array(newCandidates.prefix(openSlots))
                let selected = selectedAddOns + selectedNew

                if !selected.isEmpty {
                    let equalBudget = min(settings.maxPerPositionTL, spendableCash / Double(selected.count))

                    for c in selected {
                        let px = max(0.0001, quotes[c.symbol] ?? c.close)
                        let budget = min(equalBudget, spendableCash)

                        if budget <= 0 {
                            appendEvent(
                                LiveStrategyEvent(
                                    date: now,
                                    kind: .skip,
                                    symbol: c.symbol,
                                    amountTL: 0,
                                    cashAfterTL: cashTL,
                                    note: "Nakit yok",
                                    holdingsText: holdingsSummary(from: nextHoldings)
                                )
                            )
                            continue
                        }

                        let qty = floor(budget / px)
                        guard qty >= 1 else {
                            appendEvent(
                                LiveStrategyEvent(
                                    date: now,
                                    kind: .skip,
                                    symbol: c.symbol,
                                    amountTL: 0,
                                    cashAfterTL: cashTL,
                                    note: "1 lot için nakit yetersiz",
                                    holdingsText: holdingsSummary(from: nextHoldings)
                                )
                            )
                            continue
                        }
                        let spent = qty * px
                        let existingHolding = nextHoldings.first(where: { $0.symbol == c.symbol })
                        let isAddOn = (existingHolding != nil)
                        let projectedAvgCost: Double = {
                            guard let existingHolding else { return px }
                            let oldQty = max(0, existingHolding.quantity)
                            let newQty = oldQty + qty
                            guard newQty > 0 else { return px }
                            return ((oldQty * existingHolding.avgCostTL) + (qty * px)) / newQty
                        }()
                        let tp1Base = existingHolding?.firstBuyPriceTL ?? px
                        let tpSlNote = Self.tpSlSummary(avgCostTL: projectedAvgCost, tp1BaseTL: tp1Base, settings: settings)
                        let actionNote = isAddOn
                            ? "Ek AL S\(c.score) \(c.quality) • \(tpSlNote)"
                            : "S\(c.score) \(c.quality)"

                        if settings.requireTradeConfirmation {
                            upsertPendingAction(
                                LiveStrategyPendingAction(
                                    createdAt: now,
                                    kind: .buy,
                                    symbol: c.symbol,
                                    quantity: qty,
                                    priceTL: px,
                                    amountTL: spent,
                                    note: actionNote,
                                    signalScore: c.score,
                                    signalQuality: c.quality
                                )
                            )
                            reservedCash += spent
                            spendableCash = max(0, cashTL - reservedCash)
                        } else {
                            cashTL -= spent
                            if let existingIdx = nextHoldings.firstIndex(where: { $0.symbol == c.symbol }) {
                                let old = nextHoldings[existingIdx]
                                let oldQty = max(0, old.quantity)
                                let newQty = oldQty + qty
                                let newAvg = newQty > 0
                                    ? ((oldQty * old.avgCostTL) + (qty * px)) / newQty
                                    : px
                                let updatedFills = old.buyFills + [LiveStrategyBuyFill(date: now, quantity: qty, priceTL: px)]
                                nextHoldings[existingIdx] = LiveStrategyHolding(
                                    id: old.id,
                                    symbol: old.symbol,
                                    quantity: newQty,
                                    avgCostTL: newAvg,
                                    entryDate: old.entryDate,
                                    signalScore: max(old.signalScore, c.score),
                                    signalQuality: c.quality,
                                    lastPriceTL: px,
                                    lastUpdated: now,
                                    buyFills: updatedFills,
                                    tp1Executed: old.tp1Executed,
                                    tp1ExecutedAt: old.tp1ExecutedAt
                                )
                            } else {
                                let newHolding = LiveStrategyHolding(
                                    symbol: c.symbol,
                                    quantity: qty,
                                    avgCostTL: px,
                                    entryDate: now,
                                    signalScore: c.score,
                                    signalQuality: c.quality,
                                    lastPriceTL: px,
                                    lastUpdated: now
                                )
                                nextHoldings.append(newHolding)
                            }
                            buysToPortfolio.append((symbol: c.symbol, quantity: qty, price: px))

                            appendEvent(
                                LiveStrategyEvent(
                                    date: now,
                                    kind: .buy,
                                    symbol: c.symbol,
                                    amountTL: spent,
                                    cashAfterTL: cashTL,
                                    note: actionNote,
                                    holdingsText: holdingsSummary(from: nextHoldings)
                                )
                            )
                            spendableCash = max(0, spendableCash - spent)
                        }
                    }
                } else {
                    let reason: String
                    if buyCandidatesAll.isEmpty {
                        reason = """
                        AL yok
                        Aday: 0
                        Preset: \(settings.preset.title)
                        Min skor: \(settings.preset.minBuyTotal)
                        Nakit: \(String(format: "₺%.0f", spendableCash))
                        """
                    } else if openSlots <= 0 {
                        reason = """
                        AL atlandı
                        Pozisyon limiti: \(settings.maxOpenPositions)
                        Aday: \(buyCandidatesAll.count)
                        Elde: \(uniqueOpenCount)
                        """
                    } else {
                        reason = """
                        AL atlandı
                        Seçilen: 0/\(buyCandidatesAll.count)
                        Yeni slot: \(openSlots)
                        """
                    }
                    appendEvent(
                        LiveStrategyEvent(
                            date: now,
                            kind: .skip,
                            symbol: "GENEL",
                            amountTL: 0,
                            cashAfterTL: cashTL,
                            note: reason,
                            holdingsText: holdingsSummary(from: nextHoldings)
                        )
                    )
                }
            }

            holdings = nextHoldings.sorted { $0.marketValueTL > $1.marketValueTL }
            sanitizePendingActions(
                openSymbols: Set(holdings.map(\.symbol)),
                buyCandidates: buySymbolSet
            )
            lastUpdated = now

            guard isRunning else { return }
            if !buysToPortfolio.isEmpty {
                await appendBuysToPortfolio(buysToPortfolio)
                portfolioVM.loadFromDiskAndRefresh()
            }
        } catch {
            errorText = "Strateji için kayıtlı tarama bulunamadı."
        }
    }

    func approvePendingAction(_ actionID: UUID) {
        Task { [weak self] in
            await self?.approvePendingActionNow(actionID)
        }
    }

    func rejectPendingAction(_ actionID: UUID) {
        guard let idx = pendingActions.firstIndex(where: { $0.id == actionID }) else { return }
        let action = pendingActions.remove(at: idx)
        appendEvent(
            LiveStrategyEvent(
                date: Date(),
                kind: .skip,
                symbol: action.symbol,
                amountTL: 0,
                cashAfterTL: cashTL,
                note: "Onay reddi • \(action.note)",
                holdingsText: holdingsSummary(from: holdings)
            )
        )
        persist()
    }

    func approveAllPendingActions() {
        Task { [weak self] in
            guard let self else { return }
            let ids = self.pendingActions.map(\.id)
            for id in ids {
                await self.approvePendingActionNow(id)
            }
        }
    }

    func rejectAllPendingActions() {
        guard !pendingActions.isEmpty else { return }
        let now = Date()
        for action in pendingActions {
            appendEvent(
                LiveStrategyEvent(
                    date: now,
                    kind: .skip,
                    symbol: action.symbol,
                    amountTL: 0,
                    cashAfterTL: cashTL,
                    note: "Onay reddi • \(action.note)",
                    holdingsText: holdingsSummary(from: holdings)
                )
            )
        }
        pendingActions.removeAll()
        persist()
    }

    private func approvePendingActionNow(_ actionID: UUID) async {
        guard let idx = pendingActions.firstIndex(where: { $0.id == actionID }) else { return }
        let now = Date()
        if Self.isWeekend(now: now) {
            errorText = "Piyasa kapalı (Cumartesi/Pazar)."
            return
        }
        if !Self.isMarketSessionOpen(now: now) {
            errorText = "Piyasa kapalı (10:00-18:00). Onaylı işlemler seans içinde uygulanır."
            return
        }
        let action = pendingActions[idx]
        if action.kind == .buy, Self.isBuyCutoffPassed(now: now) {
            errorText = "Canlı stratejide AL onayı sadece 17:00-18:00 arası yapılır."
            return
        }
        _ = pendingActions.remove(at: idx)

        switch action.kind {
        case .buy:
            await executeApprovedBuy(action, now: now)
        case .sell:
            await executeApprovedSell(action, now: now)
        }

        holdings.sort { $0.marketValueTL > $1.marketValueTL }
        lastUpdated = now
        persist()
    }

    private func executeApprovedBuy(_ action: LiveStrategyPendingAction, now: Date) async {
        let livePrice = await Self.fetchLastClose(yahoo: yahoo, symbol: action.symbol) ?? action.priceTL
        guard livePrice > 0 else { return }
        let budget = min(action.amountTL, cashTL)
        guard budget > 0 else {
            appendEvent(
                LiveStrategyEvent(
                    date: now,
                    kind: .skip,
                    symbol: action.symbol,
                    amountTL: 0,
                    cashAfterTL: cashTL,
                    note: "Onaylı AL atlandı • Nakit yok",
                    holdingsText: holdingsSummary(from: holdings)
                )
            )
            return
        }

        let qty = floor(budget / livePrice)
        guard qty >= 1 else {
            appendEvent(
                LiveStrategyEvent(
                    date: now,
                    kind: .skip,
                    symbol: action.symbol,
                    amountTL: 0,
                    cashAfterTL: cashTL,
                    note: "Onaylı AL atlandı • 1 lot için nakit yetersiz",
                    holdingsText: holdingsSummary(from: holdings)
                )
            )
            return
        }
        let spent = qty * livePrice

        cashTL -= spent
        let isAddOn: Bool
        let appliedAvgCost: Double
        if let idx = holdings.firstIndex(where: { $0.symbol == action.symbol }) {
            let old = holdings[idx]
            let oldQty = max(0, old.quantity)
            let newQty = oldQty + qty
            let newAvg = newQty > 0 ? ((oldQty * old.avgCostTL) + spent) / newQty : livePrice
            let updatedFills = old.buyFills + [LiveStrategyBuyFill(date: now, quantity: qty, priceTL: livePrice)]
            holdings[idx] = LiveStrategyHolding(
                id: old.id,
                symbol: old.symbol,
                quantity: newQty,
                avgCostTL: newAvg,
                entryDate: old.entryDate,
                signalScore: old.signalScore,
                signalQuality: old.signalQuality,
                lastPriceTL: livePrice,
                lastUpdated: now,
                buyFills: updatedFills,
                tp1Executed: old.tp1Executed,
                tp1ExecutedAt: old.tp1ExecutedAt
            )
            isAddOn = true
            appliedAvgCost = newAvg
        } else {
            holdings.append(
                LiveStrategyHolding(
                    symbol: action.symbol,
                    quantity: qty,
                    avgCostTL: livePrice,
                    entryDate: now,
                    signalScore: action.signalScore ?? 0,
                    signalQuality: action.signalQuality ?? "-",
                    lastPriceTL: livePrice,
                    lastUpdated: now
                )
            )
            isAddOn = false
            appliedAvgCost = livePrice
        }
        let tp1Base = holdings.first(where: { $0.symbol == action.symbol })?.firstBuyPriceTL ?? livePrice
        let tpSlNote = Self.tpSlSummary(avgCostTL: appliedAvgCost, tp1BaseTL: tp1Base, settings: settings)
        let buyEventNote = isAddOn
            ? "\(action.note) • Ek AL onaylandı • \(tpSlNote)"
            : "\(action.note) • Onaylı"

        appendEvent(
            LiveStrategyEvent(
                date: now,
                kind: .buy,
                symbol: action.symbol,
                amountTL: spent,
                cashAfterTL: cashTL,
                note: buyEventNote,
                holdingsText: holdingsSummary(from: holdings)
            )
        )

        await appendBuysToPortfolio([(symbol: action.symbol, quantity: qty, price: livePrice)])
        portfolioVM.loadFromDiskAndRefresh()
    }

    private func executeApprovedSell(_ action: LiveStrategyPendingAction, now: Date) async {
        let livePrice = await Self.fetchLastClose(yahoo: yahoo, symbol: action.symbol) ?? action.priceTL
        guard livePrice > 0 else { return }
        guard let idx = holdings.firstIndex(where: { $0.symbol == action.symbol }) else { return }

        let current = holdings[idx]
        let qty = min(max(0, floor(action.quantity)), max(0, floor(current.quantity)))
        guard qty > 0 else { return }

        let proceeds = qty * livePrice
        cashTL += proceeds

        let remaining = current.quantity - qty
        if remaining <= 0.000_000_1 {
            holdings.remove(at: idx)
        } else {
            holdings[idx] = LiveStrategyHolding(
                id: current.id,
                symbol: current.symbol,
                quantity: remaining,
                avgCostTL: current.avgCostTL,
                entryDate: current.entryDate,
                signalScore: current.signalScore,
                signalQuality: current.signalQuality,
                lastPriceTL: livePrice,
                lastUpdated: now,
                buyFills: current.buyFills,
                tp1Executed: current.tp1Executed || action.note.contains("TP1"),
                tp1ExecutedAt: action.note.contains("TP1")
                    ? now
                    : current.tp1ExecutedAt
            )
        }

        appendEvent(
            LiveStrategyEvent(
                date: now,
                kind: .sell,
                symbol: action.symbol,
                amountTL: proceeds,
                cashAfterTL: cashTL,
                note: "\(action.note) • Onaylı",
                holdingsText: holdingsSummary(from: holdings)
            )
        )
    }

    private func appendEvent(_ event: LiveStrategyEvent) {
        events.append(event)
        if events.count > maxStoredEvents {
            events.removeFirst(events.count - maxStoredEvents)
        }
    }

    private func hasPendingAction(kind: LiveStrategyPendingActionKind, symbol: String) -> Bool {
        pendingActions.contains { $0.kind == kind && $0.symbol == symbol }
    }

    private func upsertPendingAction(_ action: LiveStrategyPendingAction) {
        if let idx = pendingActions.firstIndex(where: { $0.kind == action.kind && $0.symbol == action.symbol }) {
            pendingActions[idx] = action
        } else {
            pendingActions.append(action)
        }
        if pendingActions.count > maxStoredPendingActions {
            pendingActions.removeFirst(pendingActions.count - maxStoredPendingActions)
        }
    }

    private func pendingReservedCashTL() -> Double {
        pendingActions
            .filter { $0.kind == .buy }
            .reduce(0) { $0 + max(0, $1.amountTL) }
    }

    private func sanitizePendingActions(openSymbols: Set<String>, buyCandidates: Set<String>) {
        guard !pendingActions.isEmpty else { return }
        pendingActions.removeAll { action in
            switch action.kind {
            case .sell:
                return !openSymbols.contains(action.symbol)
            case .buy:
                return !buyCandidates.contains(action.symbol)
            }
        }
    }

    private func holdingsSummary(from list: [LiveStrategyHolding]) -> String {
        guard !list.isEmpty else { return "Yok" }
        return list
            .sorted { $0.marketValueTL > $1.marketValueTL }
            .prefix(3)
            .map { h in
                let clean = h.symbol.replacingOccurrences(of: ".IS", with: "")
                return "\(clean) \(String(format: "%.1f", h.quantity))l • Ort ₺\(String(format: "%.2f", h.avgCostTL)) • Son ₺\(String(format: "%.2f", h.lastPriceTL)) • \(String(format: "%+.1f%%", h.pnlPct))"
            }
            .joined(separator: " | ")
    }

    private func registerObservers() {
        let center = NotificationCenter.default

        let appSettingsToken = center.addObserver(
            forName: .appScanSettingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isRunning else { return }
                self.scheduleConfigRefresh(
                    reason: "Tarama ayarları değişti. Aktif strateji güncelleniyor.",
                    trigger: .settingsChanged
                )
            }
        }

        let signalConfigToken = center.addObserver(
            forName: .strategySignalConfigChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isRunning else { return }
                self.scheduleConfigRefresh(
                    reason: "Sinyal ayarları değişti. Aktif strateji güncelleniyor.",
                    trigger: .settingsChanged
                )
            }
        }

        let snapshotToken = center.addObserver(
            forName: .scanSnapshotSaved,
            object: nil,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor [weak self] in
                guard let self, self.isRunning else { return }
                let idxRaw = (note.userInfo?["indexRaw"] as? String)?.lowercased() ?? ""
                guard idxRaw == self.settings.indexOption.rawValue.lowercased() else { return }
                self.scheduleConfigRefresh(
                    reason: "Yeni tarama verisi algılandı. Aktif strateji güncelleniyor.",
                    trigger: .snapshotUpdated
                )
            }
        }

        notificationObservers = [appSettingsToken, signalConfigToken, snapshotToken]
    }

    private func scheduleConfigRefresh(reason: String, trigger: RefreshTrigger) {
        configRefreshTask?.cancel()
        configRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard let self, self.isRunning else { return }
            self.errorText = reason
            await self.refreshNow(trigger: trigger)
        }
    }

    private func restartAutoLoopIfNeeded() {
        guard isRunning else { return }
        startAutoLoop()
    }

    private func startAutoLoop() {
        autoLoopTask?.cancel()
        guard isRunning else { return }

        let interval = UInt64(max(60, settings.autoRefreshMinutes * 60))
        autoLoopTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval * 1_000_000_000)
                if Task.isCancelled { break }
                let now = Date()
                guard !Self.isWeekend(now: now) else { continue }
                guard Self.isMorningExecutionWindow(now: now) else { continue }
                if let lastUpdated = self.lastUpdated, Calendar.current.isDate(lastUpdated, inSameDayAs: now) {
                    continue
                }
                await self.refreshNow(trigger: .autoSchedule)
            }
        }
    }

    private static func isBuyCutoffPassed(
        now: Date,
        executionHour: Int = 17,
        closeHour: Int = 18
    ) -> Bool {
        let hour = Calendar.current.component(.hour, from: now)
        return hour < executionHour || hour >= closeHour
    }

    private static func isMorningExecutionWindow(
        now: Date,
        hour: Int = 17
    ) -> Bool {
        Calendar.current.component(.hour, from: now) == hour
    }

    private static func isAfterMarketClose(
        now: Date,
        closeHour: Int = 18
    ) -> Bool {
        Calendar.current.component(.hour, from: now) >= closeHour
    }

    private static func isMarketSessionOpen(
        now: Date,
        openHour: Int = 10,
        closeHour: Int = 18
    ) -> Bool {
        if isWeekend(now: now) { return false }
        let hour = Calendar.current.component(.hour, from: now)
        return hour >= openHour && hour < closeHour
    }

    private static func isWeekend(now: Date) -> Bool {
        let weekday = Calendar.current.component(.weekday, from: now)
        return weekday == 1 || weekday == 7
    }

    private struct HistoricalBootstrapPosition {
        let symbol: String
        let quantity: Double
        let invested: Double
        let avgCostTL: Double
        let entryDate: Date
        let signalScore: Int
        let signalQuality: String
        let exitDay: Date
        let exitReason: ExitReason
        let returnPct: Double
        let daysHeld: Int
        let plannedTotalProceeds: Double
        let tp1PlannedProceeds: Double
        let tp1Day: Date?
        let tp1Applied: Bool
    }

    private func normalizeBuyFreeze(now: Date) {
        if let skipBuyUntil, now >= skipBuyUntil {
            self.skipBuyUntil = nil
        }
    }

    private func isBuyFreezeActive(now: Date) -> Bool {
        guard let skipBuyUntil else { return false }
        return now < skipBuyUntil
    }

    private func executionDate(for day: Date, hour: Int = 17) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
    }

    private func runHistoricalBootstrap(until wallClockNow: Date) async {
        guard let startedAt else { return }
        let cal = Calendar.current
        let startDay = cal.startOfDay(for: startedAt)
        let today = cal.startOfDay(for: wallClockNow)
        let replayEndDay = today
        guard startDay <= replayEndDay else {
            errorText = "Geçmiş gün bulunamadı. Strateji canlı takipte."
            return
        }
        let buyEndDay = today

        errorText = "Geçmiş strateji hazırlanıyor..."

        do {
            let exitConfig = BacktestExitConfig(
                tp1Pct: settings.tp1Pct,
                tp2Pct: settings.tp2Pct,
                tp1SellPercent: settings.tp1SellPercent,
                stopLossPct: settings.stopLossPct,
                maxHoldDays: settings.maxHoldDays,
                cooldownDays: settings.cooldownDays
            )
            let portfolioConfig = BacktestPortfolioConfig(addOnMode: .off, addOnWaitDays: 5)

            let trades = try await BacktestEngine.runBacktestBackground(
                indexService: indexService,
                yahoo: yahoo,
                indexOption: settings.indexOption,
                preset: settings.preset,
                exitConfig: exitConfig,
                portfolioConfig: portfolioConfig,
                includeTodaySignals: true
            ) { _, _, _ in }

            let filtered = trades.filter { trade in
                let day = cal.startOfDay(for: trade.entryDate)
                return day >= startDay && day <= buyEndDay
            }

            let simulated = simulateHistoricalState(
                trades: filtered,
                startDay: startDay,
                buyEndDay: buyEndDay,
                replayEndDay: replayEndDay
            )

            cashTL = simulated.cash
            holdings = simulated.holdings
            events = simulated.events
            pendingActions = []
            lastUpdated = wallClockNow
            sourceSnapshotDate = nil
            skipBuyUntil = nil
            await refreshHoldingsWithLatestQuotes(now: wallClockNow)

            if !simulated.portfolioBuys.isEmpty {
                await appendBuysToPortfolio(simulated.portfolioBuys)
            }
            await refreshPortfolioAfterBootstrap()

            if filtered.isEmpty {
                errorText = "Geçmiş dönemde AL sinyali yok. Strateji canlı takipte."
            } else {
                errorText = "Geçmiş strateji yüklendi. 24 Şubat 2026 dahil işlendi."
            }
        } catch {
            errorText = "Geçmiş strateji hesaplanamadı: \(error.localizedDescription)"
        }
    }

    private func simulateHistoricalState(
        trades: [BacktestTradeResult],
        startDay: Date,
        buyEndDay: Date,
        replayEndDay: Date
    ) -> (cash: Double, holdings: [LiveStrategyHolding], events: [LiveStrategyEvent], portfolioBuys: [(symbol: String, quantity: Double, price: Double)], lastUpdated: Date) {
        let cal = Calendar.current
        let orderedTrades = trades.sorted { lhs, rhs in
            if lhs.entryDate != rhs.entryDate { return lhs.entryDate < rhs.entryDate }
            if lhs.signalScore != rhs.signalScore { return lhs.signalScore > rhs.signalScore }
            return lhs.symbol < rhs.symbol
        }
        let entryBuckets = Dictionary(grouping: orderedTrades) { cal.startOfDay(for: $0.entryDate) }

        var cash = initialCapitalTL
        var open: [UUID: HistoricalBootstrapPosition] = [:]
        var events: [LiveStrategyEvent] = []
        events.reserveCapacity(min(maxStoredEvents, 200))

        func appendEvent(_ event: LiveStrategyEvent) {
            events.append(event)
            if events.count > maxStoredEvents {
                events.removeFirst(events.count - maxStoredEvents)
            }
        }

        func openHoldingsText(_ positions: [UUID: HistoricalBootstrapPosition]) -> String {
            guard !positions.isEmpty else { return "Yok" }
            var bySymbol: [String: (quantity: Double, totalCost: Double)] = [:]
            for p in positions.values {
                var row = bySymbol[p.symbol] ?? (0, 0)
                row.quantity += p.quantity
                row.totalCost += p.invested
                bySymbol[p.symbol] = row
            }
            return bySymbol
                .sorted { $0.value.totalCost > $1.value.totalCost }
                .prefix(3)
                .map { item in
                    let clean = item.key.replacingOccurrences(of: ".IS", with: "")
                    let qty = max(0.0, item.value.quantity)
                    let avg = qty > 0 ? (item.value.totalCost / qty) : 0
                    return "\(clean) \(String(format: "%.1f", qty))l • Ort ₺\(String(format: "%.2f", avg))"
                }
                .joined(separator: " | ")
        }

        var day = startDay
        while day <= replayEndDay {
            let current = executionDate(for: day)
            let buyExecution = executionDate(for: day, hour: 17)
            if Self.isWeekend(now: day) {
                appendEvent(
                    LiveStrategyEvent(
                        date: buyExecution,
                        kind: .skip,
                        symbol: "GENEL",
                        amountTL: 0,
                        cashAfterTL: cash,
                        note: "Piyasa kapalı (Cumartesi/Pazar).",
                        holdingsText: openHoldingsText(open)
                    )
                )
                guard let nextDay = cal.date(byAdding: .day, value: 1, to: day) else { break }
                day = nextDay
                continue
            }

            let todaysSignals: [BacktestTradeResult] = day <= buyEndDay
                ? (entryBuckets[day] ?? []).sorted { lhs, rhs in
                    if lhs.signalScore != rhs.signalScore { return lhs.signalScore > rhs.signalScore }
                    return lhs.symbol < rhs.symbol
                }
                : []
            let todaysBuySymbols = Set(todaysSignals.map { $0.symbol.normalizedBISTSymbol() })

            // TP1 sadece bir kez ve gerçekleştiği günde işlenir; kalan lotlar sonraki günlerde TP2/Süre ile kapanır.
            let tp1IDs: [UUID] = open.compactMap { entry in
                let id = entry.key
                let p = entry.value
                guard !p.tp1Applied else { return nil }
                guard let tp1Day = p.tp1Day else { return nil }
                return tp1Day <= day ? id : nil
            }
            for id in tp1IDs {
                guard let p = open[id] else { continue }
                let tp1Proceeds = max(0, p.tp1PlannedProceeds)
                guard tp1Proceeds > 0.000_000_1 else {
                    open[id] = HistoricalBootstrapPosition(
                        symbol: p.symbol,
                        quantity: p.quantity,
                        invested: p.invested,
                        avgCostTL: p.avgCostTL,
                        entryDate: p.entryDate,
                        signalScore: p.signalScore,
                        signalQuality: p.signalQuality,
                        exitDay: p.exitDay,
                        exitReason: p.exitReason,
                        returnPct: p.returnPct,
                        daysHeld: p.daysHeld,
                        plannedTotalProceeds: p.plannedTotalProceeds,
                        tp1PlannedProceeds: p.tp1PlannedProceeds,
                        tp1Day: p.tp1Day,
                        tp1Applied: true
                    )
                    continue
                }
                cash += tp1Proceeds
                let sellFraction = min(max(settings.tp1SellPercent / 100.0, 0.0), 1.0)
                let soldQty = min(p.quantity, max(1, floor(p.quantity * sellFraction)))
                let remainingQty = max(0, p.quantity - soldQty)
                let remainingInvested = max(0, p.avgCostTL * remainingQty)
                if remainingQty <= 0.000_000_1 {
                    _ = open.removeValue(forKey: id)
                } else {
                    open[id] = HistoricalBootstrapPosition(
                        symbol: p.symbol,
                        quantity: remainingQty,
                        invested: remainingInvested,
                        avgCostTL: p.avgCostTL,
                        entryDate: p.entryDate,
                        signalScore: p.signalScore,
                        signalQuality: p.signalQuality,
                        exitDay: p.exitDay,
                        exitReason: p.exitReason,
                        returnPct: p.returnPct,
                        daysHeld: p.daysHeld,
                        plannedTotalProceeds: p.plannedTotalProceeds,
                        tp1PlannedProceeds: p.tp1PlannedProceeds,
                        tp1Day: p.tp1Day,
                        tp1Applied: true
                    )
                }
                appendEvent(
                    LiveStrategyEvent(
                        date: current,
                        kind: .sell,
                        symbol: p.symbol,
                        amountTL: tp1Proceeds,
                        cashAfterTL: cash,
                        note: String(format: "TP1 +%.1f%% • %%%.0f SAT • %dg", settings.tp1Pct, settings.tp1SellPercent, p.daysHeld),
                        holdingsText: openHoldingsText(open)
                    )
                )
            }

            let closingIDs = open.compactMap { id, p in
                (p.exitReason != .open && p.exitDay <= day) ? id : nil
            }
            for id in closingIDs {
                guard let p = open[id] else { continue }
                if p.exitReason == .stopLoss, todaysBuySymbols.contains(p.symbol.normalizedBISTSymbol()) {
                    // Aynı gün AL sinyali varsa SL kapanışını iptal et; pozisyon açık kalır.
                    open[id] = HistoricalBootstrapPosition(
                        symbol: p.symbol,
                        quantity: p.quantity,
                        invested: p.invested,
                        avgCostTL: p.avgCostTL,
                        entryDate: p.entryDate,
                        signalScore: p.signalScore,
                        signalQuality: p.signalQuality,
                        exitDay: replayEndDay,
                        exitReason: .open,
                        returnPct: p.returnPct,
                        daysHeld: p.daysHeld,
                        plannedTotalProceeds: p.plannedTotalProceeds,
                        tp1PlannedProceeds: p.tp1PlannedProceeds,
                        tp1Day: p.tp1Day,
                        tp1Applied: p.tp1Applied
                    )
                    continue
                }
                _ = open.removeValue(forKey: id)
                let proceeds: Double = p.tp1Applied
                    ? max(0, p.plannedTotalProceeds - p.tp1PlannedProceeds)
                    : p.plannedTotalProceeds
                cash += proceeds
                let closeReason: String = {
                    if p.exitReason == .takeProfit, p.tp1Applied {
                        return String(format: "TP2 +%.1f%% • Kalan SAT", settings.tp2Pct)
                    }
                    return Self.replayExitReasonText(p.exitReason)
                }()
                appendEvent(
                    LiveStrategyEvent(
                        date: current,
                        kind: .sell,
                        symbol: p.symbol,
                        amountTL: proceeds,
                        cashAfterTL: cash,
                        note: "\(closeReason) • \(p.daysHeld)g • " + String(format: "%+.1f%%", p.returnPct),
                        holdingsText: openHoldingsText(open)
                    )
                )
            }

            if day <= buyEndDay {
                if !todaysSignals.isEmpty {
                    let openSymbols = Set(open.values.map(\.symbol))
                    var eligible: [BacktestTradeResult] = []
                    var seenSymbols: Set<String> = []
                    for t in todaysSignals {
                        let normalized = t.symbol.normalizedBISTSymbol()
                        if seenSymbols.contains(normalized) { continue }
                        seenSymbols.insert(normalized)
                        eligible.append(t)
                    }

                    let uniqueOpenCount = openSymbols.count
                    let openSlots = max(0, settings.maxOpenPositions - uniqueOpenCount)
                    let addOnEligible = eligible.filter { openSymbols.contains($0.symbol.normalizedBISTSymbol()) }
                    let newEligible = eligible.filter { !openSymbols.contains($0.symbol.normalizedBISTSymbol()) }
                    let selectedAddOns = addOnEligible
                    let selectedNew = Array(newEligible.prefix(openSlots))
                    let selected = selectedAddOns + selectedNew

                    if selected.isEmpty, !eligible.isEmpty, openSlots <= 0 {
                        appendEvent(
                            LiveStrategyEvent(
                                date: buyExecution,
                                kind: .skip,
                                symbol: "GENEL",
                                amountTL: 0,
                                cashAfterTL: cash,
                                note: """
                                AL atlandı
                                Pozisyon limiti: \(settings.maxOpenPositions)
                                Aday: \(eligible.count)
                                Elde: \(openSymbols.count)
                                """,
                                holdingsText: openHoldingsText(open)
                            )
                        )
                    } else if eligible.isEmpty {
                        appendEvent(
                            LiveStrategyEvent(
                                date: buyExecution,
                                kind: .skip,
                                symbol: "GENEL",
                                amountTL: 0,
                                cashAfterTL: cash,
                                note: """
                                AL yok
                                Aday: 0
                                Preset: \(settings.preset.title)
                                Min skor: \(settings.preset.minBuyTotal)
                                Nakit: \(String(format: "₺%.0f", cash))
                                """,
                                holdingsText: openHoldingsText(open)
                            )
                        )
                    } else if eligible.count > selected.count {
                        appendEvent(
                            LiveStrategyEvent(
                                date: buyExecution,
                                kind: .skip,
                                symbol: "GENEL",
                                amountTL: 0,
                                cashAfterTL: cash,
                                note: """
                                AL atlandı
                                Seçilen: \(selected.count)/\(eligible.count)
                                Yeni slot: \(openSlots)
                                """,
                                holdingsText: openHoldingsText(open)
                            )
                        )
                    }

                    if !selected.isEmpty {
                        let equalBudget = min(settings.maxPerPositionTL, cash / Double(selected.count))
                        for t in selected {
                            if cash <= 0 {
                                appendEvent(
                                    LiveStrategyEvent(
                                        date: buyExecution,
                                        kind: .skip,
                                        symbol: t.symbol.normalizedBISTSymbol(),
                                        amountTL: 0,
                                        cashAfterTL: cash,
                                        note: "Nakit yok",
                                        holdingsText: openHoldingsText(open)
                                    )
                                )
                                continue
                            }

                            let price = max(0.0001, t.entryPrice)
                            let budget = min(equalBudget, cash)
                            if budget <= 0 {
                                continue
                            }

                            let qty = floor(budget / price)
                            if qty < 1 { continue }
                            let spent = qty * price

                            let symbol = t.symbol.normalizedBISTSymbol()
                            let plannedTotalProceeds = max(0, spent * (1.0 + t.returnPct / 100.0))
                            let scaledTp1Proceeds: Double = {
                                guard let raw = t.tp1Proceeds, t.entryPrice > 0 else { return 0 }
                                return max(0, raw * (spent / t.entryPrice))
                            }()
                            let tp1PlannedProceeds = min(plannedTotalProceeds, scaledTp1Proceeds)
                            let tp1Day = t.tp1Date.map { cal.startOfDay(for: $0) }
                            cash -= spent
                            open[UUID()] = HistoricalBootstrapPosition(
                                symbol: symbol,
                                quantity: qty,
                                invested: spent,
                                avgCostTL: price,
                                entryDate: buyExecution,
                                signalScore: t.signalScore,
                                signalQuality: t.signalQuality,
                                exitDay: cal.startOfDay(for: t.exitDate),
                                exitReason: t.exitReason,
                                returnPct: t.returnPct,
                                daysHeld: t.daysHeld,
                                plannedTotalProceeds: plannedTotalProceeds,
                                tp1PlannedProceeds: tp1PlannedProceeds,
                                tp1Day: tp1Day,
                                tp1Applied: tp1PlannedProceeds <= 0.000_000_1
                            )

                            appendEvent(
                                LiveStrategyEvent(
                                    date: buyExecution,
                                    kind: .buy,
                                    symbol: symbol,
                                    amountTL: spent,
                                    cashAfterTL: cash,
                                    note: "S\(t.signalScore) \(t.signalQuality) • \(Self.tpSlSummary(avgCostTL: price, settings: settings))",
                                    holdingsText: openHoldingsText(open)
                                )
                            )
                        }
                    }
                }
                else if cash > 0 {
                    appendEvent(
                        LiveStrategyEvent(
                            date: buyExecution,
                            kind: .skip,
                            symbol: "GENEL",
                            amountTL: 0,
                            cashAfterTL: cash,
                            note: """
                            AL yok
                            Aday: 0
                            Preset: \(settings.preset.title)
                            Min skor: \(settings.preset.minBuyTotal)
                            Nakit: \(String(format: "₺%.0f", cash))
                            """,
                            holdingsText: openHoldingsText(open)
                        )
                    )
                }
            }

            guard let nextDay = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = nextDay
        }

        var aggregate: [String: (
            quantity: Double,
            cost: Double,
            entryDate: Date,
            score: Int,
            quality: String,
            fills: [LiveStrategyBuyFill],
            tp1Executed: Bool,
            tp1ExecutedAt: Date?
        )] = [:]
        for p in open.values {
            var row = aggregate[p.symbol] ?? (0, 0, p.entryDate, p.signalScore, p.signalQuality, [], false, nil)
            row.quantity += p.quantity
            row.cost += p.invested
            if p.entryDate < row.entryDate { row.entryDate = p.entryDate }
            if p.signalScore > row.score {
                row.score = p.signalScore
                row.quality = p.signalQuality
            }
            if p.tp1Applied {
                row.tp1Executed = true
                if let tp1Day = p.tp1Day {
                    let tp1At = executionDate(for: tp1Day)
                    if let current = row.tp1ExecutedAt {
                        row.tp1ExecutedAt = max(current, tp1At)
                    } else {
                        row.tp1ExecutedAt = tp1At
                    }
                }
            }
            row.fills.append(
                LiveStrategyBuyFill(
                    date: p.entryDate,
                    quantity: p.quantity,
                    priceTL: p.avgCostTL
                )
            )
            aggregate[p.symbol] = row
        }

        let lastUpdated = executionDate(for: replayEndDay)
        let holdings = aggregate.map { symbol, row in
            let avgCost = row.quantity > 0 ? (row.cost / row.quantity) : 0
            return LiveStrategyHolding(
                symbol: symbol,
                quantity: row.quantity,
                avgCostTL: avgCost,
                entryDate: row.entryDate,
                signalScore: row.score,
                signalQuality: row.quality,
                lastPriceTL: avgCost,
                lastUpdated: lastUpdated,
                buyFills: row.fills,
                tp1Executed: row.tp1Executed,
                tp1ExecutedAt: row.tp1ExecutedAt
            )
        }
        .sorted { $0.marketValueTL > $1.marketValueTL }

        let portfolioBuys = holdings
            .filter { $0.quantity > 0 && $0.avgCostTL > 0 }
            .map { h in
                (symbol: h.symbol, quantity: h.quantity, price: h.avgCostTL)
            }

        return (
            cash: cash,
            holdings: holdings,
            events: events,
            portfolioBuys: portfolioBuys,
            lastUpdated: lastUpdated
        )
    }

    private func refreshHoldingsWithLatestQuotes(now: Date) async {
        guard !holdings.isEmpty else { return }
        let symbols = Array(Set(holdings.map(\.symbol)))
        let quotes = await Self.fetchLatestQuotes(yahoo: yahoo, symbols: symbols)
        guard !quotes.isEmpty else { return }

        holdings = holdings
            .map { h in
                let px = quotes[h.symbol] ?? h.lastPriceTL
                return LiveStrategyHolding(
                    id: h.id,
                    symbol: h.symbol,
                    quantity: h.quantity,
                    avgCostTL: h.avgCostTL,
                    entryDate: h.entryDate,
                    signalScore: h.signalScore,
                    signalQuality: h.signalQuality,
                    lastPriceTL: px,
                    lastUpdated: now,
                    buyFills: h.buyFills,
                    tp1Executed: h.tp1Executed,
                    tp1ExecutedAt: h.tp1ExecutedAt
                )
            }
            .sorted { $0.marketValueTL > $1.marketValueTL }
    }

    private func refreshPortfolioAfterBootstrap() async {
        var retries = 12
        while portfolioVM.isLoading, retries > 0 {
            retries -= 1
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        portfolioVM.clearPriceCache()
        portfolioVM.loadFromDiskAndRefresh()
    }

    private static func tpSlSummary(avgCostTL: Double, tp1BaseTL: Double? = nil, settings: LiveStrategySettings) -> String {
        let tp1Base = max(0.0001, tp1BaseTL ?? avgCostTL)
        let tp1 = tp1Base * (1.0 + settings.tp1Pct / 100.0)
        let tp2 = avgCostTL * (1.0 + settings.tp2Pct / 100.0)
        let sl = avgCostTL * (1.0 - settings.stopLossPct / 100.0)
        return String(format: "TP1 ₺%.2f • TP2 ₺%.2f • SL ₺%.2f", tp1, tp2, sl)
    }

    private static func replayExitReasonText(_ reason: ExitReason) -> String {
        switch reason {
        case .takeProfit:
            return "TP"
        case .stopLoss:
            return "SL"
        case .maxDays:
            return "Süre"
        case .open:
            return "Açık"
        }
    }

    private static func sellDecision(
        for holding: LiveStrategyHolding,
        price: Double,
        now: Date,
        stillBuy: Bool,
        settings: LiveStrategySettings
    ) -> SellDecision? {
        guard holding.avgCostTL > 0 else { return nil }
        let tp1Price = holding.firstBuyPriceTL * (1.0 + settings.tp1Pct / 100.0)
        let tp2Price = holding.avgCostTL * (1.0 + settings.tp2Pct / 100.0)
        let slPrice = holding.avgCostTL * (1.0 - settings.stopLossPct / 100.0)

        if price <= slPrice {
            if stillBuy {
                // Aynı gün AL sinyali devam ediyorsa SL çıkışı atlanır; pozisyon AL/ekleme ile devam eder.
                return nil
            }
            let reason = String(format: "SL -%.1f%% • Tam SAT • Eşik ₺%.2f", settings.stopLossPct, slPrice)
            return SellDecision(
                reason: reason,
                price: price,
                sellFraction: 1.0,
                tp1ExecutedAfterSell: holding.tp1Executed,
                tp1ExecutedAtAfterSell: holding.tp1ExecutedAt
            )
        }
        if !holding.tp1Executed, price >= tp1Price {
            let reason = String(format: "TP1 +%.1f%% • %%%.0f SAT • Eşik ₺%.2f", settings.tp1Pct, settings.tp1SellPercent, tp1Price)
            return SellDecision(
                reason: reason,
                price: price,
                sellFraction: settings.tp1SellPercent / 100.0,
                tp1ExecutedAfterSell: true,
                tp1ExecutedAtAfterSell: now
            )
        }
        let canRunTP2Today: Bool = {
            guard holding.tp1Executed else { return false }
            guard let tp1ExecutedAt = holding.tp1ExecutedAt else { return true } // legacy snapshots
            return !Calendar.current.isDate(tp1ExecutedAt, inSameDayAs: now)
        }()
        if canRunTP2Today, price >= tp2Price {
            let reason = String(format: "TP2 +%.1f%% • Kalan SAT • Eşik ₺%.2f", settings.tp2Pct, tp2Price)
            return SellDecision(
                reason: reason,
                price: price,
                sellFraction: 1.0,
                tp1ExecutedAfterSell: true,
                tp1ExecutedAtAfterSell: holding.tp1ExecutedAt
            )
        }

        let cal = Calendar.current
        let daysHeld = cal.dateComponents([.day], from: cal.startOfDay(for: holding.entryDate), to: cal.startOfDay(for: now)).day ?? 0
        if daysHeld >= settings.maxHoldDays, !stillBuy {
            let reason = "Süre \(settings.maxHoldDays)g • Tam SAT"
            return SellDecision(
                reason: reason,
                price: price,
                sellFraction: 1.0,
                tp1ExecutedAfterSell: holding.tp1Executed,
                tp1ExecutedAtAfterSell: holding.tp1ExecutedAt
            )
        }

        return nil
    }

    private static func fetchLatestQuotes(
        yahoo: YahooFinanceService,
        symbols: [String]
    ) async -> [String: Double] {
        let normalized = Array(Set(symbols.map { $0.normalizedBISTSymbol() }))
        guard !normalized.isEmpty else { return [:] }

        var result: [String: Double] = [:]
        result.reserveCapacity(normalized.count)

        await withTaskGroup(of: (String, Double?).self) { group in
            let workerCount = min(8, normalized.count)
            var iterator = normalized.makeIterator()

            for _ in 0..<workerCount {
                guard let sym = iterator.next() else { break }
                group.addTask {
                    let px = await Self.fetchLastClose(yahoo: yahoo, symbol: sym)
                    return (sym, px)
                }
            }

            while let (sym, price) = await group.next() {
                if let price, price > 0 {
                    result[sym] = price
                }
                if let next = iterator.next() {
                    group.addTask {
                        let px = await Self.fetchLastClose(yahoo: yahoo, symbol: next)
                        return (next, px)
                    }
                }
            }
        }

        return result
    }

    private static func fetchLastClose(yahoo: YahooFinanceService, symbol: String) async -> Double? {
        do {
            let candles = try await yahoo.fetchDailyCandles(symbol: symbol, range: "5d")
            return candles.last?.close
        } catch {
            return nil
        }
    }

    private func appendBuysToPortfolio(_ buys: [(symbol: String, quantity: Double, price: Double)]) async {
        guard !buys.isEmpty else { return }

        var assets = await PortfolioStore.shared.load()
        var addedContributions: [StrategyPortfolioContributionRecord] = []
        addedContributions.reserveCapacity(buys.count)

        for buy in buys {
            guard buy.quantity > 0, buy.price > 0 else { continue }
            let normalized = buy.symbol.normalizedBISTSymbol()
            let cost = buy.quantity * buy.price

            if let idx = assets.firstIndex(where: { a in
                a.type == .stock && a.symbol.normalizedBISTSymbol() == normalized
            }) {
                var existing = assets[idx]
                let oldQty = max(0, existing.quantity)
                let oldCost = max(0, existing.avgCostTRY ?? buy.price)
                let newQty = oldQty + buy.quantity
                existing.quantity = newQty
                existing.avgCostTRY = newQty > 0
                    ? ((oldQty * oldCost) + (buy.quantity * buy.price)) / newQty
                    : buy.price
                assets[idx] = existing

                addedContributions.append(
                    StrategyPortfolioContributionRecord(
                        assetID: existing.id,
                        symbol: normalized,
                        quantity: buy.quantity,
                        totalCostTL: cost
                    )
                )
            } else {
                let display = normalized.replacingOccurrences(of: ".IS", with: "")
                let newAsset =
                    Asset(
                        type: .stock,
                        name: display,
                        symbol: normalized,
                        quantity: buy.quantity,
                        avgCostTRY: buy.price
                    )
                assets.append(newAsset)

                addedContributions.append(
                    StrategyPortfolioContributionRecord(
                        assetID: newAsset.id,
                        symbol: normalized,
                        quantity: buy.quantity,
                        totalCostTL: cost
                    )
                )
            }
        }

        await PortfolioStore.shared.save(assets)
        mergePortfolioContributions(addedContributions)
    }

    private func mergePortfolioContributions(_ added: [StrategyPortfolioContributionRecord]) {
        guard !added.isEmpty else { return }
        for c in added {
            if var current = portfolioContributionsByAssetID[c.assetID] {
                current.quantity += c.quantity
                current.totalCostTL += c.totalCostTL
                portfolioContributionsByAssetID[c.assetID] = current
            } else {
                portfolioContributionsByAssetID[c.assetID] = c
            }
        }
    }

    private func rollbackPortfolioContributions(_ contributions: [StrategyPortfolioContributionRecord]) async {
        var assets = await PortfolioStore.shared.load()
        for contribution in contributions {
            Self.removeContribution(contribution, from: &assets)
        }
        await PortfolioStore.shared.save(assets)

        for contribution in contributions {
            portfolioContributionsByAssetID.removeValue(forKey: contribution.assetID)
        }
        portfolioVM.loadFromDiskAndRefresh()
        persist()
    }

    private static func removeContribution(
        _ contribution: StrategyPortfolioContributionRecord,
        from assets: inout [Asset]
    ) {
        var remainingQty = max(0, contribution.quantity)
        var remainingCost = max(0, contribution.totalCostTL)
        guard remainingQty > 0 else { return }

        if let exactIdx = assets.firstIndex(where: { $0.id == contribution.assetID }) {
            let before = remainingQty
            remainingQty = applyRemoval(
                to: &assets,
                index: exactIdx,
                removeQty: remainingQty,
                removeCostTL: remainingCost
            )
            if before > 0 {
                remainingCost = max(0, remainingCost * (remainingQty / before))
            }
        }

        guard remainingQty > 0 else { return }

        let normalized = contribution.symbol.normalizedBISTSymbol()
        var idx = 0
        while idx < assets.count, remainingQty > 0 {
            let isSameStock = assets[idx].type == .stock &&
                assets[idx].symbol.normalizedBISTSymbol() == normalized
            if !isSameStock {
                idx += 1
                continue
            }

            let before = remainingQty
            remainingQty = applyRemoval(
                to: &assets,
                index: idx,
                removeQty: remainingQty,
                removeCostTL: remainingCost
            )
            if before > 0 {
                remainingCost = max(0, remainingCost * (remainingQty / before))
            }

            if idx < assets.count {
                idx += 1
            }
        }
    }

    private static func applyRemoval(
        to assets: inout [Asset],
        index: Int,
        removeQty: Double,
        removeCostTL: Double
    ) -> Double {
        guard assets.indices.contains(index) else { return removeQty }
        var asset = assets[index]
        let qty = max(0, asset.quantity)
        guard qty > 0, removeQty > 0 else { return removeQty }

        let deductQty = min(qty, removeQty)
        let remainingQty = qty - deductQty

        let oldAvg = max(0, asset.avgCostTRY ?? 0)
        let oldTotalCost = qty * oldAvg
        let proportionalCost = removeQty > 0 ? removeCostTL * (deductQty / removeQty) : 0
        let deductCost = min(max(0, proportionalCost), oldTotalCost)
        let remainingCost = max(0, oldTotalCost - deductCost)

        if remainingQty <= 0.000_000_1 {
            assets.remove(at: index)
        } else {
            asset.quantity = remainingQty
            if oldAvg > 0 {
                asset.avgCostTRY = remainingCost / remainingQty
            }
            assets[index] = asset
        }

        return max(0, removeQty - deductQty)
    }

    private func restore() {
        defer { clampAfterRestore() }

        guard
            let data = UserDefaults.standard.data(forKey: snapshotKey),
            let snap = try? JSONDecoder().decode(Snapshot.self, from: data)
        else {
            return
        }

        isRunning = snap.isRunning
        startedAt = snap.startedAt
        lastUpdated = snap.lastUpdated
        sourceSnapshotDate = snap.sourceSnapshotDate
        initialCapitalTL = snap.initialCapitalTL
        cashTL = snap.cashTL
        settings = snap.settings
        holdings = snap.holdings
        events = snap.events
        pendingActions = snap.pendingActions
        skipBuyUntil = snap.skipBuyUntil
        var map: [UUID: StrategyPortfolioContributionRecord] = [:]
        for record in snap.portfolioContributions {
            if var current = map[record.assetID] {
                current.quantity += record.quantity
                current.totalCostTL += record.totalCostTL
                map[record.assetID] = current
            } else {
                map[record.assetID] = record
            }
        }
        portfolioContributionsByAssetID = map
    }

    private func clampAfterRestore() {
        initialCapitalTL = max(10_000, initialCapitalTL)
        cashTL = max(0, cashTL)
        settings = settings.clamped()
        normalizeBuyFreeze(now: Date())
        if events.count > maxStoredEvents {
            events = Array(events.suffix(maxStoredEvents))
        }
        if pendingActions.count > maxStoredPendingActions {
            pendingActions = Array(pendingActions.suffix(maxStoredPendingActions))
        }
    }

    private func persist() {
        let snap = Snapshot(
            isRunning: isRunning,
            startedAt: startedAt,
            lastUpdated: lastUpdated,
            sourceSnapshotDate: sourceSnapshotDate,
            initialCapitalTL: initialCapitalTL,
            cashTL: cashTL,
            settings: settings,
            holdings: holdings,
            events: events,
            pendingActions: pendingActions,
            skipBuyUntil: skipBuyUntil,
            portfolioContributions: Array(portfolioContributionsByAssetID.values)
        )
        if let data = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(data, forKey: snapshotKey)
        }
    }
}

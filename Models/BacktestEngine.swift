import Foundation

// MARK: - Backtest Result Types

struct BacktestTradeResult: Identifiable, Codable {
    let id: UUID
    let symbol: String
    let signalDate: Date
    let signalClose: Double
    let nextDayClose: Double
    let nextDayChangePct: Double
    let signalScore: Int
    let signalQuality: String
    let reasons: [String]
    let proximity: Double
    let volumeTrend: Double
    let rangeCompression: Double

    var isWin: Bool { nextDayChangePct > 0 }

    init(
        symbol: String,
        signalDate: Date,
        signalClose: Double,
        nextDayClose: Double,
        score: Int,
        quality: String,
        reasons: [String],
        proximity: Double,
        volumeTrend: Double,
        rangeCompression: Double
    ) {
        self.id = UUID()
        self.symbol = symbol
        self.signalDate = signalDate
        self.signalClose = signalClose
        self.nextDayClose = nextDayClose
        self.nextDayChangePct = ((nextDayClose - signalClose) / max(signalClose, 0.001)) * 100
        self.signalScore = score
        self.signalQuality = quality
        self.reasons = reasons
        self.proximity = proximity
        self.volumeTrend = volumeTrend
        self.rangeCompression = rangeCompression
    }
}

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

    static let empty = BacktestSummary(
        totalSignals: 0, wins: 0, losses: 0,
        winRate: 0, avgReturn: 0, avgWinReturn: 0, avgLossReturn: 0,
        maxWin: 0, maxLoss: 0, profitFactor: 0, trades: []
    )

    static func from(trades: [BacktestTradeResult]) -> BacktestSummary {
        guard !trades.isEmpty else { return .empty }

        let winsArr = trades.filter { $0.isWin }
        let lossesArr = trades.filter { !$0.isWin }

        let winCount = winsArr.count
        let lossCount = lossesArr.count

        let avgReturn = trades.map(\.nextDayChangePct).reduce(0, +) / Double(trades.count)
        let avgWin = winsArr.isEmpty ? 0 : winsArr.map(\.nextDayChangePct).reduce(0, +) / Double(winCount)
        let avgLoss = lossesArr.isEmpty ? 0 : lossesArr.map(\.nextDayChangePct).reduce(0, +) / Double(lossCount)
        let maxW = trades.map(\.nextDayChangePct).max() ?? 0
        let maxL = trades.map(\.nextDayChangePct).min() ?? 0

        let totalProfit = winsArr.map(\.nextDayChangePct).reduce(0, +)
        let totalLoss = abs(lossesArr.map(\.nextDayChangePct).reduce(0, +))
        let pf = totalLoss > 0 ? (totalProfit / totalLoss) : (totalProfit > 0 ? 99 : 0)

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
            trades: trades.sorted { $0.signalDate > $1.signalDate }
        )
    }
}

// MARK: - Backtest Engine

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

    func run(indexOption: IndexOption, preset: TomorrowPreset, lookback: Int) {
        if isRunning { return }

        errorText = nil
        summary = .empty
        progress = 0
        progressText = "Hazırlanıyor…"
        isRunning = true

        task?.cancel()

        task = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            do {
                let trades = try await self.runBacktestBackground(indexOption: indexOption, preset: preset, lookback: lookback)

                if Task.isCancelled { throw CancellationError() }

                let sum = BacktestSummary.from(trades: trades)

                await MainActor.run {
                    self.summary = sum
                    self.progress = 1
                    self.progressText = "Bitti. \(sum.totalSignals) sinyal."
                    self.isRunning = false
                }

            } catch is CancellationError {
                await MainActor.run {
                    self.isRunning = false
                    self.progressText = "İptal edildi."
                }
            } catch {
                await MainActor.run {
                    self.isRunning = false
                    self.errorText = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Background runner

    private func runBacktestBackground(
        indexOption: IndexOption,
        preset: TomorrowPreset,
        lookback: Int
    ) async throws -> [BacktestTradeResult] {

        // 1) symbol universe
        let snap = try await services.indexService.fetchSnapshot(indexCode: indexOption.rawValue)
        let symbolsAll = snap.yahooSymbols

        let symbols = symbolsAll.filter { $0.hasSuffix(".IS") }

        let total = max(1, symbols.count)
        var done = 0

        // 2) concurrency (Yahoo 429'u azaltmak için düşük tut)
        let concurrency = (indexOption == .bistAll ? 1 : (indexOption == .xu100 ? 2 : 3))
        let sem = AsyncSemaphore(value: concurrency)

        var collected: [BacktestTradeResult] = []
        collected.reserveCapacity(512)

        try await withThrowingTaskGroup(of: [BacktestTradeResult].self) { group in
            for sym in symbols {
                group.addTask { [services] in
                    await sem.wait()
                    defer { Task { await sem.signal() } }

                    if Task.isCancelled { return [] }

                    // küçük throttle (429'u düşürür)
                    try? await Task.sleep(nanoseconds: 250_000_000) // 0.25s

                    return await BacktestEngine.backtestOneSymbolStatic(
                        services: services,
                        symbol: sym,
                        preset: preset,
                        lookback: lookback
                    )
                }
            }

            for try await trades in group {
                if Task.isCancelled { throw CancellationError() }

                done += 1
                collected.append(contentsOf: trades)

                let pct = Double(done) / Double(total)
                let text = "\(done)/\(total) sembol"

                await MainActor.run {
                    self.progress = pct
                    self.progressText = text
                }
            }
        }

        return collected
    }

    // MARK: - Single symbol backtest (static helper)

    private static func backtestOneSymbolStatic(
        services: AppServices,
        symbol: String,
        preset: TomorrowPreset,
        lookback: Int
    ) async -> [BacktestTradeResult] {

        var trades: [BacktestTradeResult] = []
        do {
            let sym = symbol.normalizedBISTSymbol()

            let candles = try await services.candles.getCandles(
                symbol: sym,
                range: .mo6,
                minCount: 120,
                forceRefresh: false
            )

            guard candles.count >= 80 else { return [] }

            let startIdx = max(55, lookback + 5)
            let endIdx = candles.count - 2
            guard endIdx > startIdx else { return [] }

            for dayIdx in startIdx...endIdx {
                if Task.isCancelled { break }

                let slice = Array(candles[0...dayIdx])

                guard let signal = SignalScorer.scoreTomorrowBuyOnly(
                    candles: slice,
                    preset: preset,
                    lookback: lookback
                ) else { continue }

                let signalDay = candles[dayIdx]
                let nextDay = candles[dayIdx + 1]

                let trade = BacktestTradeResult(
                    symbol: sym,
                    signalDate: signalDay.date,
                    signalClose: signalDay.close,
                    nextDayClose: nextDay.close,
                    score: signal.total,
                    quality: signal.quality,
                    reasons: signal.reasons,
                    proximity: signal.breakdown.proximityPct,
                    volumeTrend: signal.breakdown.volumeTrend,
                    rangeCompression: signal.breakdown.rangeCompression
                )

                trades.append(trade)
            }

        } catch {
            return []
        }

        return trades
    }
}

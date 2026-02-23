import Foundation

struct MarketTickerItem: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let valueText: String
    let changePct: Double?
}

@MainActor
final class MarketTickerViewModel: ObservableObject {
    @Published var items: [MarketTickerItem] = []
    @Published var lastUpdated: Date?
    @Published var errorText: String?
    @Published var isLoading: Bool = false

    private let yahoo = YahooFinanceService()

    private var loopTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var isRefreshing = false

    // ✅ açılış bootstrap retry (ağ ısınana kadar)
    private var bootstrapTask: Task<Void, Never>?
    private var didBootstrap = false

    private let refreshInterval: TimeInterval = 60

    func start() {
        guard loopTask == nil else { return }

        // ✅ ilk açılışta 0s/2s/6s/12s dene
        if !didBootstrap {
            didBootstrap = true
            bootstrapTask?.cancel()
            bootstrapTask = Task { [weak self] in
                guard let self else { return }
                await self.refreshOnce(force: true)
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await self.refreshOnce(force: true)
            }
        }

        // periyodik döngü
        loopTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self.refreshInterval * 1_000_000_000))
                if Task.isCancelled { break }
                await self.refreshOnce(force: false)
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil

        refreshTask?.cancel()
        refreshTask = nil

        bootstrapTask?.cancel()
        bootstrapTask = nil
    }

    func refreshNow() {
        refreshTask?.cancel()
        refreshTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await self.refreshOnce(force: true)
        }
    }

    private func refreshOnce(force: Bool) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        if !force, let last = lastUpdated, Date().timeIntervalSince(last) < 10 {
            return
        }

        isLoading = items.isEmpty
        defer { isLoading = false }

        do {
            errorText = nil

            async let fx = fetchLastAndChange(symbol: "USDTRY=X", range: "10d")
            async let gold = fetchLastAndChange(symbol: "GC=F", range: "10d")
            async let silver = fetchLastAndChange(symbol: "SI=F", range: "10d")

            let (fxRes, goldRes, silverRes) = try await (fx, gold, silver)

            let tryRate = fxRes.last
            let usdPct = fxRes.changePct

            let gramPerOunce = 31.1034768
            let goldTryGram = (goldRes.last * tryRate) / gramPerOunce
            let silverTryGram = (silverRes.last * tryRate) / gramPerOunce

            let nf = NumberFormatter()
            nf.locale = Locale(identifier: "tr_TR")
            nf.numberStyle = .decimal
            nf.minimumFractionDigits = 2
            nf.maximumFractionDigits = 2

            func fmt(_ v: Double) -> String {
                nf.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v)
            }

            let newItems: [MarketTickerItem] = [
                MarketTickerItem(title: "USD/TRY", valueText: fmt(tryRate), changePct: usdPct),
                MarketTickerItem(title: "ALTIN (gr)", valueText: "₺ " + fmt(goldTryGram), changePct: goldRes.changePct),
                MarketTickerItem(title: "GÜMÜŞ (gr)", valueText: "₺ " + fmt(silverTryGram), changePct: silverRes.changePct)
            ]

            // ✅ “0” gibi anlamsız sonuçları ilk açılışta hata say (retry’a izin ver)
            let looksInvalid = (tryRate <= 0.01) || newItems.allSatisfy { $0.valueText.contains("0") }
            if looksInvalid && items.isEmpty {
                throw NSError(domain: "Ticker", code: -2, userInfo: [
                    NSLocalizedDescriptionKey: "Geçici veri sorunu (retry)"
                ])
            }

            items = newItems
            lastUpdated = Date()

        } catch is CancellationError {
            // sessiz
        } catch {
            // items boşsa kullanıcıya “deniyor” mesajı göster
            if items.isEmpty {
                errorText = error.localizedDescription
            } else {
                errorText = error.localizedDescription
            }
        }
    }

    private func fetchLastAndChange(symbol: String, range: String) async throws -> (last: Double, changePct: Double?) {
        let candles = try await yahoo.fetchDailyCandles(symbol: symbol, range: range)
        guard candles.count >= 2 else {
            return (candles.last?.close ?? 0, nil)
        }

        let last = candles[candles.count - 1].close
        let prev = candles[candles.count - 2].close

        guard prev > 0 else { return (last, nil) }

        let changePct = ((last - prev) / prev) * 100.0
        return (last, changePct)
    }
}

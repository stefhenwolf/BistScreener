//
//  PortfolioViewModel.swift
//  BistScreener
//

import Foundation

// ✅ MainActor dışı: TaskGroup içinde rahatça üretilebilsin
struct PortfolioRow: Identifiable, Hashable {
    let id: UUID
    let asset: Asset
    let lastPrice: Double?        // asset'in kendi baz fiyatı (metal için USD/ons)
    let prevClose: Double?        // dünkü kapanış (baz fiyat)
    let valueTRY: Double?         // TRY toplam değer
    let pnlTRY: Double?           // TRY toplam K/Z (avgCostTRY varsa)
    let dayPnlTRY: Double?        // günlük K/Z (dünkü kapanışa göre)
    let dayChangePct: Double?     // günlük % değişim (fiyata göre)
    let isUSDConverted: Bool      // USD->TRY dönüşümü kullandı mı?
}

@MainActor
final class PortfolioViewModel: ObservableObject {

    @Published var assets: [Asset] = []
    @Published var rows: [PortfolioRow] = []
    @Published var totalTRY: Double = 0
    @Published var lastUpdated: Date?
    @Published var isLoading: Bool = false
    @Published var errorText: String?

    private let store = PortfolioStore.shared
    private let yahoo: YahooFinanceService
    private let cloudRepository: any CloudDataRepository
    private var cloudUserID: String?
    private var localStorageUserKey: String = "guest"

    // ── USD/TRY cache (5 dk TTL) ──
    private var cachedUsdTry: Double?
    private var usdTryFetchedAt: Date?
    private let usdTryTTL: TimeInterval = 300 // 5 dakika

    // ── Fiyat cache (aynı session içinde tekrar çekmemek için) ──
    private struct PriceCache {
        let last: Double?
        let prev: Double?
        let fetchedAt: Date
    }
    private var priceCache: [String: PriceCache] = [:]
    private let priceTTL: TimeInterval = 120 // 2 dakika
    private let maxPriceFetchConcurrency: Int = 8

    init(
        yahoo: YahooFinanceService = YahooFinanceService(),
        cloudRepository: any CloudDataRepository = NoopCloudDataRepository()
    ) {
        self.yahoo = yahoo
        self.cloudRepository = cloudRepository
    }

    func setCloudUserID(_ userID: String?) {
        let normalized = userID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let clean = (normalized?.isEmpty == false) ? normalized : nil
        let newLocalKey = sanitizedStorageKey(clean)
        let userChanged = cloudUserID != clean || localStorageUserKey != newLocalKey
        guard userChanged else { return }

        cloudUserID = clean
        localStorageUserKey = newLocalKey

        Task { [weak self] in
            guard let self else { return }
            await store.setActiveUserKey(newLocalKey)
            await loadFromDisk()
            let hydratedFromCloud = await hydratePortfolioFromCloudIfPossible()
            if !hydratedFromCloud {
                await syncPortfolioToCloud(snapshot: assets)
            }
            await refreshPricesAsync()
        }
    }

    // MARK: - FX: concurrent Yahoo + Frankfurter

    private func fetchUSDTry() async -> Double? {
        // Cache kontrolü
        if let cached = cachedUsdTry,
           let at = usdTryFetchedAt,
           Date().timeIntervalSince(at) < usdTryTTL {
            return cached
        }

        // Yahoo ve Frankfurter'ı paralel çek, ilk BAŞARILI sonucu al.
        // Başarılı bir sonuç bulununca diğer görevi iptal et.
        let result: Double? = await withTaskGroup(of: Double?.self, returning: Double?.self) { group in
            group.addTask { [yahoo] in
                do {
                    let candles = try await yahoo.fetchDailyCandles(symbol: "USDTRY=X", range: "5d")
                    return candles.last?.close
                } catch {
                    return nil
                }
            }
            group.addTask {
                do {
                    return try await self.fetchUSDTryFromFrankfurter()
                } catch {
                    return nil
                }
            }

            var firstSuccess: Double?
            while let value = await group.next() {
                if let value {
                    firstSuccess = value
                    group.cancelAll()
                    break
                }
            }
            return firstSuccess
        }

        if let result {
            cachedUsdTry = result
            usdTryFetchedAt = Date()
        }
        return result
    }

    private func fetchUSDTryFromFrankfurter() async throws -> Double {
        let url = URL(string: "https://api.frankfurter.app/latest?from=USD&to=TRY")!
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        req.setValue("BistScreener/1.0 (iOS)", forHTTPHeaderField: "User-Agent")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        struct Res: Decodable { let rates: [String: Double] }
        let decoded = try JSONDecoder().decode(Res.self, from: data)

        guard let v = decoded.rates["TRY"] else {
            throw NSError(domain: "FX", code: 1, userInfo: [NSLocalizedDescriptionKey: "USD/TRY alınamadı"])
        }
        return v
    }

    // MARK: - Load / Save

    func loadFromDisk() async {
        let loaded = await store.load()
        self.assets = loaded
    }

    func loadFromDiskAndRefresh() {
        // Zaten yükleniyor ise tekrar tetikleme
        guard !isLoading else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.loadFromDisk()
            await self.refreshPricesAsync()
        }
    }

    func upsert(_ asset: Asset) {
        var normalized = asset
        normalized.symbol = Self.normalizedPortfolioSymbol(type: normalized.type, symbol: normalized.symbol)

        if let idx = assets.firstIndex(where: { $0.id == normalized.id }) {
            assets[idx] = normalized
        } else {
            // Merge satırından gelen düzenlemelerde id birebir tutmayabilir.
            let key = Self.normalizedPortfolioSymbol(type: normalized.type, symbol: normalized.symbol)
            let sameSymbolIndices = assets.indices.filter { i in
                assets[i].type == normalized.type &&
                Self.normalizedPortfolioSymbol(type: assets[i].type, symbol: assets[i].symbol) == key
            }

            if let first = sameSymbolIndices.first {
                let preserved = assets[first]
                let updated = Asset(
                    id: preserved.id,
                    type: normalized.type,
                    name: normalized.name,
                    symbol: normalized.symbol,
                    quantity: normalized.quantity,
                    avgCostTRY: normalized.avgCostTRY,
                    createdAt: preserved.createdAt
                )
                assets[first] = updated

                for idx in sameSymbolIndices.dropFirst().sorted(by: >) {
                    assets.remove(at: idx)
                }
            } else {
                assets.append(normalized)
            }
        }

        let snapshot = assets
        Task { [weak self] in
            guard let self else { return }
            await self.persistAndSync(snapshot)
        }
    }

    func delete(at offsets: IndexSet) {
        assets.remove(atOffsets: offsets)

        let snapshot = assets
        Task { [weak self] in
            guard let self else { return }
            await self.store.save(snapshot)
            await self.syncPortfolioToCloud(snapshot: snapshot)
        }
    }

    func deleteBySymbols(_ symbols: [String]) {
        let keys = Set(symbols.map { $0.uppercased() }.filter { !$0.isEmpty })
        guard !keys.isEmpty else { return }

        // UI state
        assets.removeAll { keys.contains($0.symbol.uppercased()) }

        // Disk
        let snapshot = assets
        Task { [weak self] in
            guard let self else { return }
            await self.store.save(snapshot)
            await self.syncPortfolioToCloud(snapshot: snapshot)
        }
    }

    @discardableResult
    func sellAsset(type: AssetType, symbol: String, quantity: Double) -> Bool {
        let targetQty = max(0, quantity)
        guard targetQty > 0 else { return false }

        let key = Self.normalizedPortfolioSymbol(type: type, symbol: symbol)
        guard !key.isEmpty else { return false }

        let available = assets.reduce(0.0) { partial, asset in
            guard asset.type == type else { return partial }
            let assetKey = Self.normalizedPortfolioSymbol(type: asset.type, symbol: asset.symbol)
            guard assetKey == key else { return partial }
            return partial + max(0, asset.quantity)
        }

        guard available + 1e-9 >= targetQty else { return false }

        var remaining = targetQty
        var updated: [Asset] = []
        updated.reserveCapacity(assets.count)

        for var asset in assets {
            let assetKey = Self.normalizedPortfolioSymbol(type: asset.type, symbol: asset.symbol)
            let isMatch = asset.type == type && assetKey == key
            guard isMatch, remaining > 0 else {
                updated.append(asset)
                continue
            }

            let currentQty = max(0, asset.quantity)
            let deduct = min(currentQty, remaining)
            let nextQty = currentQty - deduct
            remaining -= deduct

            if nextQty > 0.000_000_1 {
                asset.quantity = nextQty
                updated.append(asset)
            }
        }

        assets = updated
        let snapshot = assets
        Task { [weak self] in
            guard let self else { return }
            await self.persistAndSync(snapshot)
        }
        refreshPrices()
        return true
    }

    private func persistAndSync(_ snapshot: [Asset]) async {
        await store.save(snapshot)
        await syncPortfolioToCloud(snapshot: snapshot)
    }

    private func syncPortfolioToCloud(snapshot: [Asset]) async {
        guard let userID = cloudUserID else { return }
        do {
            try await cloudRepository.replacePortfolioPositions(userID: userID, assets: snapshot)
        } catch {
            await MainActor.run {
                self.errorText = "Cloud portföy yazılamadı: \(error.localizedDescription)"
            }
        }
    }

    private func hydratePortfolioFromCloudIfPossible() async -> Bool {
        guard let userID = cloudUserID else { return false }
        do {
            let remote = try await cloudRepository.fetchPortfolioPositions(userID: userID)
            guard !remote.isEmpty else { return false }
            await store.save(remote)
            await MainActor.run {
                self.assets = remote
            }
            return true
        } catch {
            await MainActor.run {
                self.errorText = "Cloud portföy okunamadı: \(error.localizedDescription)"
            }
            return false
        }
    }

    private func sanitizedStorageKey(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "guest" }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let out = String(scalars)
        return out.isEmpty ? "guest" : out
    }

    // MARK: - Refresh prices

    func refreshPrices() {
        guard !isLoading else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.refreshPricesAsync()
        }
    }

    private func refreshPricesAsync() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }

        // ✅ 1) Aynı symbol+type olanları tek satıra indir
        let list = Self.mergeAssets(assets)

        if list.isEmpty {
            rows = []
            totalTRY = 0
            lastUpdated = Date()
            publishWidgetSnapshot(rows: [], totalTRY: 0, updatedAt: lastUpdated ?? Date())
            return
        }

        // ✅ 2) USD/TRY: concurrent Yahoo + Frankfurter (cached)
        let usdTry = await fetchUSDTry()

        // ✅ 3) Concurrent fiyat çekimi (bounded concurrency + price cache)
        var tmp: [PortfolioRow] = []
        tmp.reserveCapacity(list.count)

        await withTaskGroup(of: PortfolioRow?.self) { group in
            let concurrency = max(1, min(maxPriceFetchConcurrency, list.count))
            var iterator = list.makeIterator()

            for _ in 0..<concurrency {
                guard let a = iterator.next() else { break }
                let usdTrySnap = usdTry

                group.addTask { [weak self] in
                    guard let self else { return nil }

                    let fetchSymbol: String = {
                        switch a.type {
                        case .cash:
                            return ""
                        case .metal:
                            return Self.yahooSymbolForMetal(original: a.symbol)
                        case .stock, .fund:
                            // BIST hisseleri/fonları ".IS" suffix'i gerektirir
                            return a.symbol.normalizedBISTSymbol()
                        case .fx, .crypto:
                            return a.symbol
                        }
                    }()

                    let (last, prev): (Double?, Double?)
                    if a.type == .cash {
                        (last, prev) = (1.0, 1.0)
                    } else {
                        (last, prev) = await self.fetchPrice(symbol: fetchSymbol)
                    }
                    return Self.makeRow(asset: a, lastPrice: last, prevClose: prev, usdTry: usdTrySnap)
                }
            }

            while let r = await group.next() {
                if let r { tmp.append(r) }

                guard let a = iterator.next() else { continue }
                let usdTrySnap = usdTry
                group.addTask { [weak self] in
                    guard let self else { return nil }

                    let fetchSymbol: String = {
                        switch a.type {
                        case .cash:
                            return ""
                        case .metal:
                            return Self.yahooSymbolForMetal(original: a.symbol)
                        case .stock, .fund:
                            return a.symbol.normalizedBISTSymbol()
                        case .fx, .crypto:
                            return a.symbol
                        }
                    }()

                    let (last, prev): (Double?, Double?)
                    if a.type == .cash {
                        (last, prev) = (1.0, 1.0)
                    } else {
                        (last, prev) = await self.fetchPrice(symbol: fetchSymbol)
                    }
                    return Self.makeRow(asset: a, lastPrice: last, prevClose: prev, usdTry: usdTrySnap)
                }
            }
        }

        // sıralama
        tmp.sort {
            if $0.asset.type.rawValue != $1.asset.type.rawValue {
                return $0.asset.type.rawValue < $1.asset.type.rawValue
            }
            return $0.asset.name.localizedCaseInsensitiveCompare($1.asset.name) == .orderedAscending
        }

        rows = tmp
        totalTRY = tmp.compactMap(\.valueTRY).reduce(0, +)
        lastUpdated = Date()
        publishWidgetSnapshot(rows: tmp, totalTRY: totalTRY, updatedAt: lastUpdated ?? Date())
    }

    // MARK: - Price fetch (with in-memory TTL cache)

    private func fetchPrice(symbol: String) async -> (last: Double?, prev: Double?) {
        let key = symbol.uppercased()

        // Cache hit
        if let cached = priceCache[key],
           Date().timeIntervalSince(cached.fetchedAt) < priceTTL {
            return (cached.last, cached.prev)
        }

        // Network fetch
        do {
            let candles = try await yahoo.fetchDailyCandles(symbol: symbol, range: "5d")
            let last = candles.last?.close
            let prev = candles.count >= 2 ? candles[candles.count - 2].close : nil

            priceCache[key] = PriceCache(last: last, prev: prev, fetchedAt: Date())
            return (last, prev)
        } catch {
            return (nil, nil)
        }
    }

    /// Fiyat cache'ini temizle (manuel yenileme için)
    func clearPriceCache() {
        priceCache.removeAll()
        cachedUsdTry = nil
        usdTryFetchedAt = nil
    }

    private func publishWidgetSnapshot(rows: [PortfolioRow], totalTRY: Double, updatedAt: Date) {
        let totalPnL = rows.compactMap(\.pnlTRY).reduce(0, +)
        let invested = max(0, totalTRY - totalPnL)
        let totalPnLPct = invested > 0 ? (totalPnL / invested) * 100 : 0
        let snapshot = PortfolioWidgetSnapshot(
            totalTRY: totalTRY,
            totalPnLTRY: totalPnL,
            totalPnLPct: totalPnLPct,
            assetCount: rows.count,
            updatedAt: updatedAt
        )
        WidgetSnapshotBridge.shared.writePortfolioSnapshot(snapshot)
    }

    // MARK: - Merge (same symbol+type)

    nonisolated private static func mergeAssets(_ assets: [Asset]) -> [Asset] {
        struct Key: Hashable {
            let type: AssetType
            let symbol: String
        }

        var dict: [Key: [Asset]] = [:]
        for a in assets {
            let key = Key(type: a.type, symbol: normalizedPortfolioSymbol(type: a.type, symbol: a.symbol))
            dict[key, default: []].append(a)
        }

        var merged: [Asset] = []
        merged.reserveCapacity(dict.count)

        for (key, arr) in dict {
            guard let first = arr.first else { continue }

            let totalQty = arr.reduce(0.0) { $0 + $1.quantity }

            // avgCostTRY ağırlıklı ortalama (nil olanları yok say)
            let costPairs = arr.compactMap { a -> (qty: Double, cost: Double)? in
                guard let c = a.avgCostTRY else { return nil }
                return (a.quantity, c)
            }

            let weightedAvgCost: Double? = {
                let denom = costPairs.reduce(0.0) { $0 + $1.qty }
                guard denom > 0 else { return nil }
                let numer = costPairs.reduce(0.0) { $0 + ($1.qty * $1.cost) }
                return numer / denom
            }()

            // name: en uzun olanı seç
            let bestName = arr
                .map(\.name)
                .sorted { $0.count > $1.count }
                .first ?? first.name

            // ✅ deterministik id: type|symbol
            let mergedID = stableUUID("\(key.type.rawValue)|\(key.symbol)")

            let out = Asset(
                id: mergedID,
                type: first.type,
                name: bestName,
                symbol: key.symbol,
                quantity: totalQty,
                avgCostTRY: weightedAvgCost
            )

            merged.append(out)
        }

        merged.sort {
            if $0.type.rawValue != $1.type.rawValue { return $0.type.rawValue < $1.type.rawValue }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        return merged
    }

    nonisolated private static func normalizedPortfolioSymbol(type: AssetType, symbol: String) -> String {
        let raw = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch type {
        case .stock, .fund:
            return raw.normalizedBISTSymbol()
        case .fx, .metal, .crypto:
            return raw
        case .cash:
            return "TRY"
        }
    }

    nonisolated private static func stableUUID(_ key: String) -> UUID {
        // hash stable değil; UTF8'den deterministik 16 byte üretelim
        let bytes = Array(key.utf8)
        var b = [UInt8](repeating: 0, count: 16)
        for i in 0..<16 {
            if bytes.isEmpty { b[i] = UInt8(i & 0xFF) }
            else { b[i] = bytes[i % bytes.count] &+ UInt8((i * 31) & 0xFF) }
        }
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }

    // MARK: - Metal symbol mapping (Yahoo)

    nonisolated private static func yahooSymbolForMetal(original: String) -> String {
        let s = original.uppercased()
        if s.contains("XAU") || s.contains("GOLD") { return "GC=F" }     // USD/oz
        if s.contains("XAG") || s.contains("SILVER") { return "SI=F" }   // USD/oz
        return original
    }

    // MARK: - Row valuation (TRY + Daily PnL)

    nonisolated private static func makeRow(asset: Asset, lastPrice: Double?, prevClose: Double?, usdTry: Double?) -> PortfolioRow {
        let lp = lastPrice
        let pc = prevClose

        let gramPerOunce = 31.1034768

        var valueTRY: Double? = nil
        var usedUSD = false

        var dayPnlTRY: Double? = nil
        var dayChangePct: Double? = nil

        if let lp {
            switch asset.type {
            case .cash:
                valueTRY = asset.quantity
                dayPnlTRY = 0
                dayChangePct = 0

            // ── Metal: USD/ons → TRY/gram çevrim ──
            case .metal:
                if let usdTry {
                    let tryPerGramLast = (lp * usdTry) / gramPerOunce
                    valueTRY = tryPerGramLast * asset.quantity
                    usedUSD = true

                    if let pc, pc > 0 {
                        let tryPerGramPrev = (pc * usdTry) / gramPerOunce
                        dayPnlTRY = (tryPerGramLast - tryPerGramPrev) * asset.quantity
                        dayChangePct = ((lp - pc) / pc) * 100.0
                    }
                }

            // ── BIST hisse/fon: Yahoo .IS fiyatı zaten TRY ──
            case .stock, .fund:
                valueTRY = lp * asset.quantity

                if let pc, pc > 0 {
                    dayPnlTRY = (lp - pc) * asset.quantity
                    dayChangePct = ((lp - pc) / pc) * 100.0
                }

            // ── Döviz (FX): USDTRY=X gibi, fiyat zaten TRY ──
            case .fx:
                valueTRY = lp * asset.quantity

                if let pc, pc > 0 {
                    dayPnlTRY = (lp - pc) * asset.quantity
                    dayChangePct = ((lp - pc) / pc) * 100.0
                }

            // ── Kripto: USD bazlı → TRY çevrim ──
            case .crypto:
                if let usdTry {
                    valueTRY = (lp * usdTry) * asset.quantity
                    usedUSD = true

                    if let pc, pc > 0 {
                        dayPnlTRY = ((lp - pc) * usdTry) * asset.quantity
                        dayChangePct = ((lp - pc) / pc) * 100.0
                    }
                }
            }
        }

        var pnl: Double? = nil
        if asset.type != .cash, let valueTRY, let avg = asset.avgCostTRY {
            pnl = valueTRY - (avg * asset.quantity)
        }

        return PortfolioRow(
            id: asset.id,
            asset: asset,
            lastPrice: lp,
            prevClose: pc,
            valueTRY: valueTRY,
            pnlTRY: pnl,
            dayPnlTRY: dayPnlTRY,
            dayChangePct: dayChangePct,
            isUSDConverted: usedUSD
        )
    }
}

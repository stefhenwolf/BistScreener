//
//  PortfolioViewModel.swift
//  BistScreener
//

import Foundation

// ✅ MainActor dışı: TaskGroup içinde rahatça üretilebilsin
struct PortfolioRow: Identifiable, Hashable {
    let id: UUID
    let asset: Asset
    let lastPrice: Double?        // asset’in kendi baz fiyatı (metal için USD/ons)
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
    private let yahoo = YahooFinanceService()

    // MARK: - FX fallback (Frankfurter)

    private func fetchUSDTryFromFrankfurter() async throws -> Double {
        let url = URL(string: "https://api.frankfurter.app/latest?from=USD&to=TRY")!
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
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
        Task { [weak self] in
            guard let self else { return }
            await self.loadFromDisk()
            await self.refreshPricesAsync()
        }
    }

    func upsert(_ asset: Asset) {
        // ✅ önce local state güncelle
        if let idx = assets.firstIndex(where: { $0.id == asset.id }) {
            assets[idx] = asset
        } else {
            assets.append(asset)
        }

        // ✅ store'a yaz
        Task { [store] in
            await store.upsert(asset)
        }
    }

    func delete(at offsets: IndexSet) {
        let ids = offsets.compactMap { idx -> UUID? in
            guard assets.indices.contains(idx) else { return nil }
            return assets[idx].id
        }

        assets.remove(atOffsets: offsets)

        Task { [store] in
            await store.delete(ids: ids)
        }
    }
    func deleteBySymbols(_ symbols: [String]) {
        let keys = Set(symbols.map { $0.uppercased() }.filter { !$0.isEmpty })
        guard !keys.isEmpty else { return }

        // UI state
        assets.removeAll { keys.contains($0.symbol.uppercased()) }

        // Disk
        Task { [store] in
            await store.delete(symbols: Array(keys))
        }
    }


    // MARK: - Refresh prices

    func refreshPrices() {
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
            return
        }

        // 1) USDTRY: önce Yahoo
        var usdTry: Double? = nil
        do {
            let usdCandles = try await yahoo.fetchDailyCandles(symbol: "USDTRY=X", range: "1mo")
            usdTry = usdCandles.last?.close
        } catch {
            usdTry = nil
        }

        // 2) Yahoo olmadıysa Frankfurter fallback
        if usdTry == nil {
            do { usdTry = try await fetchUSDTryFromFrankfurter() }
            catch { usdTry = nil }
        }

        let concurrencyLimit = 8
        var iterator = list.makeIterator()

        var tmp: [PortfolioRow] = []
        tmp.reserveCapacity(list.count)

        await withTaskGroup(of: PortfolioRow?.self) { group in

            func add(_ a: Asset) {
                let usdTrySnap = usdTry

                group.addTask {
                    let yahoo = YahooFinanceService()

                    let fetchSymbol: String = {
                        if a.type == .metal {
                            return Self.yahooSymbolForMetal(original: a.symbol)
                        }
                        return a.symbol
                    }()

                    do {
                        // son + prev close için 5d yeterli
                        let candles = try await yahoo.fetchDailyCandles(symbol: fetchSymbol, range: "5d")
                        let last = candles.last?.close
                        let prev = candles.count >= 2 ? candles[candles.count - 2].close : nil

                        return Self.makeRow(asset: a, lastPrice: last, prevClose: prev, usdTry: usdTrySnap)
                    } catch {
                        return Self.makeRow(asset: a, lastPrice: nil, prevClose: nil, usdTry: usdTrySnap)
                    }
                }
            }

            for _ in 0..<min(concurrencyLimit, list.count) {
                if let a = iterator.next() { add(a) }
            }

            while let r = await group.next() {
                if let r { tmp.append(r) }
                if let next = iterator.next() { add(next) }
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
    }

    // MARK: - Merge (same symbol+type)

    nonisolated private static func mergeAssets(_ assets: [Asset]) -> [Asset] {
        struct Key: Hashable {
            let type: AssetType
            let symbol: String
        }

        var dict: [Key: [Asset]] = [:]
        for a in assets {
            let key = Key(type: a.type, symbol: a.symbol.uppercased())
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

    nonisolated private static func stableUUID(_ key: String) -> UUID {
        // hash stable değil; UTF8’den deterministik 16 byte üretelim
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
        let sym = asset.symbol.uppercased()
        let isBistTRY = sym.hasSuffix(".IS")
        let isFX = asset.type == .fx

        let lp = lastPrice
        let pc = prevClose

        let gramPerOunce = 31.1034768

        var valueTRY: Double? = nil
        var usedUSD = false

        var dayPnlTRY: Double? = nil
        var dayChangePct: Double? = nil

        if let lp {
            switch asset.type {
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

            default:
                if isFX || isBistTRY {
                    valueTRY = lp * asset.quantity

                    if let pc, pc > 0 {
                        dayPnlTRY = (lp - pc) * asset.quantity
                        dayChangePct = ((lp - pc) / pc) * 100.0
                    }
                } else {
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
        }

        var pnl: Double? = nil
        if let valueTRY, let avg = asset.avgCostTRY {
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

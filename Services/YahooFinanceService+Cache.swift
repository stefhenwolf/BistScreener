//
//  YahooFinanceService+Cache.swift
//  BistScreener
//
//  Created by Sedat Pala on 18.02.2026.
//

import Foundation

extension YahooFinanceService {

    /// Cache varsa hızlı göster. Yoksa 1y indirip son ~160 günü cache’e koy (120 iş günü + tolerans).
    func getOrFetchInitial(symbol: String) async throws -> [Candle] {
        let key = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        if let cached = await CandleCache.shared.load(symbol: key), !cached.isEmpty {
            return cached
        }

        let fetched = try await fetchDailyCandles(symbol: key, range: "1y")
        let trimmed = Array(fetched.suffix(160))
        await CandleCache.shared.save(symbol: key, candles: trimmed)
        return trimmed
    }
    
    /// Cache’i “son 10 gün” ile tazeler (merge by day). Offline/boş cevap olursa cache’i bozmaz.
    func refreshLatest(symbol: String) async throws -> [Candle] {
        let key = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        let cached = await CandleCache.shared.load(symbol: key) ?? []

        // ✅ TTL: cache varsa kısa sürede tekrar network'e gitme
        let ttl = ttlSeconds(for: key)
        if !cached.isEmpty, isWithinTTL(symbol: key, kind: "latest10d", ttl: ttl) {
            return cached
        }

        let fetched: [Candle]
        do {
            fetched = try await fetchDailyCandles(symbol: key, range: "10d")
        } catch {
            return cached
        }

        guard !fetched.isEmpty else { return cached }

        let merged = mergeByDay(old: cached, new: fetched)
        let trimmed = Array(merged.suffix(200))
        await CandleCache.shared.save(symbol: key, candles: trimmed)

        // ✅ stamp
        markRefreshed(symbol: key, kind: "latest10d")
        return trimmed
    }

    /// Portföy gibi yerlerde “son fiyat” için: önce cache, yoksa küçük range çek.
    func getOrFetchLastClose(symbol: String, range: String = "10d") async throws -> Double? {
        let key = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        let cached = await CandleCache.shared.load(symbol: key) ?? []
        if let last = cached.last?.close { return last }

        // ✅ TTL: cache boş olsa bile aynı anda/zırt pırt fetch yapma
        let ttl = ttlSeconds(for: key)
        if isWithinTTL(symbol: key, kind: "lastClose|\(range)", ttl: ttl) {
            return nil // elde veri yok, ama tekrar da deneme (UI nil'i yönetmeli)
        }

        let fetched: [Candle]
        do {
            fetched = try await fetchDailyCandles(symbol: key, range: range)
        } catch {
            return cached.last?.close
        }

        if !fetched.isEmpty {
            await CandleCache.shared.save(symbol: key, candles: Array(fetched.suffix(200)))
            markRefreshed(symbol: key, kind: "lastClose|\(range)")
        } else {
            // boş döndüyse de stamp koy ki spam olmasın
            markRefreshed(symbol: key, kind: "lastClose|\(range)")
        }

        return fetched.last?.close
    }

    // MARK: - Merge helper

    private func mergeByDay(old: [Candle], new: [Candle]) -> [Candle] {
        func dayKeyUTC(_ d: Date) -> Int {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(secondsFromGMT: 0)!   // ✅ gün kaymasını engeller
            let c = cal.dateComponents([.year, .month, .day], from: d)
            let y = c.year ?? 0
            let m = c.month ?? 0
            let dd = c.day ?? 0
            return (y * 10_000) + (m * 100) + dd
        }

        // Aynı gün 2 mum gelirse “new” öncelikli
        var dict: [Int: Candle] = [:]
        for c in old { dict[dayKeyUTC(c.date)] = c }
        for c in new { dict[dayKeyUTC(c.date)] = c }

        return dict.values.sorted { $0.date < $1.date }
    }
    // MARK: - Refresh TTL helpers

    private enum RefreshTTL {
        // Hisseler için
        static let equitySeconds: TimeInterval = 60          // 1 dk
        // FX/Commodity için (USDTRY=X, GC=F, SI=F vb.)
        static let macroSeconds: TimeInterval  = 300         // 5 dk
    }

    /// USDTRY=X, GC=F, SI=F gibi semboller için daha uzun TTL
    private func ttlSeconds(for symbol: String) -> TimeInterval {
        let s = symbol.uppercased()
        if s.contains("=X") || s.hasSuffix("=F") { return RefreshTTL.macroSeconds }
        return RefreshTTL.equitySeconds
    }

    private func refreshStampKey(symbol: String, kind: String) -> String {
        "yahoo_refresh_stamp|\(kind)|\(symbol.uppercased())"
    }

    private func isWithinTTL(symbol: String, kind: String, ttl: TimeInterval) -> Bool {
        let k = refreshStampKey(symbol: symbol, kind: kind)
        let last = UserDefaults.standard.double(forKey: k)
        if last == 0 { return false }
        return (Date().timeIntervalSince1970 - last) < ttl
    }

    private func markRefreshed(symbol: String, kind: String) {
        let k = refreshStampKey(symbol: symbol, kind: kind)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: k)
    }
}

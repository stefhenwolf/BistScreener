//
//  CandleRepository.swift
//  BistScreener
//
//  Created by Sedat Pala on 22.02.2026.
//

import Foundation

/// Tek gerçek kaynak: hem Scan hem Detail buradan candle alır.
/// Cache + fetch + normalize burada çözülür.
@MainActor
final class CandleRepository: ObservableObject {

    enum Range: String {
        case mo6 = "6mo"
        case y1  = "1y"
    }

    private let yahoo: YahooFinanceService

    /// Basit bellek cache (hız için)
    private var memCache: [String: [Candle]] = [:]

    /// Aynı anda aynı sembol/range istenirse tek network çalışsın (dedup)
    private var inflight: [String: Task<[Candle], Error>] = [:]

    /// Cache TTL (dakika)
    private let ttl: TimeInterval
    private var lastFetchAt: [String: Date] = [:]

    init(yahoo: YahooFinanceService, ttlMinutes: Double = 10) {
        self.yahoo = yahoo
        self.ttl = ttlMinutes * 60.0
    }

    /// Tek giriş noktası
    func getCandles(
        symbol: String,
        range: Range = .mo6,
        minCount: Int = 140,
        forceRefresh: Bool = false
    ) async throws -> [Candle] {

        let sym = symbol.normalizedBISTSymbol()

        // 1) Memory cache (TTL)
        if !forceRefresh,
           let cached = memCache[sym],
           cached.count >= min(20, minCount),
           let t = lastFetchAt[sym],
           Date().timeIntervalSince(t) < ttl {
            if needsLatestRefresh(lastDate: cached.last?.date) {
                if let refreshed = try? await refreshLatestIfNeeded(symbol: sym), !refreshed.isEmpty {
                    return refreshed
                }
            }
            return cached
        }

        // 2) Disk cache varsa onu da önce oku (mevcut CandleCache’ini kullan)
        if !forceRefresh,
           let disk = await CandleCache.shared.load(symbol: sym),
           !disk.isEmpty {
            // Disk'i mem'e koy
            memCache[sym] = disk
            lastFetchAt[sym] = Date()

            // Eğer disk yeterliyse direkt dön
            if disk.count >= min(20, minCount) {
                if needsLatestRefresh(lastDate: disk.last?.date) {
                    if let refreshed = try? await refreshLatestIfNeeded(symbol: sym), !refreshed.isEmpty {
                        return refreshed
                    }
                }
                return disk
            }
            // yetmiyorsa fetch'e düş
        }

        // 3) Network fetch (tek yer) + inflight dedup
        let key = "\(sym)|\(range.rawValue)"
        if let t = inflight[key] {
            let fetched = try await t.value
            let trimmed = Array(fetched.suffix(max(minCount, 140)))
            memCache[sym] = trimmed
            lastFetchAt[sym] = Date()
            await CandleCache.shared.save(symbol: sym, candles: trimmed)
            return trimmed
        }

        let task = Task<[Candle], Error> {
            try await self.yahoo.fetchDailyCandles(symbol: sym, range: range.rawValue)
        }
        inflight[key] = task

        let fetched: [Candle]
        do {
            fetched = try await task.value
        } catch {
            inflight[key] = nil
            // ✅ Network geçici düşebilir (500/429 vs). Disk cache varsa onu kullan.
            if let disk = await CandleCache.shared.load(symbol: sym), !disk.isEmpty {
                memCache[sym] = disk
                lastFetchAt[sym] = Date()
                return disk
            }
            throw error
        }
        inflight[key] = nil

        // 4) Normalize / trim
        // (Sen taramada 140 kullanıyorsun. Burada da standartlaştırıyoruz.)
        let trimmed = Array(fetched.suffix(max(minCount, 140)))

        // 5) Cache write-through
        memCache[sym] = trimmed
        lastFetchAt[sym] = Date()
        await CandleCache.shared.save(symbol: sym, candles: trimmed)

        return trimmed
    }

    /// Cache’i “son günleri” ile tazeler (merge by day). UI’yi bloklamamak için genelde background’da çağır.
    /// - Not: Bu fonksiyon *cache varsa* çalışır; yoksa network ile baştan çekmeye kalkmaz.
    func refreshLatestIfNeeded(symbol: String, lookbackDays: String = "10d") async throws -> [Candle] {
        let sym = symbol.normalizedBISTSymbol()

        let cached = await CandleCache.shared.load(symbol: sym) ?? []
        guard !cached.isEmpty else { return [] }

        // Son candle bugünden çok eski değilse (örn. aynı gün) hiç dokunma.
        if let last = cached.last?.date {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(secondsFromGMT: 0)!
            let lastDay = cal.startOfDay(for: last)
            let todayDay = cal.startOfDay(for: Date())
            if lastDay >= todayDay { return cached }
        }

        // Küçük range çek, merge et (inflight dedup)
        let key = "\(sym)|\(lookbackDays)"
        let fetched: [Candle]
        if let t = inflight[key] {
            fetched = try await t.value
        } else {
            let task = Task<[Candle], Error> {
                try await self.yahoo.fetchDailyCandles(symbol: sym, range: lookbackDays)
            }
            inflight[key] = task
            do {
                fetched = try await task.value
            } catch {
                inflight[key] = nil
                // ✅ Güncelleme başarısızsa cache'i bozma; mevcut cache ile devam et.
                return cached
            }
            inflight[key] = nil
        }
        guard !fetched.isEmpty else { return cached }

        let merged = mergeByDay(old: cached, new: fetched)
        let trimmed = Array(merged.suffix(200))
        memCache[sym] = trimmed
        lastFetchAt[sym] = Date()
        await CandleCache.shared.save(symbol: sym, candles: trimmed)
        return trimmed
    }

    func clearMemoryCache() {
        memCache.removeAll()
        lastFetchAt.removeAll()
    }

    // MARK: - Merge helper

    private func mergeByDay(old: [Candle], new: [Candle]) -> [Candle] {
        func dayKeyUTC(_ d: Date) -> Int {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(secondsFromGMT: 0)!
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

    /// Günlük veride son mum bugünden gerideyse kısa güncelleme zorlanır.
    /// BIST için gün kapanışı yerel takvimde takip edilir.
    private func needsLatestRefresh(lastDate: Date?) -> Bool {
        guard let lastDate else { return true }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Istanbul") ?? .current
        let lastDay = cal.startOfDay(for: lastDate)
        let todayDay = cal.startOfDay(for: Date())
        return lastDay < todayDay
    }
}

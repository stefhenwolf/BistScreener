import Foundation

// MARK: - Tomorrow BUY-only (EOD -> Next Day) Types

enum TomorrowPreset: String, Codable, CaseIterable {
    case relaxed
    case normal
    case strict

    var title: String {
        switch self {
        case .relaxed: return "Relaxed"
        case .normal:  return "Normal"
        case .strict:  return "Strict"
        }
    }

    /// BUY minimum total threshold
    var minBuyTotal: Int {
        switch self {
        case .relaxed: return 30  // Gevşek – daha fazla aday gösterir
        case .normal:  return 50  // Dengeli
        case .strict:  return 65  // Sıkı – yalnızca en güçlü sinyaller
        }
    }

    /// Strict modda Tier C kapalı
    var allowsTierC: Bool { self != .strict }
}

enum LiquidityTier: String, Codable, CaseIterable {
    case a, b, c, none

    var label: String {
        switch self {
        case .a: return "Tier A"
        case .b: return "Tier B"
        case .c: return "Tier C"
        case .none: return "—"
        }
    }
}

/// BUY-only çıktı
struct TomorrowSignalScore: Codable, Equatable, Hashable {
    let isBuy: Bool          // true (BUY ise üretilir)
    let total: Int           // 0..100 Tomorrow Bias Score
    let quality: String      // "A+" "A" "B" "C" "D"
    let signal: TradeSignal  // .buy (tek aksiyon)
    let tier: LiquidityTier
    let reasons: [String]    // max 3 chip text
    let breakdown: TomorrowBreakdown
}

struct TomorrowBreakdown: Codable, Equatable, Hashable {

    // Tier / Liquidity
    var avgValue20: Double = 0
    var valueToday: Double = 0
    var valueMultiple: Double = 0

    // Close strength
    var clv: Double = 0

    // Breakout proximity
    var lookback: Int = 20
    var highestClose: Double = 0
    var highestHigh: Double = 0
    var breakoutBufferPct: Double = 0
    var didBreakout: Bool = false

    // Trend
    var ema20: Double = 0
    var ema50: Double = 0
    var trendOK: Bool = false

    // Compression / Expansion
    var trToday: Double = 0
    var trMedian20: Double = 0
    var trSpikeMultiple: Double = 0
    var expansionOK: Bool = false

    var compressionOK: Bool = false
    var compressionFlagsHit: Int = 0   // 0..3

    // Pre-breakout specific
    var proximityPct: Double = 0       // How close to breakout level (0..1)
    var volumeTrend: Double = 0        // Volume trend (recent vs older)
    var rangeCompression: Double = 0   // Range compression ratio

    // For debugging / UI
    var notes: [String] = []
}

// MARK: - Tomorrow BUY-only Scorer (PRE-BREAKOUT Strategy)

enum SignalScorer {

    enum Reject: String {
        case notEnoughData
        case todayChangeTooHigh
        case proximityOutOfRange
        case valueMultipleLow
        case volumeTrendLow
        case clvLow
        case rangeNotCompressed
        case scoreBelowMin
        case refLevelInvalid
    }

    static func debugScoreWithConfig(candles: [Candle], config: StrategyConfig) -> (result: TomorrowSignalScore?, reject: Reject?, notes: [String]) {
        var notes: [String] = []

        guard candles.count >= max(config.lookbackDays + 15, 60) else {
            return (nil, .notEnoughData, ["count=\(candles.count)"])
        }

        let r = scoreWithConfig(candles: candles, config: config)
        if r != nil { return (r, nil, ["OK"]) }

        return (nil, .scoreBelowMin, ["returned nil"])
    }

    // MARK: - Tier thresholds (AvgValue20 in TL)

    private static let tierA: Double = 50_000_000
    private static let tierB: Double = 15_000_000
    private static let tierC: Double = 5_000_000

    // MARK: - Core entry (preset-based, backwards compatible)

    static func scoreTomorrowBuyOnly(
        candles: [Candle],
        preset: TomorrowPreset,
        lookback: Int = 20
    ) -> TomorrowSignalScore? {
        // Preset → StrategyConfig dönüşümü
        var cfg = StrategyConfig.load()
        cfg.lookbackDays = lookback
        switch preset {
        case .relaxed:
            cfg.minProximity = 0.90
            cfg.maxProximity = 1.02
            cfg.minValueMultiple = 0.5
            cfg.minVolumeTrend = 0.0       // filtre kapalı
            cfg.minCLV = 0.20
            cfg.maxRangeCompression = 2.0
            cfg.maxTodayChangePct = 8.0
            cfg.minScore = preset.minBuyTotal
        case .normal:
            break // cfg'den oku (kullanıcı ayarları)
        case .strict:
            cfg.minProximity = 0.97
            cfg.maxProximity = 1.002
            cfg.minValueMultiple = 1.2
            cfg.minVolumeTrend = 1.1
            cfg.minCLV = 0.70
            cfg.maxRangeCompression = 1.1
            cfg.maxTodayChangePct = 3.0
            cfg.minScore = preset.minBuyTotal
        }
        return scoreWithConfig(candles: candles, config: cfg)
    }

    // MARK: - Core entry (config-based)

    /// PRE-BREAKOUT: StrategyConfig ile çalışan ana fonksiyon
    static func scoreWithConfig(
        candles: [Candle],
        config: StrategyConfig
    ) -> TomorrowSignalScore? {

        let lookback = config.lookbackDays
        guard candles.count >= max(lookback + 5, 55) else { return nil }
        guard let last = candles.last else { return nil }

        let closes = candles.map(\.close)
        let highs  = candles.map(\.high)
        let volumes = candles.map { Double($0.volume) }

        // ---------- Liquidity (AvgValue20)
        guard let avgValue20 = ValueSeries.averageValue(closes: closes, volumes: volumes, period: 20) else { return nil }
        var tier = liquidityTier(avgValue20: avgValue20)
        if tier == .none { tier = .b }

        // ---------- Value (today / avg20)
        let valueToday = last.close * Double(last.volume)
        let valueMultiple = (avgValue20 > 0) ? (valueToday / avgValue20) : 0
        guard valueMultiple >= config.minValueMultiple else { return nil }

        // ---------- CLV
        guard let clv = CLV.value(candle: last) else { return nil }
        guard clv >= config.minCLV else { return nil }

        // ---------- Trend filter (EMA)
        let ema20 = EMA.lastValue(values: closes, period: 20) ?? 0
        let ema50 = EMA.lastValue(values: closes, period: 50) ?? 0
        let trendOK = last.close >= ema50

        // ---------- Proximity (son mum hariç tutularak hesaplanır)
        let closesExToday = Array(closes.dropLast())
        let highsExToday  = Array(highs.dropLast())
        let highestClose20 = BreakoutLevels.highestClose(closes: closesExToday, lookback: lookback) ?? 0
        let highestHigh20  = BreakoutLevels.highestHigh(highs: highsExToday, lookback: lookback) ?? 0
        let refLevel = tier == .c ? highestHigh20 : highestClose20
        guard refLevel > 0 else { return nil }

        let proximity = last.close / refLevel
        guard proximity >= config.minProximity else { return nil }
        guard proximity <= config.maxProximity else { return nil }

        let didBreakout = proximity > 1.0

        // ---------- Volume Trend
        let recentVols = Array(volumes.suffix(5))
        let olderVols  = Array(volumes.dropLast(5).suffix(10))
        let avgRecentVol = recentVols.isEmpty ? 0 : recentVols.reduce(0, +) / Double(recentVols.count)
        let avgOlderVol  = olderVols.isEmpty ? 1 : olderVols.reduce(0, +) / Double(olderVols.count)
        let volumeTrend = avgOlderVol > 0 ? (avgRecentVol / avgOlderVol) : 1.0

        if config.minVolumeTrend > 0 {
            guard volumeTrend >= config.minVolumeTrend else { return nil }
        }

        // ---------- Range Compression
        let recentRanges = candles.suffix(5).map { $0.high - $0.low }
        let olderRanges  = candles.dropLast(5).suffix(10).map { $0.high - $0.low }
        let avgRecentRange = recentRanges.isEmpty ? 0 : recentRanges.reduce(0, +) / Double(recentRanges.count)
        let avgOlderRange  = olderRanges.isEmpty ? 1 : olderRanges.reduce(0, +) / Double(olderRanges.count)
        let rangeCompression = avgOlderRange > 0 ? (avgRecentRange / avgOlderRange) : 1.0

        guard rangeCompression <= config.maxRangeCompression else { return nil }

        // ---------- Today Change
        let prevClose = candles.count >= 2 ? candles[candles.count - 2].close : last.close
        let todayChangePct = prevClose > 0 ? ((last.close - prevClose) / prevClose) * 100 : 0
        guard todayChangePct <= config.maxTodayChangePct else { return nil }

        // ---------- TR spike
        let trSeries = TrueRange.calculate(candles: candles)
        let trToday = trSeries.last ?? 0
        let trMedian20 = Rolling.medianLast(trSeries, window: 20) ?? 1
        let trSpikeMultiple = trMedian20 > 0 ? (trToday / trMedian20) : 1.0

        // ---------- Compression check
        let compression = compressionOK(candles: candles, window: 8)

        // ✅ SCORE BUILD (configurable weights)
        let proximityScore: Double = {
            let range = config.maxProximity - config.minProximity
            guard range > 0 else { return proximity >= config.minProximity ? 1.0 : 0 }
            // minProximity → 0, maxProximity → 1 (lineer)
            let x = (proximity - config.minProximity) / range
            return min(1, max(0, x))
        }()

        let clvScore = scoreCLV(clv, minCLV: config.minCLV)

        let volumeTrendScore: Double = {
            if volumeTrend <= 0.8 { return 0 }
            let x = (volumeTrend - 0.8) / 1.2
            return min(1, max(0, x))
        }()

        let compressionScore: Double = {
            if rangeCompression >= config.maxRangeCompression { return 0 }
            let x = (config.maxRangeCompression - rangeCompression) / max(config.maxRangeCompression - 0.5, 0.1)
            return min(1, max(0, x))
        }()

        // Ağırlıkları normalize et (toplam 100'e oranla)
        let wTotal = config.weightProximity + config.weightVolumeTrend + config.weightCLV + config.weightCompression
        let normalizer = wTotal > 0 ? (100.0 / wTotal) : 1.0

        // ⚠️ Skor hesaplaması: her bileşen 0..1, ağırlıklar toplamı ~100
        // Formül: (score_i * weight_i) toplamı * normalizer → 0..100
        let total = min(100, max(0,
            Int(round(
                (proximityScore    * config.weightProximity +
                 volumeTrendScore  * config.weightVolumeTrend +
                 clvScore          * config.weightCLV +
                 compressionScore  * config.weightCompression) * normalizer
            ))
        ))

        guard total >= config.minScore else { return nil }

        let quality = qualityBand(total: total, config: config)

        // Reasons (max 3)
        var reasons: [String] = []
        if proximityScore >= 0.7 { reasons.append("Kırılım Yakın") }
        if volumeTrendScore >= 0.5 { reasons.append("Hacim Artışı") }
        if compressionScore >= 0.5 { reasons.append("Sıkışma") }
        if clvScore >= 0.7 { reasons.append("Güçlü Kapanış") }
        if trendOK { reasons.append("Trend Yukarı") }
        reasons = Array(reasons.prefix(3))
        if reasons.isEmpty { reasons.append("Pre-Breakout") }

        var bd = TomorrowBreakdown()
        bd.avgValue20 = avgValue20
        bd.valueToday = valueToday
        bd.valueMultiple = valueMultiple

        bd.clv = clv

        bd.lookback = lookback
        bd.highestClose = highestClose20
        bd.highestHigh = highestHigh20
        bd.breakoutBufferPct = 0
        bd.didBreakout = didBreakout

        bd.ema20 = ema20
        bd.ema50 = ema50
        bd.trendOK = trendOK

        bd.trToday = trToday
        bd.trMedian20 = trMedian20
        bd.trSpikeMultiple = trSpikeMultiple
        bd.expansionOK = false

        bd.compressionOK = compression.ok
        bd.compressionFlagsHit = compression.flagsHit

        bd.proximityPct = proximity
        bd.volumeTrend = volumeTrend
        bd.rangeCompression = rangeCompression

        bd.notes = [
            "\(tier.label)",
            String(format: "Kırılıma %.1f%%", (proximity - 1.0) * 100),
            String(format: "Hacim x%.1f", volumeTrend),
            String(format: "Sıkışma %.2f", rangeCompression),
            String(format: "Bugün %+.1f%%", todayChangePct)
        ]

        return TomorrowSignalScore(
            isBuy: true,
            total: total,
            quality: quality,
            signal: .buy,
            tier: tier,
            reasons: reasons,
            breakdown: bd
        )
    }

    // MARK: - Helpers

    private static func liquidityTier(avgValue20: Double) -> LiquidityTier {
        if avgValue20 >= tierA { return .a }
        if avgValue20 >= tierB { return .b }
        if avgValue20 >= tierC { return .c }
        return .none
    }

    private static func qualityBand(total: Int, config: StrategyConfig) -> String {
        switch total {
        case config.qualityAPlus...: return "A+"
        case config.qualityA...:     return "A"
        case config.qualityB...:     return "B"
        case config.qualityC...:     return "C"
        default:                     return "D"
        }
    }

    /// Normalize 0..1 score
    private static func scoreCLV(_ clv: Double, minCLV: Double) -> Double {
        if clv <= minCLV { return 0 }
        let denom = max(1e-9, 1.0 - minCLV)
        let x = (clv - minCLV) / denom
        return min(1, max(0, x))
    }

    private static func compressionOK(candles: [Candle], window: Int, preset: TomorrowPreset = .normal) -> (ok: Bool, flagsHit: Int) {
        guard window > 0, candles.count >= window + 20 else { return (false, 0) }

        // 1) ATR down: ATR_now < ATR_{window}barsAgo
        let atrSeries = ATR.calculate(candles: candles, period: 14).compactMap { $0 }
        let atrNow = atrSeries.last ?? 0
        let atrAgo = atrSeries.count > window ? atrSeries[atrSeries.count - 1 - window] : atrNow
        let flagATRDown = atrNow > 0 && atrNow < atrAgo

        // 2) median range down: median(range last window) < median(range prev window)
        let ranges = candles.map { $0.high - $0.low }
        let lastRanges = Array(ranges.suffix(window))
        let prevRanges = Array(ranges.dropLast(window).suffix(window))
        let medLast = Stats.median(lastRanges) ?? 0
        let medPrev = Stats.median(prevRanges) ?? medLast
        let flagRangeDown = medLast > 0 && medLast < medPrev

        // 3) overlap proxy: median body small vs range (body/range median < threshold)
        let bodyRatios: [Double] = candles.suffix(window).map { c in
            let r = max(c.high - c.low, 1e-9)
            return abs(c.close - c.open) / r
        }
        let medBody = Stats.median(bodyRatios) ?? 1.0
        let flagBodySmall = medBody < 0.45

        let flags = [flagATRDown, flagRangeDown, flagBodySmall].filter { $0 }.count

        let minFlags = preset == .relaxed ? 1 : 2
        return (flags >= minFlags, flags)
    }
}

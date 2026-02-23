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
        case .relaxed: return 45  // Çok gevşek (test için)
        case .normal:  return 55  // Normal
        case .strict:  return 65  // Strict
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

    // Breakout
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

    // For debugging / UI
    var notes: [String] = []
}

// MARK: - Tomorrow BUY-only Scorer

enum SignalScorer {

    // MARK: - Tier thresholds (AvgValue20 in TL)

    private static let tierA: Double = 50_000_000
    private static let tierB: Double = 15_000_000
    private static let tierC: Double = 5_000_000

    // MARK: - Core entry

    /// BUY-only: BUY değilse nil döner.
    static func scoreTomorrowBuyOnly(
        candles: [Candle],
        preset: TomorrowPreset,
        lookback: Int = 20
    ) -> TomorrowSignalScore? {

        guard candles.count >= max(lookback + 5, 55) else { return nil } // EMA50 vs için güvenli buffer
        guard let last = candles.last else { return nil }

        let closes = candles.map(\.close)
        let highs  = candles.map(\.high)
        let lows   = candles.map(\.low)
        let volumes = candles.map { Double($0.volume) }

        // ---------- Liquidity (AvgValue20)
        guard let avgValue20 = ValueSeries.averageValue(closes: closes, volumes: volumes, period: 20) else { return nil }
        let tier = liquidityTier(avgValue20: avgValue20)

        if tier == .none { return nil }
        if tier == .c, preset.allowsTierC == false { return nil }

        // ---------- Value spike (today / avg20)
        let valueToday = last.close * Double(last.volume)
        let valueMultiple = (avgValue20 > 0) ? (valueToday / avgValue20) : 0

        // Tier-based value multiple thresholds (relaxed)
        let minValueMultiple: Double = {
            switch tier {
            case .a: return preset == .strict ? 1.5 : 1.2
            case .b: return preset == .strict ? 1.6 : 1.4
            case .c: return preset == .relaxed ? 1.5 : 1.8
            case .none: return .infinity
            }
        }()

        guard valueMultiple >= minValueMultiple else { return nil }

        // ---------- CLV (close location value)
        guard let clv = CLV.value(candle: last) else { return nil }
        let minCLV: Double = {
            switch tier {
            case .a, .b: return preset == .relaxed ? 0.70 : 0.75
            case .c:     return preset == .relaxed ? 0.75 : 0.82
            case .none:  return 1.0
            }
        }()
        guard clv >= minCLV else { return nil }

        // ---------- Trend filter (EMA)
        let ema20 = EMA.lastValue(values: closes, period: 20) ?? 0
        let ema50 = EMA.lastValue(values: closes, period: 50) ?? 0

        let trendOK: Bool = {
            switch tier {
            case .a, .b:
                return last.close >= ema20
            case .c:
                // sığda daha strict
                return last.close >= ema50
            case .none:
                return false
            }
        }()
        guard trendOK else { return nil }

        // ---------- Breakout (tier-based)
        let highestClose = BreakoutLevels.highestClose(closes: closes, lookback: lookback) ?? 0
        let highestHigh  = BreakoutLevels.highestHigh(highs: highs, lookback: lookback) ?? 0

        let bufferPct: Double = {
            switch tier {
            case .a, .b:
                return preset == .relaxed ? 0.0 : 0.003   // %0.3
            case .c:
                return preset == .relaxed ? 0.003 : 0.006 // %0.6
            case .none:
                return 0
            }
        }()

        let didBreakout: Bool = {
            switch tier {
            case .a, .b:
                let level = highestClose * (1 + bufferPct)
                return last.close > level
            case .c:
                let level = highestHigh * (1 + bufferPct)
                return last.close > level
            case .none:
                return false
            }
        }()
        guard didBreakout else { return nil }

        // ---------- Compression (last 8 bars) - skip for relaxed preset
        let compression: (ok: Bool, flagsHit: Int) = {
            if preset == .relaxed { return (true, 0) }  // Skip compression for relaxed
            return compressionOK(candles: candles, window: 8, preset: preset)
        }()
        if preset != .relaxed { guard compression.ok else { return nil } }

        // ---------- Expansion (TR spike)
        let trSeries = TrueRange.calculate(candles: candles)
        guard let trToday = trSeries.last else { return nil }
        guard let trMedian20 = Rolling.medianLast(trSeries, window: 20) else { return nil }
        guard trMedian20 > 0 else { return nil }

        let trSpikeMultiple = trToday / trMedian20
        let minTRSpike: Double = {
            switch tier {
            case .a, .b: return preset == .relaxed ? 1.0 : 1.15
            case .c:     return preset == .relaxed ? 1.1 : 1.5
            case .none:  return .infinity
            }
        }()
        guard trSpikeMultiple >= minTRSpike else { return nil }

        // ✅ burada artık BUY olmuş sayılır

        // ---------- Score build (0..100)
        let breakoutScore = scoreBreakout(lastClose: last.close, level: (tier == .c ? highestHigh : highestClose))
        let clvScore      = scoreCLV(clv)
        let valueScore    = scoreMultiple(valueMultiple, cap: 3.0)
        let compScore     = scoreCompression(flagsHit: compression.flagsHit) // 0..3

        // Weights: Breakout 30, CLV 25, Value 25, Compression 20
        let total = min(100, max(0,
            Int(round(
                breakoutScore * 30 +
                clvScore      * 25 +
                valueScore    * 25 +
                compScore     * 20
            ))
        ))

        // BUY threshold (preset)
        guard total >= preset.minBuyTotal else { return nil }

        let quality = qualityBand(total: total)

        // Reasons (max 3)
        var reasons: [String] = []
        reasons.append("Breakout")
        if clv >= 0.85 { reasons.append("High CLV") }
        reasons.append(valueMultiple >= 2.0 ? "Value Spike" : "Value Up")
        if reasons.count > 3 { reasons = Array(reasons.prefix(3)) }

        var bd = TomorrowBreakdown()
        bd.avgValue20 = avgValue20
        bd.valueToday = valueToday
        bd.valueMultiple = valueMultiple

        bd.clv = clv

        bd.lookback = lookback
        bd.highestClose = highestClose
        bd.highestHigh = highestHigh
        bd.breakoutBufferPct = bufferPct
        bd.didBreakout = didBreakout

        bd.ema20 = ema20
        bd.ema50 = ema50
        bd.trendOK = trendOK

        bd.trToday = trToday
        bd.trMedian20 = trMedian20
        bd.trSpikeMultiple = trSpikeMultiple
        bd.expansionOK = true

        bd.compressionOK = true
        bd.compressionFlagsHit = compression.flagsHit

        // küçük notlar (debug için)
        bd.notes = [
            "\(tier.label)",
            String(format: "CLV %.2f", clv),
            String(format: "Value x%.2f", valueMultiple),
            String(format: "TR x%.2f", trSpikeMultiple)
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

    private static func qualityBand(total: Int) -> String {
        switch total {
        case 90...: return "A+"
        case 82...: return "A"
        case 74...: return "B"
        case 66...: return "C"
        default:    return "D"
        }
    }

    /// Normalize 0..1 score
    private static func scoreCLV(_ clv: Double) -> Double {
        // 0.70 -> 0, 1.0 -> 1
        let x = (clv - 0.70) / 0.30
        return min(1, max(0, x))
    }

    /// Multiple normalize 0..1
    private static func scoreMultiple(_ m: Double, cap: Double) -> Double {
        // 1.0 -> 0, cap -> 1
        let x = (m - 1.0) / (cap - 1.0)
        return min(1, max(0, x))
    }

    /// Breakout “strength”: close/level ratio
    private static func scoreBreakout(lastClose: Double, level: Double) -> Double {
        guard level > 0 else { return 0 }
        let pct = (lastClose / level) - 1.0  // 0.0..?
        // 0% -> 0, 3% -> 1
        let x = pct / 0.03
        return min(1, max(0, x))
    }

    private static func scoreCompression(flagsHit: Int) -> Double {
        // 0..3 -> 0..1
        return min(1, max(0, Double(flagsHit) / 3.0))
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

        // Require fewer flags for relaxed preset
        let minFlags = preset == .relaxed ? 1 : 2
        return (flags >= minFlags, flags)
    }
}

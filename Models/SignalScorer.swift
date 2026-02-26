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

    /// BUY minimum total threshold (non-linear skorlama ile kalibre edildi)
    var minBuyTotal: Int {
        switch self {
        case .relaxed: return 40   // ~%30-50 geçer (8-15 / 30 hisse)
        case .normal:  return 52   // ~%10-25 geçer (3-8  / 30 hisse)
        case .strict:  return 65   // ~%0-10  geçer (0-3  / 30 hisse)
        }
    }

    /// Preset-specific lookback (kısa lookback = daha yakın zirve, daha fazla aday)
    var lookbackDays: Int {
        switch self {
        case .relaxed: return 15
        case .normal:  return 20
        case .strict:  return 25
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

// MARK: - Tomorrow BUY-only Scorer (PRE-BREAKOUT Strategy v2)
// ═══════════════════════════════════════════════════════════
// v2 Farkları:
//   1. Tüm presetler softMode kullanır (hard guard yok)
//   2. Non-linear scoring: Gaussian proximity, Sigmoid CLV
//   3. Today change ceza olarak uygulanır (guard değil)
//   4. Ağırlıklar: proximity=35, vol=20, clv=20, comp=15, trend=10
//   5. Kalibre minScore: relaxed=40, normal=52, strict=65
// ═══════════════════════════════════════════════════════════

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

    // MARK: - Interpolation helper

    /// Lineer interpolasyon: a → b arası, t ∈ [0,1]
    private static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * max(0, min(1, t))
    }

    // MARK: - ═══════════════════════════════════════
    // NON-LINEAR SCORING FUNCTIONS (v2)
    // ═══════════════════════════════════════════════

    /// Proximity: Asimetrik Gaussian bell curve (v3 — daha sıkı, kırılıma yakın)
    /// Sweet spot: 0.97-1.01 (kırılıma %0-3 mesafe)
    /// Peak: 0.99 (kırılımın %1 altı = en ideal birikim noktası)
    /// Sol sigma: 0.040 → 0.95'te skor 0.54, 0.93'te skor 0.22
    /// Sağ sigma: 0.025 → 1.015'te skor 0.61, 1.04'te skor 0.08
    /// Daha seçici: sadece kırılıma gerçekten yakın olanlar yüksek skor alır
    private static func scoreProximityNonLinear(_ p: Double) -> Double {
        // Aşırı uçlarda sıfır
        if p < 0.88 || p > 1.08 { return 0 }

        let center = 0.99
        // Sol: sigma=0.040 → yaklaşanlar toleranslı ama seçici
        // Sağ: sigma=0.025 → kırmış hisseler hızla puan kaybeder
        let sigma = p < center ? 0.040 : 0.025
        return exp(-pow((p - center) / sigma, 2))
    }

    /// CLV: Sigmoid curve
    /// 0.0 (en düşükte kapanış) → 0.02 skor
    /// 0.5 (ortada kapanış) → 0.50 skor
    /// 0.8 (güçlü kapanış) → 0.92 skor
    /// 1.0 (en yüksekte kapanış) → 0.98 skor
    private static func scoreCLVNonLinear(_ clv: Double) -> Double {
        // Sigmoid: 1 / (1 + e^(-k*(x-0.5)))
        // k=8 → yeterince dik ama smooth
        return 1.0 / (1.0 + exp(-8.0 * (clv - 0.5)))
    }

    /// Volume Trend: Parçalı (piecewise) fonksiyon
    /// Ideal: 1.2-2.5x (organik hacim artışı = akıllı para birikimi)
    /// Düşük (<0.7): ilgi azalmış → düşük skor
    /// Çok yüksek (>3.0): haber/manipülasyon riski → skor düşer
    private static func scoreVolumeTrendNonLinear(_ vt: Double) -> Double {
        if vt < 0.3 { return 0 }
        if vt < 0.7 { return lerp(0, 0.20, (vt - 0.3) / 0.4) }
        if vt < 1.0 { return lerp(0.20, 0.50, (vt - 0.7) / 0.3) }
        if vt < 1.5 { return lerp(0.50, 0.85, (vt - 1.0) / 0.5) }
        if vt < 2.5 { return lerp(0.85, 1.0, (vt - 1.5) / 1.0) }
        if vt < 4.0 { return lerp(1.0, 0.60, (vt - 2.5) / 1.5) }
        return 0.50  // Aşırı hacim, belirsiz sinyal
    }

    /// Range Compression: Ters orantı (düşük = daha sıkışmış = daha iyi)
    /// <0.5: Çok sıkışmış → patlama enerjisi birikmiş → 1.0
    /// 0.5-0.8: İyi sıkışma → 0.70-0.90
    /// 0.8-1.0: Hafif sıkışma → 0.45-0.70
    /// 1.0-1.5: Genişleme → 0.15-0.45 (breakout/breakdown olabilir)
    /// >1.5: Güçlü genişleme → 0-0.15 (hareket başlamış)
    private static func scoreCompressionNonLinear(_ rc: Double) -> Double {
        if rc < 0.3 { return 1.0 }
        if rc < 0.5 { return lerp(1.0, 0.92, (rc - 0.3) / 0.2) }
        if rc < 0.8 { return lerp(0.92, 0.70, (rc - 0.5) / 0.3) }
        if rc < 1.0 { return lerp(0.70, 0.45, (rc - 0.8) / 0.2) }
        if rc < 1.3 { return lerp(0.45, 0.25, (rc - 1.0) / 0.3) }
        if rc < 1.8 { return lerp(0.25, 0.10, (rc - 1.3) / 0.5) }
        if rc < 2.5 { return lerp(0.10, 0.0, (rc - 1.8) / 0.7) }
        return 0
    }

    /// Trend: EMA alignment skoru
    /// Tam hizalama (close > EMA20 > EMA50) → 1.0 (güçlü boğa trendi)
    /// EMA50 üzeri → 0.60 (trend yukarı ama EMA cross belirsiz)
    /// EMA50'ye yakın (%2 içinde) → 0.35 (nötr, destek testi olabilir)
    /// EMA50 altı → 0.10 (ayı bölgesi, kırılım düşük olasılık)
    private static func scoreTrend(lastClose: Double, ema20: Double, ema50: Double) -> Double {
        // Tam bullish alignment: close > EMA20 > EMA50
        if lastClose > ema20 && ema20 > ema50 { return 1.0 }
        // Close EMA50 üzerinde ama EMA'lar cross etmemiş
        if lastClose > ema50 { return 0.60 }
        // EMA50'ye çok yakın (destek bölgesi, bounce potansiyeli)
        if ema50 > 0 && lastClose > ema50 * 0.98 { return 0.35 }
        // EMA50 altı - ayı trendi
        return 0.10
    }

    /// Momentum Adjustment: Küçük pozitif hareket = alıcı momentum (bonus)
    /// +0.5% ile +3% arası: Gaussian bonus (peak ~+5 puan @ %1.5)
    /// +5% üzeri: Ceza (uzamış, giriş riskli)
    /// -4% altı: Ceza (zayıflık sinyali)
    /// Net etki: -20 ile +5 arası puan
    private static func momentumAdjustment(_ changePct: Double) -> Double {
        // ── BONUS: Küçük pozitif hareket → alıcı momentum ──
        if changePct >= 0.3 && changePct <= 4.0 {
            // Gaussian bonus: peak ~1.5% → +5 puan
            let center = 1.5
            let sigma = 1.2
            return 5.0 * exp(-pow((changePct - center) / sigma, 2))
        }

        // ── PENALTY: Aşırı yükseliş → uzamış, giriş riski ──
        if changePct > 5.0 {
            return -min(20.0, (changePct - 5.0) * 4.0)
        }

        // ── PENALTY: Sert düşüş → zayıflık sinyali ──
        if changePct < -4.0 {
            return -min(12.0, (abs(changePct) - 4.0) * 2.5)
        }

        return 0
    }

    /// Setup Synergy:
    /// Kırılıma yakın + kontrollü hacim artışı + sıkışma + güçlü kapanış
    /// birlikte geldiğinde küçük bonus ver.
    private static func setupSynergyAdjustment(
        proximity: Double,
        volumeTrend: Double,
        rangeCompression: Double,
        clv: Double
    ) -> Double {
        var bonus: Double = 0
        if proximity >= 0.965 && proximity <= 1.01 { bonus += 1.5 }
        if volumeTrend >= 1.1 && volumeTrend <= 2.6 { bonus += 1.0 }
        if rangeCompression <= 0.95 { bonus += 1.0 }
        if clv >= 0.65 { bonus += 1.0 }
        return min(4.0, bonus)
    }

    /// Volatilite anomalisi varsa daha seçici ol.
    private static func dynamicMinScoreDelta(
        trSpikeMultiple: Double,
        liquidityTier: LiquidityTier
    ) -> Int {
        var delta = 0

        if trSpikeMultiple >= 3.2 {
            delta += 8
        } else if trSpikeMultiple >= 2.4 {
            delta += 5
        } else if trSpikeMultiple >= 1.9 {
            delta += 2
        }

        switch liquidityTier {
        case .a:
            break
        case .b:
            delta += 1
        case .c:
            delta += 3
        case .none:
            delta += 6
        }

        return delta
    }

    // MARK: - Debug

    /// Her koşulu ayrı ayrı kontrol eder, neden reddedildiğini detaylı döner
    static func debugScoreWithConfig(candles: [Candle], config: StrategyConfig) -> (result: TomorrowSignalScore?, reject: Reject?, notes: [String]) {
        var notes: [String] = []
        let lookback = config.lookbackDays

        guard candles.count >= max(lookback + 5, 40) else {
            return (nil, .notEnoughData, ["count=\(candles.count), need=\(max(lookback+5,40))"])
        }
        guard let last = candles.last else {
            return (nil, .notEnoughData, ["no last candle"])
        }
        notes.append("candles=\(candles.count)")

        let closes = candles.map(\.close)
        let highs = candles.map(\.high)
        let volumes = candles.map { Double($0.volume) }

        // Value
        let avgValue20 = ValueSeries.averageValue(closes: closes, volumes: volumes, period: 20) ?? 0
        let valueToday = last.close * Double(last.volume)
        let valueMultiple = (avgValue20 > 0) ? (valueToday / avgValue20) : 0
        notes.append(String(format: "valueMult=%.2f", valueMultiple))

        // CLV
        let clv = CLV.value(candle: last) ?? 0.5
        let clvScore = scoreCLVNonLinear(clv)
        notes.append(String(format: "clv=%.3f → skor=%.2f", clv, clvScore))

        // Proximity
        let closesExToday = Array(closes.dropLast())
        let highsExToday  = Array(highs.dropLast())
        let highestClose20 = BreakoutLevels.highestClose(closes: closesExToday, lookback: lookback) ?? 0
        let highestHigh20  = BreakoutLevels.highestHigh(highs: highsExToday, lookback: lookback) ?? 0
        let tier = liquidityTier(avgValue20: avgValue20)
        let refLevel = tier == .c ? highestHigh20 : highestClose20

        if refLevel > 0 {
            let proximity = last.close / refLevel
            let proxScore = scoreProximityNonLinear(proximity)
            notes.append(String(format: "proximity=%.4f → skor=%.2f (sweet: 0.97-1.00)", proximity, proxScore))

            if proxScore < 0.3 {
                notes.append("⚠️ proximity düşük skor (sweet spot: 0.97-1.00)")
            }
        } else {
            notes.append("⛔ refLevel=0")
            return (nil, .refLevelInvalid, notes)
        }

        // Volume trend
        let recentVols = Array(volumes.suffix(5))
        let olderVols  = Array(volumes.dropLast(5).suffix(10))
        let avgRecentVol = recentVols.isEmpty ? 0 : recentVols.reduce(0, +) / Double(recentVols.count)
        let avgOlderVol  = olderVols.isEmpty ? 1 : olderVols.reduce(0, +) / Double(olderVols.count)
        let volumeTrend = avgOlderVol > 0 ? (avgRecentVol / avgOlderVol) : 1.0
        let volScore = scoreVolumeTrendNonLinear(volumeTrend)
        notes.append(String(format: "volTrend=%.2f → skor=%.2f (ideal: 1.2-2.5)", volumeTrend, volScore))

        // Range compression
        let recentRanges = candles.suffix(5).map { $0.high - $0.low }
        let olderRanges  = candles.dropLast(5).suffix(10).map { $0.high - $0.low }
        let avgRecentRange = recentRanges.isEmpty ? 0 : recentRanges.reduce(0, +) / Double(recentRanges.count)
        let avgOlderRange  = olderRanges.isEmpty ? 1 : olderRanges.reduce(0, +) / Double(olderRanges.count)
        let rangeCompression = avgOlderRange > 0 ? (avgRecentRange / avgOlderRange) : 1.0
        let compScore = scoreCompressionNonLinear(rangeCompression)
        notes.append(String(format: "rangeComp=%.2f → skor=%.2f (düşük=iyi)", rangeCompression, compScore))

        // Today change
        let prevClose = candles.count >= 2 ? candles[candles.count - 2].close : last.close
        let todayChangePct = prevClose > 0 ? ((last.close - prevClose) / prevClose) * 100 : 0
        let momAdj = momentumAdjustment(todayChangePct)
        notes.append(String(format: "todayChg=%.1f%% → momentum=%+.1f puan", todayChangePct, momAdj))

        // Trend
        let ema20 = EMA.lastValue(values: closes, period: 20) ?? 0
        let ema50 = EMA.lastValue(values: closes, period: 50) ?? 0
        let trendScore = scoreTrend(lastClose: last.close, ema20: ema20, ema50: ema50)
        notes.append(String(format: "trend=%.2f (close=%.2f ema20=%.2f ema50=%.2f)", trendScore, last.close, ema20, ema50))

        // Gerçek skoru al (softMode ile)
        let result = scoreWithConfig(candles: candles, config: config, softMode: true)
        if let r = result {
            notes.append("✅ SKOR=\(r.total) kalite=\(r.quality)")
        } else {
            notes.append("❌ skor eşiğin altında (min=\(config.minScore))")
        }

        return (result, result == nil ? .scoreBelowMin : nil, notes)
    }

    // MARK: - Tier thresholds (AvgValue20 in TL)

    private static let tierA: Double = 50_000_000
    private static let tierB: Double = 15_000_000
    private static let tierC: Double = 5_000_000

    // MARK: - Core entry (preset-based, backwards compatible)

    static func scoreTomorrowBuyOnly(
        candles: [Candle],
        preset: TomorrowPreset,
        regime: MarketRegime? = nil,
        lookback: Int? = nil
    ) -> TomorrowSignalScore? {
        // v2: Preset → StrategyConfig dönüşümü
        // Tüm presetler softMode kullanır.
        // Lookback: Normal preset'te StrategyConfig.lookbackDays aktif;
        // Relaxed/Strict için preset lookback kullanılır (opsiyonel manuel override hariç).
        var cfg = StrategyConfig.load()
        cfg.lookbackDays = effectiveLookback(
            preset: preset,
            configuredLookback: cfg.lookbackDays,
            overrideLookback: lookback
        )
        let activeRegime = regime ?? MarketRegimeDetector.detect(from: candles)
        cfg.minScore = dynamicMinScore(for: preset, regime: activeRegime, config: cfg)

        // ✅ v2: Tüm presetler softMode=true
        // Non-linear scoring zaten seçiciliği sağlıyor
        return scoreWithConfig(candles: candles, config: cfg, softMode: true)
    }

    static func effectiveLookback(
        preset: TomorrowPreset,
        configuredLookback: Int,
        overrideLookback: Int? = nil
    ) -> Int {
        func clamp(_ value: Int) -> Int { min(60, max(10, value)) }

        if let overrideLookback {
            return clamp(overrideLookback)
        }

        switch preset {
        case .normal:
            return clamp(configuredLookback) // Strategy editor'da ayarlanan değer
        case .relaxed, .strict:
            return preset.lookbackDays
        }
    }

    static func dynamicMinScore(
        for preset: TomorrowPreset,
        regime: MarketRegime,
        config: StrategyConfig
    ) -> Int {
        let base = preset.minBuyTotal
        let adjusted: Int

        switch regime {
        case .bull:
            adjusted = base + config.regimeBullDelta
        case .sideways:
            adjusted = base + config.regimeSidewaysDelta
        case .bear:
            adjusted = max(base + config.regimeBearDelta, config.regimeBearMinScore)
        }

        return min(95, max(0, adjusted))
    }

    // MARK: - Core scoring engine (v2)

    /// PRE-BREAKOUT: Non-linear scoring with configurable weights
    /// softMode=true → hard guard'lar kapalı, sadece skor eşiği filtreler
    /// softMode=false → hard guard'lar aktif (manual config için)
    static func scoreWithConfig(
        candles: [Candle],
        config: StrategyConfig,
        softMode: Bool = false
    ) -> TomorrowSignalScore? {

        let lookback = config.lookbackDays

        // ── DATA GUARDS (her zaman aktif) ──
        guard candles.count >= max(lookback + 5, 40) else {
            return nil
        }
        guard let last = candles.last else { return nil }

        let closes = candles.map(\.close)
        let highs  = candles.map(\.high)
        let volumes = candles.map { Double($0.volume) }

        // ---------- Liquidity (AvgValue20)
        let avgValue20 = ValueSeries.averageValue(closes: closes, volumes: volumes, period: 20) ?? 0
        var tier = liquidityTier(avgValue20: avgValue20)
        if tier == .none { tier = .b }

        // ---------- Value (today / avg20)
        let valueToday = last.close * Double(last.volume)
        let valueMultiple = (avgValue20 > 0) ? (valueToday / avgValue20) : 0
        if !softMode {
            guard valueMultiple >= config.minValueMultiple else { return nil }
        }

        // ---------- CLV (high==low ise nil → softMode'da 0.5)
        let clvValue: Double
        if let c = CLV.value(candle: last) {
            clvValue = c
        } else if softMode {
            clvValue = 0.5
        } else {
            return nil
        }
        if !softMode {
            guard clvValue >= config.minCLV else { return nil }
        }

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

        // refLevel=0 ise skor hesaplanamaz
        guard refLevel > 0 else {
            return nil
        }

        let proximity = last.close / refLevel

        if !softMode {
            guard proximity >= config.minProximity else { return nil }
            guard proximity <= config.maxProximity else { return nil }
        }

        let didBreakout = proximity > 1.0

        // ---------- Volume Trend
        let recentVols = Array(volumes.suffix(5))
        let olderVols  = Array(volumes.dropLast(5).suffix(10))
        let avgRecentVol = recentVols.isEmpty ? 0 : recentVols.reduce(0, +) / Double(recentVols.count)
        let avgOlderVol  = olderVols.isEmpty ? 1 : olderVols.reduce(0, +) / Double(olderVols.count)
        let volumeTrend = avgOlderVol > 0 ? (avgRecentVol / avgOlderVol) : 1.0

        if !softMode && config.minVolumeTrend > 0 {
            guard volumeTrend >= config.minVolumeTrend else { return nil }
        }

        // ---------- Range Compression
        let recentRanges = candles.suffix(5).map { $0.high - $0.low }
        let olderRanges  = candles.dropLast(5).suffix(10).map { $0.high - $0.low }
        let avgRecentRange = recentRanges.isEmpty ? 0 : recentRanges.reduce(0, +) / Double(recentRanges.count)
        let avgOlderRange  = olderRanges.isEmpty ? 1 : olderRanges.reduce(0, +) / Double(olderRanges.count)
        let rangeCompression = avgOlderRange > 0 ? (avgRecentRange / avgOlderRange) : 1.0

        if !softMode {
            guard rangeCompression <= config.maxRangeCompression else { return nil }
        }

        // ---------- Today Change
        let prevClose = candles.count >= 2 ? candles[candles.count - 2].close : last.close
        let todayChangePct = prevClose > 0 ? ((last.close - prevClose) / prevClose) * 100 : 0
        if !softMode {
            guard todayChangePct <= config.maxTodayChangePct else { return nil }
        }

        // ---------- TR spike
        let trSeries = TrueRange.calculate(candles: candles)
        let trToday = trSeries.last ?? 0
        let trMedian20 = Rolling.medianLast(trSeries, window: 20) ?? 1
        let trSpikeMultiple = trMedian20 > 0 ? (trToday / trMedian20) : 1.0

        // ---------- Compression check (for breakdown display)
        let compression = compressionOK(candles: candles, window: 8)

        // ═══════════════════════════════════════════════════
        // NON-LINEAR SCORE BUILD (v2)
        // ═══════════════════════════════════════════════════

        let proxScore  = scoreProximityNonLinear(proximity)
        let clvScore   = scoreCLVNonLinear(clvValue)
        let volScore   = scoreVolumeTrendNonLinear(volumeTrend)
        let compScore  = scoreCompressionNonLinear(rangeCompression)
        let trendScore = scoreTrend(lastClose: last.close, ema20: ema20, ema50: ema50)

        // Ağırlıklar (config'ten, kullanıcı ayarlayabilir)
        let wP = config.weightProximity      // default 35
        let wV = config.weightVolumeTrend    // default 20
        let wC = config.weightCLV            // default 20
        let wR = config.weightCompression    // default 15
        let wT = config.weightTrend          // default 10

        let wTotal = wP + wV + wC + wR + wT
        let normalizer = wTotal > 0 ? (100.0 / wTotal) : 1.0

        // Ağırlıklı toplam → 0..100
        let rawScore = (proxScore  * wP +
                        volScore   * wV +
                        clvScore   * wC +
                        compScore  * wR +
                        trendScore * wT) * normalizer

        // Momentum adjustment (bonus + ceza)
        let momAdj = momentumAdjustment(todayChangePct)

        let synergyAdj = setupSynergyAdjustment(
            proximity: proximity,
            volumeTrend: volumeTrend,
            rangeCompression: rangeCompression,
            clv: clvValue
        )

        let total = min(100, max(0, Int(round(rawScore + momAdj + synergyAdj))))
        let effectiveMinScore = min(
            95,
            max(
                0,
                config.minScore + dynamicMinScoreDelta(
                    trSpikeMultiple: trSpikeMultiple,
                    liquidityTier: tier
                )
            )
        )

        // SoftMode'da dahi kalite tabanı uygula (noise azaltma)
        let minScoreGate = softMode
            ? max(effectiveMinScore, config.softModeMinQualityScore)
            : effectiveMinScore

        guard total >= minScoreGate else { return nil }

        let quality = qualityBand(total: total, config: config)

        // Reasons (max 3) — non-linear skorlara göre
        var reasons: [String] = []
        if proxScore >= 0.7  { reasons.append("Kırılım Yakın") }
        if volScore >= 0.6   { reasons.append("Hacim Artışı") }
        if compScore >= 0.6  { reasons.append("Sıkışma") }
        if clvScore >= 0.7   { reasons.append("Güçlü Kapanış") }
        if trendScore >= 0.8 { reasons.append("Trend Yukarı") }
        reasons = Array(reasons.prefix(3))
        if reasons.isEmpty { reasons.append("Pre-Breakout") }

        var bd = TomorrowBreakdown()
        bd.avgValue20 = avgValue20
        bd.valueToday = valueToday
        bd.valueMultiple = valueMultiple

        bd.clv = clvValue

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
            String(format: "Bugün %+.1f%%", todayChangePct),
            "Dinamik Eşik \(minScoreGate)"
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

    static func resetDebugCounter() {}

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

import Foundation

// MARK: - Ultra Strategy: NextDay Momentum Bounce
// ═══════════════════════════════════════════════════════════════════════
// Hedef: 1-3 gün içinde %5+ artış potansiyeli olan hisseleri tespit et.
//
// STRATEJİ FELSEFESİ:
//   Yükselen trendde geçici geri çekilme yapmış, ATR'si yüksek
//   (günlük %3+ hareket edebilen), hacimle toparlanma sinyali
//   veren hisseleri bul. Bu hisseler "sıkışmış yay" gibidir:
//   enerji biriktirmiş ve patlama potansiyeli taşır.
//
// NEDEN FARKLI:
//   Pre-Breakout: Zirveye yakın → sınırlı yukarı potansiyel
//   Ultra Bounce: Zirveden geri çekilmiş → DAHA FAZLA yukarı potansiyel
//
// 9 FAKTÖRLÜ NON-LINEAR SKORLAMA:
//   [1] Momentum Bounce  (22) — RSI oversold'dan toparlanma
//   [2] Volume Power     (20) — Hacim patlaması + OBV diverjans
//   [3] Close Strength   (15) — CLV + kapanış gücü
//   [4] Trend Alignment  (13) — EMA hizalama + ADX trend gücü
//   [5] Pullback Quality (12) — Kontrollü geri çekilme (düşen bıçak değil)
//   [6] Bollinger Bounce  (8) — Alt band yakınlığında sıçrama
//   [7] MACD Reversal     (5) — Histogram dönüş noktası
//   [8] Pattern Score     (3) — Bullish mum formasyonları
//   [9] Volatility Edge   (2) — ATR-bazlı hareket potansiyeli
//
// DİNAMİK TP/SL:
//   Her hissenin ATR'sine göre otomatik TP ve SL hesaplanır.
//   Volatil hisselerde geniş, sakin hisselerde dar TP/SL.
// ═══════════════════════════════════════════════════════════════════════

// MARK: - Ultra Strategy Config

struct UltraStrategyConfig: Codable, Equatable {

    init() {}

    // MARK: - Volatility Gate
    /// ATR/Close minimum (%). Bunun altındaki hisseler 1 günde %5 hareket EDEMEZ.
    var minATRPct: Double = 2.5

    // MARK: - Trend Filter
    /// EMA50 altındaki hisseler reddedilsin mi? (düşen bıçak koruması)
    var requireAboveEMA50: Bool = true
    /// ADX minimum: trendin gücünü ölçer. <15 = trend yok, >25 = güçlü trend
    var minADX: Double = 15.0

    // MARK: - Pullback Range
    /// Minimum geri çekilme (%) — çok sığ = indirim yok
    var minPullbackPct: Double = 3.0
    /// Maksimum geri çekilme (%) — çok derin = düşen bıçak riski
    var maxPullbackPct: Double = 20.0
    /// Gaussian peak noktası — en ideal geri çekilme mesafesi
    var idealPullbackPct: Double = 8.0

    // MARK: - RSI Bounce
    /// RSI alt sınır (aşırı satım bölgesi)
    var rsiLow: Double = 25.0
    /// RSI üst sınır (henüz nötr → giriş penceresi kapanıyor)
    var rsiHigh: Double = 50.0
    /// Gaussian peak — en ideal RSI seviyesi
    var rsiIdeal: Double = 35.0

    // MARK: - Volume
    /// Minimum relative volume — bunun altı "ilgi yok" demek
    var minRelativeVolume: Double = 0.6

    // MARK: - Scoring
    /// Minimum toplam skor (0-100). Bunun altı reddedilir.
    var minScore: Int = 55

    // MARK: - Weights (toplam 100)
    var wMomentumBounce: Double = 22
    var wVolumePower: Double = 20
    var wCloseStrength: Double = 15
    var wTrendAlignment: Double = 13
    var wPullbackQuality: Double = 12
    var wBollingerBounce: Double = 8
    var wMACDReversal: Double = 5
    var wPatternScore: Double = 3
    var wVolatilityEdge: Double = 2

    // MARK: - Quality Bands
    var qualityS: Int = 88       // S-Tier: Süper sinyal (nadir)
    var qualityAPlus: Int = 78   // A+: Çok güçlü
    var qualityA: Int = 68       // A: Güçlü
    var qualityB: Int = 58       // B: İyi
    var qualityC: Int = 48       // C: Zayıf

    // MARK: - Dynamic TP/SL (ATR-based)
    /// TP = ATR * bu çarpan (fiyat yüzde olarak)
    var tpATRMultiple: Double = 2.0
    /// SL = ATR * bu çarpan
    var slATRMultiple: Double = 1.2
    /// Minimum TP %
    var minTPPct: Double = 4.0
    /// Maksimum TP %
    var maxTPPct: Double = 12.0
    /// Minimum SL %
    var minSLPct: Double = 2.0
    /// Maksimum SL %
    var maxSLPct: Double = 5.0

    // MARK: - Regime Adjustments
    var regimeBullDelta: Int = -5    // Bull'da daha geniş ağ
    var regimeSidewaysDelta: Int = 0
    var regimeBearDelta: Int = 10    // Bear'da çok seçici

    // MARK: - Presets

    /// Sniper: Sadece en güçlü sinyaller (%1-5 geçer)
    static var sniper: UltraStrategyConfig {
        var c = UltraStrategyConfig()
        c.minATRPct = 3.5
        c.minADX = 20
        c.minPullbackPct = 5
        c.maxPullbackPct = 15
        c.rsiLow = 25
        c.rsiHigh = 42
        c.minRelativeVolume = 1.2
        c.minScore = 70
        return c
    }

    /// Hunter: Dengeli (varsayılan) (%10-25 geçer)
    static var hunter: UltraStrategyConfig {
        UltraStrategyConfig()
    }

    /// Scout: Geniş tarama (%25-50 geçer)
    static var scout: UltraStrategyConfig {
        var c = UltraStrategyConfig()
        c.minATRPct = 2.0
        c.minADX = 12
        c.minPullbackPct = 2
        c.maxPullbackPct = 25
        c.rsiLow = 20
        c.rsiHigh = 55
        c.minRelativeVolume = 0.4
        c.minScore = 42
        return c
    }

    // MARK: - Persistence

    private static let key = "ultra.strategy.config.v1"

    static func load() -> UltraStrategyConfig {
        guard let data = UserDefaults.standard.data(forKey: key),
              let cfg = try? JSONDecoder().decode(UltraStrategyConfig.self, from: data)
        else { return .hunter }
        return cfg
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: UltraStrategyConfig.key)
        }
    }
}

// MARK: - Ultra Preset

enum UltraPreset: String, Codable, CaseIterable {
    case sniper
    case hunter
    case scout

    var title: String {
        switch self {
        case .sniper: return "Sniper"
        case .hunter: return "Hunter"
        case .scout:  return "Scout"
        }
    }

    var config: UltraStrategyConfig {
        switch self {
        case .sniper: return .sniper
        case .hunter: return .hunter
        case .scout:  return .scout
        }
    }
}

// MARK: - Scan Strategy Mode

enum ScanStrategyMode: String, Codable, CaseIterable, Identifiable {
    case preBreakout = "Pre-Breakout"
    case ultraBounce = "Ultra Bounce"
    case ensemble = "Ensemble"

    var id: String { rawValue }
    var title: String { rawValue }
}

// MARK: - Ultra Signal Scorer

enum UltraSignalScorer {

    // MARK: - Main Entry Point

    /// 9-faktörlü ultra scoring: TomorrowSignalScore döner (mevcut UI ile uyumlu).
    /// nil dönerse sinyal yoktur (gate'lerden veya minScore'dan reddedilmiştir).
    static func score(
        candles: [Candle],
        config: UltraStrategyConfig = .hunter,
        regime: MarketRegime? = nil
    ) -> TomorrowSignalScore? {

        // ── DATA GUARD ──
        guard candles.count >= 60, let last = candles.last else { return nil }

        let closes = candles.map(\.close)
        let highs = candles.map(\.high)
        let volumes = candles.map { Double($0.volume) }

        // ═══ GATE 1: Volatility ═══
        // Hisse günlük yeterince hareket edebilmeli. ATR/Close < minATRPct → red.
        guard let atr14 = ATR.lastValue(candles: candles),
              last.close > 0 else { return nil }
        let atrPct = (atr14 / last.close) * 100
        guard atrPct >= config.minATRPct else { return nil }

        // ═══ GATE 2: Trend (EMA50 filtresi) ═══
        // Düşen bıçağa karşı koruma. EMA50'nin %3 altı → red.
        let ema9 = EMA.lastValue(values: closes, period: 9) ?? 0
        let ema20 = EMA.lastValue(values: closes, period: 20) ?? 0
        let ema50 = EMA.lastValue(values: closes, period: 50) ?? 0
        if config.requireAboveEMA50 && ema50 > 0 && last.close < ema50 * 0.97 {
            return nil
        }

        // ═══ CALCULATE ALL FACTORS ═══

        // RSI (14)
        let rsiSeries = RSI.calculate(closes: closes)
        let rsiCompact = rsiSeries.compactMap { $0 }
        let rsi = rsiCompact.last ?? 50
        let rsiPrev = rsiCompact.count >= 2 ? rsiCompact[rsiCompact.count - 2] : rsi

        // MACD (12/26/9)
        let macdResult = MACD.calculate(closes: closes)
        let histCompact = macdResult.histogram.compactMap { $0 }
        let histogram = histCompact.last ?? 0
        let prevHistogram = histCompact.count >= 2 ? histCompact[histCompact.count - 2] : 0

        // Volume
        let relVol = VolumeAnalysis.relativeVolume(volumes: volumes) ?? 1.0
        let recentVols = Array(volumes.suffix(5))
        let olderVols = Array(volumes.dropLast(5).suffix(10))
        let avgRecentVol = recentVols.isEmpty ? 0 : recentVols.reduce(0, +) / Double(recentVols.count)
        let avgOlderVol = olderVols.isEmpty ? 1 : olderVols.reduce(0, +) / Double(olderVols.count)
        let volumeTrend = avgOlderVol > 0 ? (avgRecentVol / avgOlderVol) : 1.0

        // OBV (On Balance Volume) — para akışı analizi
        let obv = VolumeAnalysis.obv(closes: closes, volumes: volumes)
        let obvRising: Bool = {
            guard obv.count >= 6 else { return false }
            let recent = obv[obv.count - 1]
            let older = obv[obv.count - 4]
            return recent > older
        }()

        // Price action
        let prevClose = candles.count >= 2 ? candles[candles.count - 2].close : last.close
        let priceFalling = last.close < prevClose
        let isBullish = last.close > last.open
        let clv = CLV.value(candle: last) ?? 0.5

        // Pullback from recent high (15 gün)
        let recentHigh = Array(highs.suffix(15)).max() ?? last.high
        let pullbackPct = recentHigh > 0 ? ((recentHigh - last.close) / recentHigh) * 100 : 0

        // Bollinger %B
        let bbPctB = BollingerBands.percentB(closes: closes) ?? 0.5

        // ADX (trend gücü)
        let adx = ADX.lastValue(candles: candles) ?? 20

        // Bullish pattern score
        let patterns = PatternDetector.detectScored(last: Array(candles.suffix(60)))
        let bullishPatternScore = patterns
            .filter { $0.pattern.direction == .bullish }
            .map(\.score)
            .max() ?? 0

        // Günlük getiri analizi (son 20 gün)
        let dailyReturns: [Double] = (1..<min(21, closes.count)).compactMap { i in
            let idx = closes.count - 1 - i
            guard idx > 0 else { return nil }
            return ((closes[idx] - closes[idx - 1]) / closes[idx - 1]) * 100
        }
        let maxDailyReturn20 = dailyReturns.max() ?? 0

        // Liquidity
        let avgValue20 = ValueSeries.averageValue(closes: closes, volumes: volumes, period: 20) ?? 0
        let tier = liquidityTier(avgValue20: avgValue20)

        // ═══ SCORE EACH FACTOR (0..1) ═══

        let s1 = scoreMomentumBounce(rsi: rsi, rsiPrev: rsiPrev, config: config)
        let s2 = scoreVolumePower(relativeVolume: relVol, volumeTrend: volumeTrend,
                                  obvRising: obvRising, priceFalling: priceFalling)
        let s3 = scoreCloseStrength(clv: clv, isBullishCandle: isBullish)
        let s4 = scoreTrendAlignment(close: last.close, ema9: ema9, ema20: ema20,
                                     ema50: ema50, adx: adx, config: config)
        let s5 = scorePullbackQuality(pullbackPct: pullbackPct, config: config)
        let s6 = scoreBollingerBounce(percentB: bbPctB)
        let s7 = scoreMACDReversal(histogram: histogram, prevHistogram: prevHistogram)
        let s8 = scorePatterns(bullishPatternScore: bullishPatternScore)
        let s9 = scoreVolatilityEdge(atrPct: atrPct, maxDailyReturn20: maxDailyReturn20)

        // ═══ WEIGHTED SUM → 0..100 ═══

        let wTotal = config.wMomentumBounce + config.wVolumePower + config.wCloseStrength +
                     config.wTrendAlignment + config.wPullbackQuality + config.wBollingerBounce +
                     config.wMACDReversal + config.wPatternScore + config.wVolatilityEdge
        let normalizer = wTotal > 0 ? (100.0 / wTotal) : 1.0

        let rawScore = (s1 * config.wMomentumBounce +
                        s2 * config.wVolumePower +
                        s3 * config.wCloseStrength +
                        s4 * config.wTrendAlignment +
                        s5 * config.wPullbackQuality +
                        s6 * config.wBollingerBounce +
                        s7 * config.wMACDReversal +
                        s8 * config.wPatternScore +
                        s9 * config.wVolatilityEdge) * normalizer

        // ── SYNERGY BONUS (faktörler birlikte güçlenir) ──
        let synergyBonus = synergyAdjustment(s1: s1, s2: s2, s3: s3, s4: s4, s5: s5, s6: s6)

        // ── REGIME ADJUSTMENT ──
        let activeRegime = regime ?? MarketRegimeDetector.detect(from: candles)
        let total = min(100, max(0, Int(round(rawScore + synergyBonus))))

        // ── MIN SCORE GATE ──
        let effectiveMin = effectiveMinScore(base: config.minScore, regime: activeRegime, config: config)
        guard total >= effectiveMin else { return nil }

        // ── QUALITY BAND ──
        let quality = qualityBand(total: total, config: config)

        // ── DYNAMIC TP/SL ──
        let dynamicTP = min(config.maxTPPct, max(config.minTPPct, atrPct * config.tpATRMultiple))
        let dynamicSL = min(config.maxSLPct, max(config.minSLPct, atrPct * config.slATRMultiple))
        let rr = dynamicSL > 0 ? dynamicTP / dynamicSL : 0

        // ── REASONS (max 3) ──
        var reasons: [String] = []
        if s1 >= 0.6 { reasons.append("RSI Bounce") }
        if s2 >= 0.6 { reasons.append("Hacim Gücü") }
        if s3 >= 0.7 { reasons.append("Güçlü Kapanış") }
        if s4 >= 0.7 { reasons.append("Trend Güçlü") }
        if s5 >= 0.5 { reasons.append("Geri Çekilme") }
        if s6 >= 0.6 { reasons.append("BB Bounce") }
        if s7 >= 0.7 { reasons.append("MACD Dönüş") }
        reasons = Array(reasons.prefix(3))
        if reasons.isEmpty { reasons.append("Ultra Momentum") }

        // ── BUILD BREAKDOWN ──
        // TomorrowBreakdown ile uyumlu (mevcut UI'ı kırmadan kullan)
        var bd = TomorrowBreakdown()
        bd.avgValue20 = avgValue20
        bd.valueToday = last.close * Double(last.volume)
        bd.valueMultiple = avgValue20 > 0 ? bd.valueToday / avgValue20 : 0
        bd.clv = clv
        bd.lookback = 15
        bd.highestClose = recentHigh
        bd.highestHigh = recentHigh
        bd.ema20 = ema20
        bd.ema50 = ema50
        bd.trendOK = last.close >= ema50
        bd.proximityPct = recentHigh > 0 ? last.close / recentHigh : 1.0
        bd.volumeTrend = volumeTrend
        bd.rangeCompression = 0
        bd.notes = [
            "\(tier.label)",
            String(format: "ATR %.1f%%", atrPct),
            String(format: "RSI %.0f (%.0f→%.0f)", rsi, rsiPrev, rsi),
            String(format: "ADX %.0f", adx),
            String(format: "Pullback -%.1f%%", pullbackPct),
            String(format: "BB %%B %.2f", bbPctB),
            String(format: "TP %.1f%% / SL %.1f%%", dynamicTP, dynamicSL),
            String(format: "R:R %.1f:1", rr),
            String(format: "Rejim: %@ (eşik %d)", activeRegime.title, effectiveMin),
            "Ultra Bounce Strateji"
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

    // MARK: - ═══════════════════════════════════════
    // FACTOR 1: Momentum Bounce (weight: 22)
    // RSI oversold bölgesinden toparlanma → güçlü sıçrama sinyali
    // ═══════════════════════════════════════

    private static func scoreMomentumBounce(
        rsi: Double,
        rsiPrev: Double,
        config: UltraStrategyConfig
    ) -> Double {
        // RSI tamamen dışındaysa düşük skor
        let expandedLow = config.rsiLow - 8
        let expandedHigh = config.rsiHigh + 8
        guard rsi >= expandedLow && rsi <= expandedHigh else { return 0.02 }

        // ── Gaussian bell curve: RSI ideal noktaya yakınlık ──
        // Peak: rsiIdeal (default 35) = en ideal giriş noktası
        // Sigma: (high-low)/3 → range'in ~68%'i yüksek skor alır
        let center = config.rsiIdeal
        let sigma = max(3, (config.rsiHigh - config.rsiLow) / 3.0)
        let rsiScore = exp(-pow((rsi - center) / sigma, 2))

        // ── RSI Slope (momentum dönüşü) ──
        // Pozitif slope = toparlanma, negatif = hâlâ düşüyor
        let slope = rsi - rsiPrev
        let slopeBonus: Double
        if slope > 4 {        // Hızlı toparlanma
            slopeBonus = 0.30
        } else if slope > 2 { // İyi toparlanma
            slopeBonus = 0.20
        } else if slope > 0 { // Hafif toparlanma
            slopeBonus = 0.08
        } else if slope > -2 { // Yatay/hafif düşüş
            slopeBonus = -0.05
        } else {              // Hâlâ sert düşüyor
            slopeBonus = -0.15
        }

        // ── Aşırı satım bonusu (RSI < 30 ek ödül) ──
        let oversoldBonus: Double
        if rsi < 20 { oversoldBonus = 0.15 }
        else if rsi < 25 { oversoldBonus = 0.10 }
        else if rsi < 30 { oversoldBonus = 0.05 }
        else { oversoldBonus = 0 }

        return min(1.0, max(0, rsiScore + slopeBonus + oversoldBonus))
    }

    // MARK: - ═══════════════════════════════════════
    // FACTOR 2: Volume Power (weight: 20)
    // Hacim artışı = kurumsal ilgi. OBV diverjansı = gizli birikim.
    // ═══════════════════════════════════════

    private static func scoreVolumePower(
        relativeVolume: Double,
        volumeTrend: Double,
        obvRising: Bool,
        priceFalling: Bool
    ) -> Double {
        // ── Relative Volume: bugünkü hacim / 20 günlük ortalama ──
        let relVolScore: Double
        switch relativeVolume {
        case ..<0.4:  relVolScore = 0.02
        case ..<0.7:  relVolScore = 0.10
        case ..<1.0:  relVolScore = 0.30
        case ..<1.3:  relVolScore = 0.55
        case ..<1.8:  relVolScore = 0.75
        case ..<2.5:  relVolScore = 0.90
        case ..<3.5:  relVolScore = 1.00
        default:      relVolScore = 0.80 // Aşırı hacim → belirsizlik
        }

        // ── Volume Trend: son 5 gün / önceki 10 gün ──
        let volTrendScore: Double
        switch volumeTrend {
        case ..<0.4:  volTrendScore = 0.05
        case ..<0.7:  volTrendScore = 0.15
        case ..<1.0:  volTrendScore = 0.40
        case ..<1.5:  volTrendScore = 0.70
        case ..<2.5:  volTrendScore = 0.90
        case ..<4.0:  volTrendScore = 1.00
        default:      volTrendScore = 0.65
        }

        // ── OBV Diverjansı: Fiyat düşerken OBV yükseliyor = AKILLI PARA birikimi ──
        // Bu çok güçlü bir sinyal: kurumlar sessizce topluyorlar
        let obvBonus: Double = (obvRising && priceFalling) ? 0.25 : 0

        let combined = relVolScore * 0.45 + volTrendScore * 0.30 + obvBonus
        return min(1.0, max(0, combined))
    }

    // MARK: - ═══════════════════════════════════════
    // FACTOR 3: Close Strength (weight: 15)
    // Kapanışın günün range'indeki konumu. Güçlü kapanış = alıcı hakimiyeti.
    // ═══════════════════════════════════════

    private static func scoreCloseStrength(
        clv: Double,
        isBullishCandle: Bool
    ) -> Double {
        // ── Sigmoid CLV ──
        // 0.0 (en düşükte kapanış) → düşük skor
        // 0.5 (ortada) → orta
        // 0.8+ (güçlü kapanış) → yüksek skor
        let clvScore = 1.0 / (1.0 + exp(-10.0 * (clv - 0.45)))

        // ── Bullish candle bonus ──
        // Close > Open → alıcılar günü kontrol etti
        let candleBonus: Double = isBullishCandle ? 0.12 : -0.03

        return min(1.0, max(0, clvScore + candleBonus))
    }

    // MARK: - ═══════════════════════════════════════
    // FACTOR 4: Trend Alignment (weight: 13)
    // EMA hiyerarşisi + ADX trend gücü. Trende karşı işlem yapma!
    // ═══════════════════════════════════════

    private static func scoreTrendAlignment(
        close: Double,
        ema9: Double,
        ema20: Double,
        ema50: Double,
        adx: Double,
        config: UltraStrategyConfig
    ) -> Double {
        // ── EMA Alignment: kaç bullish koşul sağlanıyor? ──
        var alignment = 0
        if close > ema50 { alignment += 1 }  // Temel trend yukarı
        if ema20 > ema50 { alignment += 1 }  // Orta vadeli trend yukarı
        if close > ema20 { alignment += 1 }  // Fiyat MA üzerinde
        if ema9 > ema20  { alignment += 1 }  // Kısa vadeli momentum yukarı

        let baseScore: Double
        switch alignment {
        case 4:  baseScore = 1.00  // Mükemmel hizalama
        case 3:  baseScore = 0.75  // İyi
        case 2:  baseScore = 0.45  // Orta (pullback bölgesi olabilir)
        case 1:  baseScore = 0.20  // Zayıf
        default: baseScore = 0.05  // Hizalama yok
        }

        // ── ADX Multiplier: trend gücü skoru amplifiye eder ──
        let adxMult: Double
        if adx >= 40 {            adxMult = 1.25  // Çok güçlü trend
        } else if adx >= 30 {     adxMult = 1.15
        } else if adx >= 25 {     adxMult = 1.08
        } else if adx >= config.minADX { adxMult = 1.00
        } else {                   adxMult = 0.55  // Zayıf trend → skor düşür
        }

        // ── EMA yakınlık bonusu: pullback'te EMA20'ye dokunmuş ──
        // Bu güçlü bir destek testi sinyali
        let emaProximityBonus: Double
        if ema20 > 0 {
            let distToEMA20 = abs(close - ema20) / ema20
            if distToEMA20 < 0.01 { emaProximityBonus = 0.08 }      // %1 içinde
            else if distToEMA20 < 0.02 { emaProximityBonus = 0.04 } // %2 içinde
            else { emaProximityBonus = 0 }
        } else {
            emaProximityBonus = 0
        }

        return min(1.0, baseScore * adxMult + emaProximityBonus)
    }

    // MARK: - ═══════════════════════════════════════
    // FACTOR 5: Pullback Quality (weight: 12)
    // Geri çekilmenin kalitesi: ne çok sığ ne çok derin. "Goldilocks zone."
    // ═══════════════════════════════════════

    private static func scorePullbackQuality(
        pullbackPct: Double,
        config: UltraStrategyConfig
    ) -> Double {
        // Fiyat zirvede veya zirve üzerinde → geri çekilme yok → düşük skor
        guard pullbackPct > 0 else { return 0.05 }

        // Çok derin → düşen bıçak riski
        if pullbackPct > config.maxPullbackPct { return 0 }

        // Çok sığ → indirim yok
        if pullbackPct < config.minPullbackPct * 0.5 { return 0.08 }

        // ── Gaussian: ideal pullback = peak skor ──
        // Orta düzeyde geri çekilme en iyi fırsattır:
        // — Yeterince indirimli fiyat
        // — Ama trend hâlâ sağlam
        let center = config.idealPullbackPct
        let sigma = max(2, (config.maxPullbackPct - config.minPullbackPct) / 3.0)
        return exp(-pow((pullbackPct - center) / sigma, 2))
    }

    // MARK: - ═══════════════════════════════════════
    // FACTOR 6: Bollinger Bounce (weight: 8)
    // Alt banda yakın = aşırı satım + sıçrama potansiyeli
    // ═══════════════════════════════════════

    private static func scoreBollingerBounce(percentB: Double) -> Double {
        // %B < 0 → alt bandın altında (çok nadir, güçlü sinyal)
        // %B = 0 → tam alt bant
        // %B = 1 → tam üst bant
        switch percentB {
        case ..<0:    return 0.95
        case ..<0.05: return 0.92
        case ..<0.15: return 0.80
        case ..<0.25: return 0.60
        case ..<0.35: return 0.40
        case ..<0.45: return 0.20
        case ..<0.55: return 0.10
        default:      return 0.03  // Üst yarı → bounce sinyali yok
        }
    }

    // MARK: - ═══════════════════════════════════════
    // FACTOR 7: MACD Reversal (weight: 5)
    // Histogram negatiften pozitife dönüş = momentum değişimi
    // ═══════════════════════════════════════

    private static func scoreMACDReversal(
        histogram: Double,
        prevHistogram: Double
    ) -> Double {
        let isAccelerating = histogram > prevHistogram

        // En iyi: histogram negatiften pozitife geçiş anı
        if prevHistogram < 0 && histogram >= 0 { return 1.0 }

        // İyi: hâlâ negatif ama yükseliyor (dip arıyor)
        if histogram < 0 && isAccelerating { return 0.65 }

        // OK: pozitif ve yükseliyor
        if histogram > 0 && isAccelerating { return 0.45 }

        // Zayıf: pozitif ama düşüyor
        if histogram > 0 && !isAccelerating { return 0.20 }

        // Kötü: negatif ve düşüyor
        return 0.03
    }

    // MARK: - ═══════════════════════════════════════
    // FACTOR 8: Pattern Score (weight: 3)
    // Bullish mum formasyonları (hammer, engulfing, morning star vb.)
    // ═══════════════════════════════════════

    private static func scorePatterns(bullishPatternScore: Int) -> Double {
        switch bullishPatternScore {
        case 80...: return 1.00   // Morning Star / Three White Soldiers
        case 65...: return 0.80   // Bullish Engulfing
        case 50...: return 0.55   // Hammer / Piercing Line
        case 30...: return 0.30   // Harami / Inverted Hammer
        case 1...:  return 0.15   // Zayıf pattern
        default:    return 0      // Pattern yok
        }
    }

    // MARK: - ═══════════════════════════════════════
    // FACTOR 9: Volatility Edge (weight: 2)
    // ATR ve tarihsel hareket büyüklüğü. %5 hedefimize ulaşabilir mi?
    // ═══════════════════════════════════════

    private static func scoreVolatilityEdge(
        atrPct: Double,
        maxDailyReturn20: Double
    ) -> Double {
        // ── ATR potansiyeli ──
        var score = 0.0
        if atrPct >= 6.0 { score += 0.50 }      // Çok volatil
        else if atrPct >= 4.5 { score += 0.40 }  // İyi volatilite
        else if atrPct >= 3.5 { score += 0.30 }  // Orta
        else if atrPct >= 2.5 { score += 0.15 }  // Minimum

        // ── Son 20 günde kaç büyük hareket yapmış? ──
        if maxDailyReturn20 >= 8 { score += 0.50 }
        else if maxDailyReturn20 >= 5 { score += 0.40 }
        else if maxDailyReturn20 >= 3 { score += 0.25 }
        else { score += 0.10 }

        return min(1.0, score)
    }

    // MARK: - ═══════════════════════════════════════
    // SYNERGY: Faktörler birlikte güçlenir
    // ═══════════════════════════════════════

    private static func synergyAdjustment(
        s1: Double, // Momentum
        s2: Double, // Volume
        s3: Double, // Close
        s4: Double, // Trend
        s5: Double, // Pullback
        s6: Double  // Bollinger
    ) -> Double {
        var bonus: Double = 0

        // ── Triple Confluence: RSI bounce + Volume + Trend ──
        // 3 temel faktör aynı anda güçlü = çok yüksek olasılıklı setup
        if s1 >= 0.60 && s2 >= 0.55 && s4 >= 0.60 {
            bonus += 4.0
        }

        // ── Pullback + Bollinger: alt bandda geri çekilme ──
        if s5 >= 0.50 && s6 >= 0.55 {
            bonus += 2.5
        }

        // ── Volume + Close: hacimle güçlü kapanış ──
        if s2 >= 0.60 && s3 >= 0.65 {
            bonus += 2.0
        }

        // ── Tam setup: 5+ faktör güçlü ──
        let strongFactors = [s1, s2, s3, s4, s5, s6].filter { $0 >= 0.55 }.count
        if strongFactors >= 5 {
            bonus += 3.0
        }

        return min(8.0, bonus) // Max +8 puan
    }

    // MARK: - ═══════════════════════════════════════
    // REGIME: Piyasa rejimine göre eşik ayarı
    // ═══════════════════════════════════════

    private static func effectiveMinScore(
        base: Int,
        regime: MarketRegime,
        config: UltraStrategyConfig
    ) -> Int {
        let delta: Int
        switch regime {
        case .bull:     delta = config.regimeBullDelta
        case .sideways: delta = config.regimeSidewaysDelta
        case .bear:     delta = config.regimeBearDelta
        }
        return min(95, max(0, base + delta))
    }

    // MARK: - Helpers

    private static func liquidityTier(avgValue20: Double) -> LiquidityTier {
        if avgValue20 >= 50_000_000 { return .a }
        if avgValue20 >= 15_000_000 { return .b }
        if avgValue20 >= 5_000_000  { return .c }
        return .none
    }

    private static func qualityBand(total: Int, config: UltraStrategyConfig) -> String {
        switch total {
        case config.qualityS...:     return "S"
        case config.qualityAPlus...: return "A+"
        case config.qualityA...:     return "A"
        case config.qualityB...:     return "B"
        case config.qualityC...:     return "C"
        default:                     return "D"
        }
    }

    // MARK: - Dynamic Exit Calculator

    /// ATR-bazlı dinamik TP ve SL hesapla.
    /// Her hisseye özel: volatil hissede geniş, sakin hissede dar.
    static func calculateDynamicExits(
        candles: [Candle],
        config: UltraStrategyConfig = .hunter
    ) -> (tpPct: Double, slPct: Double, rrRatio: Double)? {
        guard let atr = ATR.lastValue(candles: candles),
              let lastClose = candles.last?.close, lastClose > 0 else { return nil }

        let atrPct = (atr / lastClose) * 100
        let tp = min(config.maxTPPct, max(config.minTPPct, atrPct * config.tpATRMultiple))
        let sl = min(config.maxSLPct, max(config.minSLPct, atrPct * config.slATRMultiple))
        let rr = sl > 0 ? tp / sl : 0

        return (tp, sl, rr)
    }
}

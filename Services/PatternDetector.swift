    //
    //  PatternDetector.swift
    //  BistScreener
    //
    //  Created by Sedat Pala on 18.02.2026.
    //

    import Foundation

    // MARK: - Patterns

enum CandlePattern: String, CaseIterable, Identifiable, Hashable, Codable {
    var id: String { rawValue }

        // Reversal / single
        case doji = "Doji"
        case hammer = "Hammer"
        case invertedHammer = "Inverted Hammer"
        case shootingStar = "Shooting Star"
        case hangingMan = "Hanging Man"

        // 2-candle
        case bullishEngulfing = "Bullish Engulfing"
        case bearishEngulfing = "Bearish Engulfing"
        case bullishHarami = "Bullish Harami"
        case bearishHarami = "Bearish Harami"
        case piercingLine = "Piercing Line"
        case darkCloudCover = "Dark Cloud Cover"

        // 3-candle
        case morningStar = "Morning Star"
        case eveningStar = "Evening Star"
        case threeWhiteSoldiers = "Three White Soldiers"
        case threeBlackCrows = "Three Black Crows"
    }

struct CandlePatternScore: Identifiable, Hashable, Codable {    
        let id: UUID
        let pattern: CandlePattern
        let score: Int

        init(id: UUID = UUID(), pattern: CandlePattern, score: Int) {
            self.id = id
            self.pattern = pattern
            self.score = score
        }
    }

    // MARK: - Detector

    struct PatternDetector {

        // Public: scored detection
        // Not: Buraya mümkünse "son 60-120 günlük" candle’ı ver.
        static func detectScored(last candles: [Candle]) -> [CandlePatternScore] {
            guard candles.count >= 20 else { return [] } // indikatörler için
            let c = candles.sorted { $0.date < $1.date }

            // Son barlar
            guard let last = c.last else { return [] }
            let prev = c[c.count - 2]

            // Context (trend/vol/volatility)
            let ctx = Context.make(from: c)

            var out: [CandlePatternScore] = []

            // --- Single-candle on last
            if isDoji(last, ctx: ctx) {
                out.append(score(.doji, base: 45, bias: .neutral, ctx: ctx, last: last, prev: prev, trio: nil))
            }
            if isHammer(last, ctx: ctx) {
                out.append(score(.hammer, base: 62, bias: .bullishReversal, ctx: ctx, last: last, prev: prev, trio: nil))
            }
            if isInvertedHammer(last, ctx: ctx) {
                out.append(score(.invertedHammer, base: 58, bias: .bullishReversal, ctx: ctx, last: last, prev: prev, trio: nil))
            }
            if isShootingStar(last, ctx: ctx) {
                out.append(score(.shootingStar, base: 60, bias: .bearishReversal, ctx: ctx, last: last, prev: prev, trio: nil))
            }
            if isHangingMan(last, ctx: ctx) {
                out.append(score(.hangingMan, base: 58, bias: .bearishReversal, ctx: ctx, last: last, prev: prev, trio: nil))
            }

            // --- 2-candle (prev + last)
            if isBullishEngulfing(prev: prev, last: last) {
                out.append(score(.bullishEngulfing, base: 72, bias: .bullishReversal, ctx: ctx, last: last, prev: prev, trio: nil))
            }
            if isBearishEngulfing(prev: prev, last: last) {
                out.append(score(.bearishEngulfing, base: 72, bias: .bearishReversal, ctx: ctx, last: last, prev: prev, trio: nil))
            }
            if isBullishHarami(prev: prev, last: last) {
                out.append(score(.bullishHarami, base: 60, bias: .bullishReversal, ctx: ctx, last: last, prev: prev, trio: nil))
            }
            if isBearishHarami(prev: prev, last: last) {
                out.append(score(.bearishHarami, base: 60, bias: .bearishReversal, ctx: ctx, last: last, prev: prev, trio: nil))
            }
            if isPiercingLine(prev: prev, last: last) {
                out.append(score(.piercingLine, base: 68, bias: .bullishReversal, ctx: ctx, last: last, prev: prev, trio: nil))
            }
            if isDarkCloudCover(prev: prev, last: last) {
                out.append(score(.darkCloudCover, base: 68, bias: .bearishReversal, ctx: ctx, last: last, prev: prev, trio: nil))
            }

            // --- 3-candle patterns (need 3)
            if c.count >= 3 {
                let a = c[c.count - 3]
                let b = c[c.count - 2]
                let d = c[c.count - 1]
                let trio = Trio(a: a, b: b, c: d)

                if isMorningStar(trio, ctx: ctx) {
                    out.append(score(.morningStar, base: 78, bias: .bullishReversal, ctx: ctx, last: d, prev: b, trio: trio))
                }
                if isEveningStar(trio, ctx: ctx) {
                    out.append(score(.eveningStar, base: 78, bias: .bearishReversal, ctx: ctx, last: d, prev: b, trio: trio))
                }
                if isThreeWhiteSoldiers(trio, ctx: ctx) {
                    out.append(score(.threeWhiteSoldiers, base: 80, bias: .bullishContinuation, ctx: ctx, last: d, prev: b, trio: trio))
                }
                if isThreeBlackCrows(trio, ctx: ctx) {
                    out.append(score(.threeBlackCrows, base: 80, bias: .bearishContinuation, ctx: ctx, last: d, prev: b, trio: trio))
                }
            }

            // Aynı pattern iki kere eklenmesin (nadir ama)
            var seen: Set<CandlePattern> = []
            let unique = out.filter { seen.insert($0.pattern).inserted }

            // Skoru büyükten küçüğe
            return unique.sorted { $0.score > $1.score }
        }
    }

    // MARK: - Scoring model

    private enum PatternBias {
        case bullishReversal
        case bearishReversal
        case bullishContinuation
        case bearishContinuation
        case neutral
    }

    private struct Trio {
        let a: Candle
        let b: Candle
        let c: Candle
    }

    private struct Context {
        let sma20: Double?
        let sma50: Double?
        let sma20Slope: Double?   // son 5 bar slope approx
        let rsi14: Double?
        let atr14: Double?
        let volSma20: Double?
        let lastClose: Double
        let lastVolume: Double

        enum Trend {
            case up, down, flat, unknown
        }
        let trend: Trend

        static func make(from candles: [Candle]) -> Context {
            let closes = candles.map(\.close)
            let vols = candles.map { Double($0.volume) }

            let sma20 = sma(closes, 20)
            let sma50 = sma(closes, 50)

            // slope: sma20 today - sma20 5 bars ago
            let sma20Now = sma(closes, 20, upto: closes.count)
            let sma20Prev = sma(closes, 20, upto: max(0, closes.count - 5))
            let slope = (sma20Now != nil && sma20Prev != nil) ? (sma20Now! - sma20Prev!) : nil

            let rsi = calcRSI14(closes)
            let atr = calcATR14(candles)
            let v20 = sma(vols, 20)

            let lastClose = closes.last ?? 0
            let lastVol = vols.last ?? 0

            let trend: Trend = {
                guard let s20 = sma20, let s50 = sma50, let sl = slope else { return .unknown }
                if s20 > s50 && sl > 0 { return .up }
                if s20 < s50 && sl < 0 { return .down }
                return .flat
            }()

            return Context(
                sma20: sma20,
                sma50: sma50,
                sma20Slope: slope,
                rsi14: rsi,
                atr14: atr,
                volSma20: v20,
                lastClose: lastClose,
                lastVolume: lastVol,
                trend: trend
            )
        }
    }

    private func score(_ pattern: CandlePattern,
                       base: Int,
                       bias: PatternBias,
                       ctx: Context,
                       last: Candle,
                       prev: Candle,
                       trio: Trio?) -> CandlePatternScore {

        var s = base

        // 1) Trend alignment (maks +18)
        s += trendAlignment(bias: bias, ctx: ctx)

        // 2) Volume confirmation (maks +12)
        s += volumeBoost(ctx: ctx)

        // 3) Candle quality: body vs ATR, close location (maks +12)
        s += qualityBoost(last: last, prev: prev, ctx: ctx, bias: bias)

        // 4) RSI context (maks +10)
        s += rsiBoost(ctx: ctx, bias: bias)

        // 5) Multi-candle patterns: “structure” boost (maks +8)
        if trio != nil {
            s += 6
        }

        // Clamp 0...100
        s = max(0, min(100, s))
        return CandlePatternScore(pattern: pattern, score: s)
    }

    private func trendAlignment(bias: PatternBias, ctx: Context) -> Int {
        switch bias {
        case .bullishReversal:
            // düşüşte daha değerli
            switch ctx.trend {
            case .down: return 18
            case .flat: return 10
            case .up:   return 4
            case .unknown: return 8
            }
        case .bearishReversal:
            // yükselişte daha değerli
            switch ctx.trend {
            case .up:   return 18
            case .flat: return 10
            case .down: return 4
            case .unknown: return 8
            }
        case .bullishContinuation:
            switch ctx.trend {
            case .up: return 16
            case .flat: return 8
            case .down: return 3
            case .unknown: return 7
            }
        case .bearishContinuation:
            switch ctx.trend {
            case .down: return 16
            case .flat: return 8
            case .up: return 3
            case .unknown: return 7
            }
        case .neutral:
            return 6
        }
    }

    private func volumeBoost(ctx: Context) -> Int {
        guard let v20 = ctx.volSma20, v20 > 0 else { return 0 }
        let ratio = ctx.lastVolume / v20

        if ratio >= 2.0 { return 12 }
        if ratio >= 1.5 { return 8 }
        if ratio >= 1.2 { return 5 }
        if ratio >= 1.0 { return 2 }
        return 0
    }

    private func qualityBoost(last: Candle, prev: Candle, ctx: Context, bias: PatternBias) -> Int {
        let range = max(last.high - last.low, 0.000001)
        let body = abs(last.close - last.open)
        let closePos = (last.close - last.low) / range // 0..1

        var q = 0

        // body relative to ATR
        if let atr = ctx.atr14, atr > 0 {
            let bodyToATR = body / atr
            if bodyToATR >= 0.9 { q += 6 }
            else if bodyToATR >= 0.6 { q += 4 }
            else if bodyToATR >= 0.35 { q += 2 }
        }

        // close location: bullish wants close near high; bearish wants close near low
        switch bias {
        case .bullishReversal, .bullishContinuation:
            if closePos >= 0.8 { q += 6 }
            else if closePos >= 0.65 { q += 4 }
            else if closePos >= 0.55 { q += 2 }
        case .bearishReversal, .bearishContinuation:
            if closePos <= 0.2 { q += 6 }
            else if closePos <= 0.35 { q += 4 }
            else if closePos <= 0.45 { q += 2 }
        case .neutral:
            if abs(closePos - 0.5) <= 0.15 { q += 2 }
        }

        // small penalty if last candle is tiny and also volume weak
        if body / range < 0.12, let v20 = ctx.volSma20, v20 > 0 {
            if ctx.lastVolume / v20 < 0.8 { q -= 2 }
        }

        return max(0, min(12, q))
    }

    private func rsiBoost(ctx: Context, bias: PatternBias) -> Int {
        guard let rsi = ctx.rsi14 else { return 0 }

        switch bias {
        case .bullishReversal:
            // oversold -> boost
            if rsi <= 25 { return 10 }
            if rsi <= 30 { return 7 }
            if rsi <= 35 { return 4 }
            return 0
        case .bearishReversal:
            // overbought -> boost
            if rsi >= 75 { return 10 }
            if rsi >= 70 { return 7 }
            if rsi >= 65 { return 4 }
            return 0
        case .bullishContinuation:
            // healthy uptrend zone
            if rsi >= 55 && rsi <= 70 { return 6 }
            return 0
        case .bearishContinuation:
            if rsi <= 45 && rsi >= 30 { return 6 }
            return 0
        case .neutral:
            return 0
        }
    }

    // MARK: - Pattern rules

    private func isDoji(_ c: Candle, ctx: Context) -> Bool {
        let range = max(c.high - c.low, 0.000001)
        let body = abs(c.close - c.open)
        return (body / range) <= 0.10
    }

    private func isHammer(_ c: Candle, ctx: Context) -> Bool {
        let range = max(c.high - c.low, 0.000001)
        let body = abs(c.close - c.open)
        let upperWick = c.high - max(c.open, c.close)
        let lowerWick = min(c.open, c.close) - c.low
        return (body / range <= 0.35) && (lowerWick >= body * 2.0) && (upperWick <= body * 0.9)
    }

    private func isInvertedHammer(_ c: Candle, ctx: Context) -> Bool {
        let range = max(c.high - c.low, 0.000001)
        let body = abs(c.close - c.open)
        let upperWick = c.high - max(c.open, c.close)
        let lowerWick = min(c.open, c.close) - c.low
        return (body / range <= 0.35) && (upperWick >= body * 2.0) && (lowerWick <= body * 0.9)
    }

    private func isShootingStar(_ c: Candle, ctx: Context) -> Bool {
        // inverted hammer ama bearish context: close genelde open'a yakın/altında
        let range = max(c.high - c.low, 0.000001)
        let body = abs(c.close - c.open)
        let upperWick = c.high - max(c.open, c.close)
        let lowerWick = min(c.open, c.close) - c.low
        return (body / range <= 0.35) && (upperWick >= body * 2.0) && (lowerWick <= body * 0.9)
    }

    private func isHangingMan(_ c: Candle, ctx: Context) -> Bool {
        // hammer benzeri ama yükseliş sonrası bearish sinyal
        return isHammer(c, ctx: ctx)
    }

    private func isBullishEngulfing(prev: Candle, last: Candle) -> Bool {
        let prevBear = prev.close < prev.open
        let lastBull = last.close > last.open
        guard prevBear && lastBull else { return false }

        let prevBodyLow = min(prev.open, prev.close)
        let prevBodyHigh = max(prev.open, prev.close)
        let lastBodyLow = min(last.open, last.close)
        let lastBodyHigh = max(last.open, last.close)

        return lastBodyLow <= prevBodyLow && lastBodyHigh >= prevBodyHigh
    }

    private func isBearishEngulfing(prev: Candle, last: Candle) -> Bool {
        let prevBull = prev.close > prev.open
        let lastBear = last.close < last.open
        guard prevBull && lastBear else { return false }

        let prevBodyLow = min(prev.open, prev.close)
        let prevBodyHigh = max(prev.open, prev.close)
        let lastBodyLow = min(last.open, last.close)
        let lastBodyHigh = max(last.open, last.close)

        return lastBodyLow <= prevBodyLow && lastBodyHigh >= prevBodyHigh
    }

    private func isBullishHarami(prev: Candle, last: Candle) -> Bool {
        let prevBear = prev.close < prev.open
        let lastBullOrSmall = last.close >= last.open // küçük de olabilir
        guard prevBear && lastBullOrSmall else { return false }

        let prevLow = min(prev.open, prev.close)
        let prevHigh = max(prev.open, prev.close)
        let lastLow = min(last.open, last.close)
        let lastHigh = max(last.open, last.close)

        // last body, prev body içinde
        return lastLow > prevLow && lastHigh < prevHigh
    }

    private func isBearishHarami(prev: Candle, last: Candle) -> Bool {
        let prevBull = prev.close > prev.open
        let lastBearOrSmall = last.close <= last.open
        guard prevBull && lastBearOrSmall else { return false }

        let prevLow = min(prev.open, prev.close)
        let prevHigh = max(prev.open, prev.close)
        let lastLow = min(last.open, last.close)
        let lastHigh = max(last.open, last.close)

        return lastLow > prevLow && lastHigh < prevHigh
    }

    private func isPiercingLine(prev: Candle, last: Candle) -> Bool {
        // Prev bearish, last bullish; last opens below prev low-ish and closes above mid of prev body
        let prevBear = prev.close < prev.open
        let lastBull = last.close > last.open
        guard prevBear && lastBull else { return false }

        let prevMid = (prev.open + prev.close) / 2.0
        return last.open < prev.close && last.close > prevMid && last.close < prev.open
    }

    private func isDarkCloudCover(prev: Candle, last: Candle) -> Bool {
        let prevBull = prev.close > prev.open
        let lastBear = last.close < last.open
        guard prevBull && lastBear else { return false }

        let prevMid = (prev.open + prev.close) / 2.0
        return last.open > prev.close && last.close < prevMid && last.close > prev.open
    }

    // 3-candle
    private func isMorningStar(_ t: Trio, ctx: Context) -> Bool {
        let aBear = t.a.close < t.a.open
        let cBull = t.c.close > t.c.open
        guard aBear && cBull else { return false }

        let aBody = abs(t.a.close - t.a.open)
        let bBody = abs(t.b.close - t.b.open)
        let cBody = abs(t.c.close - t.c.open)

        // middle small
        guard bBody <= aBody * 0.5 else { return false }
        // final candle recovers into first candle body
        let aMid = (t.a.open + t.a.close) / 2.0
        return t.c.close >= aMid && cBody >= bBody
    }

    private func isEveningStar(_ t: Trio, ctx: Context) -> Bool {
        let aBull = t.a.close > t.a.open
        let cBear = t.c.close < t.c.open
        guard aBull && cBear else { return false }

        let aBody = abs(t.a.close - t.a.open)
        let bBody = abs(t.b.close - t.b.open)
        let cBody = abs(t.c.close - t.c.open)

        guard bBody <= aBody * 0.5 else { return false }
        let aMid = (t.a.open + t.a.close) / 2.0
        return t.c.close <= aMid && cBody >= bBody
    }

    private func isThreeWhiteSoldiers(_ t: Trio, ctx: Context) -> Bool {
        // 3 ardışık bullish, higher closes
        guard t.a.close > t.a.open, t.b.close > t.b.open, t.c.close > t.c.open else { return false }
        guard t.b.close > t.a.close, t.c.close > t.b.close else { return false }

        // opens should be within previous body (ideal)
        let aLow = min(t.a.open, t.a.close), aHigh = max(t.a.open, t.a.close)
        let bLow = min(t.b.open, t.b.close), bHigh = max(t.b.open, t.b.close)
        let cLow = min(t.c.open, t.c.close)

        return (t.b.open >= aLow && t.b.open <= aHigh) &&
               (t.c.open >= bLow && t.c.open <= bHigh) &&
               (t.c.close > t.c.open) &&
               (cLow <= t.b.close)
    }

    private func isThreeBlackCrows(_ t: Trio, ctx: Context) -> Bool {
        guard t.a.close < t.a.open, t.b.close < t.b.open, t.c.close < t.c.open else { return false }
        guard t.b.close < t.a.close, t.c.close < t.b.close else { return false }

        let aLow = min(t.a.open, t.a.close), aHigh = max(t.a.open, t.a.close)
        let bLow = min(t.b.open, t.b.close), bHigh = max(t.b.open, t.b.close)

        return (t.b.open >= aLow && t.b.open <= aHigh) &&
               (t.c.open >= bLow && t.c.open <= bHigh)
    }

    // MARK: - Indicators (SMA / RSI / ATR)

    private func sma(_ arr: [Double], _ period: Int) -> Double? {
        sma(arr, period, upto: arr.count)
    }

    // upto: first `upto` elements
    private func sma(_ arr: [Double], _ period: Int, upto: Int) -> Double? {
        guard period > 0 else { return nil }
        guard upto >= period else { return nil }
        let end = min(upto, arr.count)
        let start = end - period
        guard start >= 0 else { return nil }
        let slice = arr[start..<end]
        let sum = slice.reduce(0, +)
        return sum / Double(period)
    }

    private func calcRSI14(_ closes: [Double]) -> Double? {
        let period = 14
        guard closes.count >= period + 1 else { return nil }

        var gains: Double = 0
        var losses: Double = 0

        // initial avg
        for i in (closes.count - period)..<closes.count {
            let diff = closes[i] - closes[i - 1]
            if diff >= 0 { gains += diff } else { losses += abs(diff) }
        }

        let avgGain = gains / Double(period)
        let avgLoss = losses / Double(period)

        if avgLoss == 0 { return 100 }
        let rs = avgGain / avgLoss
        return 100 - (100 / (1 + rs))
    }

    private func calcATR14(_ candles: [Candle]) -> Double? {
        let period = 14
        guard candles.count >= period + 1 else { return nil }

        var trs: [Double] = []
        trs.reserveCapacity(period)

        let start = candles.count - period
        for i in start..<candles.count {
            let cur = candles[i]
            let prev = candles[i - 1]
            let tr1 = cur.high - cur.low
            let tr2 = abs(cur.high - prev.close)
            let tr3 = abs(cur.low - prev.close)
            let tr = max(tr1, max(tr2, tr3))
            trs.append(tr)
        }

        return trs.reduce(0, +) / Double(period)
    }

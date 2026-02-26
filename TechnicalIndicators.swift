//
//  TechnicalIndicators.swift
//  BistScreener
//
//  Created by Sedat Pala on 23.02.2026.
//

import Foundation

// MARK: - RSI

enum RSI {

    /// Hesaplar; yeterli veri yoksa nil döner.
    static func calculate(closes: [Double], period: Int = 14) -> [Double?] {
        guard period > 0 else { return Array(repeating: nil, count: closes.count) }
        guard closes.count > period else {
            return Array(repeating: nil, count: closes.count)
        }

        var result: [Double?] = Array(repeating: nil, count: period)

        // İlk ortalamalar (Wilder)
        var gains: Double = 0
        var losses: Double = 0
        for i in 1...period {
            let diff = closes[i] - closes[i - 1]
            if diff > 0 { gains += diff } else { losses += abs(diff) }
        }

        var avgGain = gains / Double(period)
        var avgLoss = losses / Double(period)

        // ✅ Edge cases
        let firstRSI: Double
        if avgLoss == 0, avgGain == 0 {
            firstRSI = 50
        } else if avgLoss == 0 {
            firstRSI = 100
        } else if avgGain == 0 {
            firstRSI = 0
        } else {
            let rs = avgGain / avgLoss
            firstRSI = 100 - (100 / (1 + rs))
        }
        result.append(firstRSI)

        // Wilder smoothing
        if closes.count >= period + 2 {
            for i in (period + 1)..<closes.count {
                let diff = closes[i] - closes[i - 1]
                let gain = max(diff, 0)
                let loss = max(-diff, 0)

                avgGain = (avgGain * Double(period - 1) + gain) / Double(period)
                avgLoss = (avgLoss * Double(period - 1) + loss) / Double(period)

                let rsi: Double
                if avgLoss == 0, avgGain == 0 {
                    rsi = 50
                } else if avgLoss == 0 {
                    rsi = 100
                } else if avgGain == 0 {
                    rsi = 0
                } else {
                    let rs = avgGain / avgLoss
                    rsi = 100 - (100 / (1 + rs))
                }
                result.append(rsi)
            }
        }

        return result
    }

    static func lastValue(closes: [Double], period: Int = 14) -> Double? {
        calculate(closes: closes, period: period).last ?? nil
    }

    /// RSI sinyali: 0-100 arasında normalize edilmiş skor
    static func signalScore(rsi: Double) -> (score: Int, label: String) {
        switch rsi {
        case ..<25:  return (95, "Aşırı Satım 🔥")
        case ..<35:  return (80, "Güçlü Alım Bölgesi")
        case ..<45:  return (60, "Alım Yaklaşıyor")
        case ..<55:  return (40, "Nötr")
        case ..<65:  return (20, "Satım Yaklaşıyor")
        case ..<75:  return (10, "Satım Bölgesi")
        default:     return (5,  "Aşırı Alım ⚠️")
        }
    }
}

// MARK: - EMA

enum EMA {
    static func calculate(values: [Double], period: Int) -> [Double?] {
        guard period > 0, values.count >= period else {
            return Array(repeating: nil, count: values.count)
        }
        let k = 2.0 / Double(period + 1)
        var result: [Double?] = Array(repeating: nil, count: period - 1)
        let firstSMA = values.prefix(period).reduce(0, +) / Double(period)
        result.append(firstSMA)

        var prev = firstSMA
        for i in period..<values.count {
            let ema = values[i] * k + prev * (1 - k)
            result.append(ema)
            prev = ema
        }
        return result
    }

    static func lastValue(values: [Double], period: Int) -> Double? {
        calculate(values: values, period: period).compactMap { $0 }.last
    }
}

// MARK: - MACD

struct MACDResult {
    let macdLine: [Double?]
    let signalLine: [Double?]
    let histogram: [Double?]
}

enum MACD {
    static func calculate(
        closes: [Double],
        fast: Int = 12,
        slow: Int = 26,
        signal: Int = 9
    ) -> MACDResult {

        let fastEMA  = EMA.calculate(values: closes, period: fast)
        let slowEMA  = EMA.calculate(values: closes, period: slow)

        let macdLine: [Double?] = zip(fastEMA, slowEMA).map { (f, s) in
            guard let f, let s else { return nil }
            return f - s
        }

        let macdValues = macdLine.compactMap { $0 }
        let rawSignal  = EMA.calculate(values: macdValues, period: signal)

        // Signal ve histogram'ı macdLine uzunluğuna pad et
        let offset = macdLine.count - rawSignal.count
        let signalLine: [Double?] = Array(repeating: nil, count: max(0, offset)) + rawSignal

        let histogram: [Double?] = zip(macdLine, signalLine).map { (m, s) in
            guard let m, let s else { return nil }
            return m - s
        }

        return MACDResult(macdLine: macdLine, signalLine: signalLine, histogram: histogram)
    }

    /// Sinyal: son histogram değeri ve öncekiyle kıyasla
    static func signalScore(result: MACDResult) -> (score: Int, label: String) {
        let hists = result.histogram.compactMap { $0 }
        guard hists.count >= 2 else { return (50, "Yetersiz Veri") }
        let last = hists[hists.count - 1]
        let prev = hists[hists.count - 2]

        if last > 0 && last > prev { return (90, "MACD Boğa Momentum") }
        if last > 0 && last <= prev { return (70, "MACD Pozitif Zayıflıyor") }
        if last < 0 && last > prev  { return (55, "MACD Dip Arıyor") }
        return (20, "MACD Ayı Momentum")
    }
}

// MARK: - Bollinger Bands

struct BollingerResult {
    let upper: [Double?]
    let middle: [Double?]
    let lower: [Double?]
}

enum BollingerBands {

    static func calculate(
        closes: [Double],
        period: Int = 20,
        stdMult: Double = 2.0
    ) -> BollingerResult {

        var upper:  [Double?] = []
        var middle: [Double?] = []
        var lower:  [Double?] = []

        for i in 0..<closes.count {
            guard i >= period - 1 else {
                upper.append(nil); middle.append(nil); lower.append(nil); continue
            }
            let slice = Array(closes[(i - period + 1)...i])
            let sma = slice.reduce(0, +) / Double(period)
            let variance = slice.map { pow($0 - sma, 2) }.reduce(0, +) / Double(period)
            let std = sqrt(variance)

            upper.append(sma + stdMult * std)
            middle.append(sma)
            lower.append(sma - stdMult * std)
        }

        return BollingerResult(upper: upper, middle: middle, lower: lower)
    }

    /// %B = (Close - Lower) / (Upper - Lower), 0..1
    static func percentB(
        closes: [Double],
        period: Int = 20,
        stdMult: Double = 2.0
    ) -> Double? {

        guard let close = closes.last else { return nil }
        let bb = calculate(closes: closes, period: period, stdMult: stdMult)

        // ✅ Double?? -> Double
        guard let u = bb.upper.last.flatMap({ $0 }),
              let l = bb.lower.last.flatMap({ $0 }) else { return nil }

        let range = u - l
        return range == 0 ? 0.5 : (close - l) / range
    }

    static func signalScore(percentB: Double) -> (score: Int, label: String) {
        switch percentB {
        case ..<0.05: return (95, "BB Alt Bant Kırma 🔥")
        case ..<0.20: return (80, "BB Alt Bölge")
        case ..<0.40: return (60, "BB Alt-Orta")
        case ..<0.60: return (40, "BB Orta Bölge")
        case ..<0.80: return (20, "BB Üst-Orta")
        default:      return (5,  "BB Üst Bant ⚠️")
        }
    }
}

// MARK: - Volume Analysis

enum VolumeAnalysis {

    /// Hacim ortalaması ve son hacmin oranı
    static func relativeVolume(volumes: [Double], period: Int = 20) -> Double? {
        guard volumes.count >= period + 1 else { return nil }
        let recent = Array(volumes.suffix(period + 1))
        let avg = Array(recent.dropLast()).reduce(0, +) / Double(period)
        guard avg > 0, let last = recent.last else { return nil }
        return last / avg
    }

    /// On Balance Volume (OBV)
    static func obv(closes: [Double], volumes: [Double]) -> [Double] {
        guard closes.count == volumes.count, !closes.isEmpty else { return [] }
        var result: [Double] = [volumes[0]]
        for i in 1..<closes.count {
            let prev = result[i - 1]
            if closes[i] > closes[i - 1] {
                result.append(prev + volumes[i])
            } else if closes[i] < closes[i - 1] {
                result.append(prev - volumes[i])
            } else {
                result.append(prev)
            }
        }
        return result
    }

    static func signalScore(relVol: Double) -> (score: Int, label: String) {
        switch relVol {
        case 3...:   return (95, "Patlama Hacmi 🚀")
        case 2...:   return (80, "Yüksek Hacim")
        case 1.5...: return (65, "Ortalamanın Üstü")
        case 0.8...: return (50, "Normal Hacim")
        default:     return (20, "Düşük Hacim")
        }
    }
}

// MARK: - ATR (Average True Range)

enum ATR {

    static func calculate(candles: [Candle], period: Int = 14) -> [Double?] {
        guard period > 0 else { return Array(repeating: nil, count: candles.count) }
        guard candles.count > 1 else { return Array(repeating: nil, count: candles.count) }

        var trList: [Double] = [candles[0].high - candles[0].low]
        for i in 1..<candles.count {
            let high = candles[i].high
            let low  = candles[i].low
            let prevClose = candles[i - 1].close
            let tr = max(high - low, abs(high - prevClose), abs(low - prevClose))
            trList.append(tr)
        }

        guard trList.count >= period else {
            return Array(repeating: nil, count: candles.count)
        }

        var result: [Double?] = Array(repeating: nil, count: period - 1)
        let firstATR = trList.prefix(period).reduce(0, +) / Double(period)
        result.append(firstATR)

        var prev = firstATR
        for i in period..<trList.count {
            let atr = (prev * Double(period - 1) + trList[i]) / Double(period)
            result.append(atr)
            prev = atr
        }
        return result
    }

    static func lastValue(candles: [Candle], period: Int = 14) -> Double? {
        calculate(candles: candles, period: period).compactMap { $0 }.last
    }

    /// Volatilite skoru: ATR/Close oranı
    static func volatilityRatio(candles: [Candle], period: Int = 14) -> Double? {
        guard let atr = lastValue(candles: candles, period: period),
              let lastClose = candles.last?.close, lastClose > 0 else { return nil }
        return atr / lastClose
    }
}

// MARK: - ADX (Average Directional Index)

enum ADX {

    /// ADX: Trend gücünü ölçer (yön bağımsız).
    /// ADX > 25 = güçlü trend, ADX < 20 = zayıf/yatay piyasa.
    /// Wilder'ın orijinal hesaplaması kullanılır.
    static func calculate(candles: [Candle], period: Int = 14) -> [Double?] {
        guard period > 0, candles.count > period * 2 + 1 else {
            return Array(repeating: nil, count: candles.count)
        }

        // Step 1: +DM, -DM, TR hesapla
        var plusDMs: [Double] = [0]
        var minusDMs: [Double] = [0]
        var trList: [Double] = [candles[0].high - candles[0].low]

        for i in 1..<candles.count {
            let highDiff = candles[i].high - candles[i - 1].high
            let lowDiff = candles[i - 1].low - candles[i].low

            let plusDM = (highDiff > lowDiff && highDiff > 0) ? highDiff : 0
            let minusDM = (lowDiff > highDiff && lowDiff > 0) ? lowDiff : 0

            plusDMs.append(plusDM)
            minusDMs.append(minusDM)

            let tr = max(
                candles[i].high - candles[i].low,
                abs(candles[i].high - candles[i - 1].close),
                abs(candles[i].low - candles[i - 1].close)
            )
            trList.append(tr)
        }

        guard plusDMs.count > period else {
            return Array(repeating: nil, count: candles.count)
        }

        // Step 2: Wilder smoothing → +DI, -DI, DX
        var smoothPlusDM = plusDMs[1...period].reduce(0, +)
        var smoothMinusDM = minusDMs[1...period].reduce(0, +)
        var smoothTR = trList[1...period].reduce(0, +)

        var dxValues: [Double] = []

        for i in period..<candles.count {
            if i > period {
                smoothPlusDM = smoothPlusDM - (smoothPlusDM / Double(period)) + plusDMs[i]
                smoothMinusDM = smoothMinusDM - (smoothMinusDM / Double(period)) + minusDMs[i]
                smoothTR = smoothTR - (smoothTR / Double(period)) + trList[i]
            }

            let plusDI = smoothTR > 0 ? (smoothPlusDM / smoothTR) * 100 : 0
            let minusDI = smoothTR > 0 ? (smoothMinusDM / smoothTR) * 100 : 0
            let diSum = plusDI + minusDI
            let dx = diSum > 0 ? (abs(plusDI - minusDI) / diSum) * 100 : 0
            dxValues.append(dx)
        }

        // Step 3: DX → ADX (Wilder smoothing)
        guard dxValues.count >= period else {
            return Array(repeating: nil, count: candles.count)
        }

        var result: [Double?] = Array(repeating: nil, count: candles.count)
        var adx = dxValues[0..<period].reduce(0, +) / Double(period)

        let firstADXIdx = period * 2
        if firstADXIdx < candles.count {
            result[firstADXIdx] = adx
        }

        for i in period..<dxValues.count {
            adx = (adx * Double(period - 1) + dxValues[i]) / Double(period)
            let candleIdx = period + i
            if candleIdx < candles.count {
                result[candleIdx] = adx
            }
        }

        return result
    }

    static func lastValue(candles: [Candle], period: Int = 14) -> Double? {
        calculate(candles: candles, period: period).compactMap { $0 }.last
    }

    static func signalScore(adx: Double) -> (score: Int, label: String) {
        switch adx {
        case 40...: return (90, "Çok Güçlü Trend")
        case 30...: return (75, "Güçlü Trend")
        case 25...: return (60, "Trend Var")
        case 20...: return (40, "Zayıf Trend")
        default:    return (15, "Trend Yok")
        }
    }
}

// MARK: - EMA Crossover

enum EMACrossover {

    struct CrossResult {
        let fast: Double?
        let slow: Double?
        let isGoldenCross: Bool   // fast > slow (bullish)
        let isMomentumUp: Bool    // fast ema hızlanıyor
    }

    static func analyze(closes: [Double], fast: Int = 9, slow: Int = 21) -> CrossResult {
        let fastEMA = EMA.calculate(values: closes, period: fast)
        let slowEMA = EMA.calculate(values: closes, period: slow)

        let fCompact = fastEMA.compactMap { $0 }
        let sCompact = slowEMA.compactMap { $0 }

        let fLast = fCompact.last
        let sLast = sCompact.last
        let fPrev = fCompact.dropLast().last

        let isGolden = (fLast ?? 0) > (sLast ?? 0)
        let isMomUp  = (fLast ?? 0) > (fPrev ?? 0)

        return CrossResult(fast: fLast, slow: sLast,
                           isGoldenCross: isGolden, isMomentumUp: isMomUp)
    }

    static func signalScore(result: CrossResult) -> (score: Int, label: String) {
        switch (result.isGoldenCross, result.isMomentumUp) {
        case (true, true):   return (90, "EMA Golden Cross + Momentum ⬆️")
        case (true, false):  return (60, "EMA Pozitif Ama Yavaşlıyor")
        case (false, true):  return (35, "EMA Negatif Ama Toparlanıyor")
        case (false, false): return (10, "EMA Death Cross ⬇️")
        }
    }
}

// MARK: - Tomorrow Strategy Utilities (BUY-only)

// ✅ Kapanışın gün içindeki konumu (0..1)
enum CLV {
    static func value(candle: Candle) -> Double? {
        let range = candle.high - candle.low
        guard range > 0 else { return nil }
        return (candle.close - candle.low) / range
    }
}

// ✅ True Range serisi (expansion için)
enum TrueRange {
    static func calculate(candles: [Candle]) -> [Double] {
        guard candles.count > 0 else { return [] }
        if candles.count == 1 { return [candles[0].high - candles[0].low] }

        var tr: [Double] = []
        tr.reserveCapacity(candles.count)
        tr.append(candles[0].high - candles[0].low)

        for i in 1..<candles.count {
            let h = candles[i].high
            let l = candles[i].low
            let pc = candles[i - 1].close
            tr.append(max(h - l, abs(h - pc), abs(l - pc)))
        }
        return tr
    }
}

// ✅ Rolling utilities (median/avg/highest)
enum Stats {

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 1 {
            return sorted[mid]
        } else {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
    }

    static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

enum Rolling {

    /// Son `window` barın median'ı
    static func medianLast(_ values: [Double], window: Int) -> Double? {
        guard window > 0, values.count >= window else { return nil }
        let slice = Array(values.suffix(window))
        return Stats.median(slice)
    }

    /// Son `period` barın ortalaması
    static func averageLast(_ values: [Double], period: Int) -> Double? {
        guard period > 0, values.count >= period else { return nil }
        let slice = Array(values.suffix(period))
        return Stats.average(slice)
    }

    /// Son `lookback` bar içindeki en yüksek değer (inclusive)
    static func highestLast(_ values: [Double], lookback: Int) -> Double? {
        guard lookback > 0, values.count >= lookback else { return nil }
        return values.suffix(lookback).max()
    }
}

// ✅ Close/High serilerinden breakout seviyeleri
enum BreakoutLevels {

    static func highestClose(closes: [Double], lookback: Int = 20) -> Double? {
        Rolling.highestLast(closes, lookback: lookback)
    }

    static func highestHigh(highs: [Double], lookback: Int = 20) -> Double? {
        Rolling.highestLast(highs, lookback: lookback)
    }
}

// ✅ TL bazlı işlem değeri: volume * close
enum ValueSeries {

    static func calculate(closes: [Double], volumes: [Double]) -> [Double] {
        guard closes.count == volumes.count else { return [] }
        var out: [Double] = []
        out.reserveCapacity(closes.count)
        for i in 0..<closes.count {
            out.append(closes[i] * volumes[i])
        }
        return out
    }

    /// Son gün Value / AvgValue(period)
    static func lastMultiple(closes: [Double], volumes: [Double], period: Int = 20) -> Double? {
        let values = calculate(closes: closes, volumes: volumes)
        guard values.count >= period + 1 else { return nil }

        let recent = Array(values.suffix(period + 1))
        let avg = Array(recent.dropLast()).reduce(0, +) / Double(period)
        guard avg > 0, let last = recent.last else { return nil }
        return last / avg
    }

    /// AvgValue20 (Tier hesaplamak için)
    static func averageValue(closes: [Double], volumes: [Double], period: Int = 20) -> Double? {
        let values = calculate(closes: closes, volumes: volumes)
        return Rolling.averageLast(values, period: period)
    }
}

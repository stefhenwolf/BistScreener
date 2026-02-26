import Foundation

enum MarketRegime {
    case bull
    case bear
    case sideways

    var title: String {
        switch self {
        case .bull: return "Bull"
        case .bear: return "Bear"
        case .sideways: return "Sideways"
        }
    }
}

struct MarketRegimeDetector {

    static func detect(from candles: [Candle]) -> MarketRegime {

        let closes = candles.map(\.close)

        // 200 mum yoksa da rejim tahmini üretmek için daha kısa EMA setiyle devam et.
        guard closes.count >= 60 else {
            return .sideways
        }

        let slowPeriod = closes.count >= 200 ? 200 : 50
        let fastPeriod = closes.count >= 200 ? 50 : 20

        let fastArray = EMA.calculate(values: closes, period: fastPeriod)
        let slowArray = EMA.calculate(values: closes, period: slowPeriod)

        guard
            let fastOpt = fastArray.last,
            let fast = fastOpt,
            let slowOpt = slowArray.last,
            let slow = slowOpt
        else {
            return .sideways
        }

        let rsi = RSI.lastValue(closes: closes) ?? 50

        // ✅ Yeni filtreler: ADX + volatilite
        // ADX düşükse trend zayıf kabul et (yan piyasa).
        let adx = ADX.lastValue(candles: candles) ?? 20

        // ATR/Close yüzdesi: anormal volatiliteyi rejim sınıflamasında filtrelemek için.
        let atrPct = (ATR.volatilityRatio(candles: candles) ?? 0) * 100

        // Trend gücü çok düşükse direkt yatay.
        if adx < 16 {
            return .sideways
        }

        // Aşırı oynak ama trend gücü yeterince net değilse yatay/karmaşa kabul et.
        if atrPct >= 7.5 && adx < 22 {
            return .sideways
        }

        // Aşırı şok volatilite dönemlerinde yanlış bull/bear etiketinden kaçın.
        if atrPct >= 9.5 {
            return .sideways
        }

        if fast > slow && rsi > 52 && adx >= 20 {
            return .bull
        } else if fast < slow && rsi < 48 && adx >= 20 {
            return .bear
        } else {
            return .sideways
        }
    }
}

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

        if fast > slow && rsi > 52 {
            return .bull
        } else if fast < slow && rsi < 48 {
            return .bear
        } else {
            return .sideways
        }
    }
}

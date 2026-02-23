import Foundation

enum MarketRegime {
    case bull
    case bear
    case sideways
}

struct MarketRegimeDetector {

    static func detect(from candles: [Candle]) -> MarketRegime {

        let closes = candles.map(\.close)

        guard closes.count >= 200 else {
            return .sideways
        }

        let ema50Array = EMA.calculate(values: closes, period: 50)
        let ema200Array = EMA.calculate(values: closes, period: 200)

        guard
            let ema50Opt = ema50Array.last,
            let ema50 = ema50Opt,
            let ema200Opt = ema200Array.last,
            let ema200 = ema200Opt
        else {
            return .sideways
        }

        let rsi = RSI.lastValue(closes: closes) ?? 50

        if ema50 > ema200 && rsi > 50 {
            return .bull
        } else if ema50 < ema200 && rsi < 50 {
            return .bear
        } else {
            return .sideways
        }
    }
}

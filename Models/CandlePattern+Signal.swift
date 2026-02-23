import Foundation

// MARK: - Pattern Direction

enum PatternDirection: String, Codable, Hashable {
    case bullish
    case bearish
    case neutral
}

// MARK: - CandlePattern -> direction
// Not: isBullish/isBearish zaten projede tanımlı olduğu için burada tekrar tanımlamıyoruz.

extension CandlePattern {
    var direction: PatternDirection {
        if isBullish { return .bullish }
        if isBearish { return .bearish }
        return .neutral
    }
}

// MARK: - ScanResult tarafında kullanılan sinyal sınıfı

enum SignalSide: String, Codable, Hashable {
    case bullish
    case bearish
    case neutral
}

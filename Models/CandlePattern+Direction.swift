import Foundation

extension CandlePattern {
    var isBullish: Bool {
        switch self {
        case .bullishEngulfing, .bullishHarami, .piercingLine,
             .morningStar, .threeWhiteSoldiers,
             .hammer, .invertedHammer:
            return true
        default:
            return false
        }
    }

    var isBearish: Bool {
        switch self {
        case .bearishEngulfing, .bearishHarami, .darkCloudCover,
             .eveningStar, .threeBlackCrows,
             .shootingStar, .hangingMan:
            return true
        default:
            return false
        }
    }
}

import Foundation

extension ScanResult {

    /// Eğer projende zaten signalSide benzeri bir şey varsa çakışmasın diye adını farklı verdim:
    func computedSignalSide(threshold: Int = 12) -> SignalSide {
        // bullishScore / bearishScore / biasScore zaten sende mevcut olduğu için onları kullanıyoruz.
        let b = biasScore
        if b >= threshold { return .bullish }
        if b <= -threshold { return .bearish }
        return .neutral
    }

    /// Info sayfasında “gerçek örnek” göstermek için paket
    struct ScoringBreakdown: Hashable {
        let totalScore: Int
        let bullishScore: Int
        let bearishScore: Int
        let biasScore: Int
        let signal: SignalSide
        let patternCount: Int
    }

    func breakdown(threshold: Int = 12) -> ScoringBreakdown {
        .init(
            totalScore: totalScore,
            bullishScore: bullishScore,
            bearishScore: bearishScore,
            biasScore: biasScore,
            signal: computedSignalSide(threshold: threshold),
            patternCount: patternCount
        )
    }
}

import Foundation

struct ScanResult: Identifiable, Codable, Hashable {

    // MARK: - Core

    let id: UUID
    let symbol: String
    let lastDate: Date
    let lastClose: Double
    let changePct: Double

    let patterns: [CandlePatternScore]

    // MARK: - Legacy Snapshot (geriye uyumlu)

    /// ✅ Eski birleşik skor (legacy SignalScorer)
    let signalTotal: Int?
    let signalDirection: Int?
    let signalQuality: Int?
    let signalConfidence: Int?
    let signal: TradeSignal?
    var breakdown: SignalBreakdown?

    // MARK: - Tomorrow BUY-only Snapshot (v1.0)

    /// ✅ Yeni strateji: sadece BUY için üretilir (nil değilse BUY adayıdır)
    let tomorrowTotal: Int?
    let tomorrowQuality: String?          // "A+" "A" "B" "C" "D"
    let tomorrowTier: LiquidityTier?      // .a/.b/.c
    let tomorrowReasons: [String]?        // max 3 chip
    var tomorrowBreakdown: TomorrowBreakdown?

    // MARK: - Hash/Equatable

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: ScanResult, rhs: ScanResult) -> Bool { lhs.id == rhs.id }

    // MARK: - Computed (Patterns)

    var totalScore: Int { patterns.reduce(0) { $0 + $1.score } }
    var patternCount: Int { patterns.count }

    var bullishScore: Int {
        patterns
            .filter { $0.pattern.direction == .bullish }
            .map(\.score)
            .reduce(0, +)
    }

    var bearishScore: Int {
        patterns
            .filter { $0.pattern.direction == .bearish }
            .map(\.score)
            .reduce(0, +)
    }

    /// bullish - bearish
    var biasScore: Int { bullishScore - bearishScore }

    // MARK: - UI (BUY-only öncelik)

    /// UI'da gösterilecek skor: öncelik Tomorrow. Yoksa legacy. Yoksa patterns clip.
    var uiScore: Int {
        if let t = tomorrowTotal { return t }
        if let t = signalTotal { return t }
        return min(max(totalScore, 0), 100)
    }

    /// UI'da tek aksiyon: Tomorrow varsa BUY, yoksa legacy/fallback.
    var uiSignal: TradeSignal {
        if tomorrowTotal != nil { return .buy }
        return signal ?? tradeSignal(using: .default)
    }

    /// UI kalite etiketi: Tomorrow varsa onun bandı, yoksa legacy numeric map, yoksa patterns'tan
    var uiQuality: String {
        if let q = tomorrowQuality { return q }

        if let qn = signalQuality {
            // legacy: 0..100 gibi düşün (senin eski kullanımına göre)
            switch qn {
            case 90...: return "A+"
            case 82...: return "A"
            case 74...: return "B"
            case 66...: return "C"
            default:    return "D"
            }
        }

        // patterns fallback: uiScore band
        switch uiScore {
        case 90...: return "A+"
        case 82...: return "A"
        case 74...: return "B"
        case 66...: return "C"
        default:    return "D"
        }
    }

    /// UI Tier etiketi
    var uiTierText: String? {
        guard let t = tomorrowTier else { return nil }
        switch t {
        case .a: return "Tier A"
        case .b: return "Tier B"
        case .c: return "Tier C"
        case .none: return nil
        }
    }

    /// Scan row alt satır meta (Tier • CLV • Value x • Breakout)
    var uiMetaLine: String? {
        guard let bd = tomorrowBreakdown else { return nil }
        let tier = uiTierText ?? ""
        let clv = String(format: "CLV %.2f", bd.clv)
        let vx  = String(format: "Value x%.2f", bd.valueMultiple)

        // breakout text (tier’e göre close/ high)
        let btxt: String
        if let t = tomorrowTier, t == .c {
            btxt = "Breakout \(bd.lookback)d High"
        } else {
            btxt = "Breakout \(bd.lookback)d Close"
        }

        let parts = [tier, clv, vx, btxt].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    /// BUY-only mi? (scan listesinde sadece bunu göstereceğiz)
    var isTomorrowBuy: Bool { tomorrowTotal != nil }

    // MARK: - SignalSide (optional legacy)

    func signalSide(using cfg: ScanScoringConfig = .default) -> SignalSide {
        let b = biasScore
        if b >= cfg.neutralBias { return .bullish }
        if b <= -cfg.neutralBias { return .bearish }
        return .neutral
    }

    // MARK: - Trade Signal (legacy fallback)

    /// Yön: biasScore (bullish - bearish)
    /// Güç: totalScore
    func tradeSignal(using cfg: ScanScoringConfig = .default) -> TradeSignal {
        let b = biasScore
        let t = totalScore

        if b >= cfg.strongBias && t >= cfg.strongTotal { return .strongBuy }
        if b <= -cfg.strongBias && t >= cfg.strongTotal { return .strongSell }

        if b >= cfg.bias && t >= cfg.total { return .buy }
        if b <= -cfg.bias && t >= cfg.total { return .sell }

        return .hold
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        symbol: String,
        lastDate: Date,
        lastClose: Double,
        changePct: Double,
        patterns: [CandlePatternScore],

        // legacy snapshot
        signalTotal: Int? = nil,
        signalDirection: Int? = nil,
        signalQuality: Int? = nil,
        signalConfidence: Int? = nil,
        signal: TradeSignal? = nil,
        breakdown: SignalBreakdown? = nil,

        // tomorrow snapshot
        tomorrowTotal: Int? = nil,
        tomorrowQuality: String? = nil,
        tomorrowTier: LiquidityTier? = nil,
        tomorrowReasons: [String]? = nil,
        tomorrowBreakdown: TomorrowBreakdown? = nil
    ) {
        self.id = id
        self.symbol = symbol
        self.lastDate = lastDate
        self.lastClose = lastClose
        self.changePct = changePct
        self.patterns = patterns

        self.signalTotal = signalTotal
        self.signalDirection = signalDirection
        self.signalQuality = signalQuality
        self.signalConfidence = signalConfidence
        self.signal = signal
        self.breakdown = breakdown

        self.tomorrowTotal = tomorrowTotal
        self.tomorrowQuality = tomorrowQuality
        self.tomorrowTier = tomorrowTier
        self.tomorrowReasons = tomorrowReasons
        self.tomorrowBreakdown = tomorrowBreakdown
    }

    // MARK: - Codable (patterns custom)

    private enum CodingKeys: String, CodingKey {
        case id, symbol, lastDate, lastClose, changePct, patterns

        // legacy
        case signalTotal, signalDirection, signalQuality, signalConfidence, signal, breakdown

        // tomorrow
        case tomorrowTotal, tomorrowQuality, tomorrowTier, tomorrowReasons, tomorrowBreakdown
    }

    private struct CodablePattern: Codable {
        let name: String
        let score: Int
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        id = try c.decode(UUID.self, forKey: .id)
        symbol = try c.decode(String.self, forKey: .symbol)
        lastDate = try c.decode(Date.self, forKey: .lastDate)
        lastClose = try c.decode(Double.self, forKey: .lastClose)
        changePct = try c.decode(Double.self, forKey: .changePct)

        let raw = try c.decode([CodablePattern].self, forKey: .patterns)
        patterns = raw.compactMap { item in
            guard let p = CandlePattern(rawValue: item.name) else { return nil }
            return CandlePatternScore(pattern: p, score: item.score)
        }

        // legacy (geriye uyumlu)
        signalTotal = try c.decodeIfPresent(Int.self, forKey: .signalTotal)
        signalDirection = try c.decodeIfPresent(Int.self, forKey: .signalDirection)
        signalQuality = try c.decodeIfPresent(Int.self, forKey: .signalQuality)
        signalConfidence = try c.decodeIfPresent(Int.self, forKey: .signalConfidence)
        signal = try c.decodeIfPresent(TradeSignal.self, forKey: .signal)
        breakdown = try c.decodeIfPresent(SignalBreakdown.self, forKey: .breakdown)

        // tomorrow (v1.0)
        tomorrowTotal = try c.decodeIfPresent(Int.self, forKey: .tomorrowTotal)
        tomorrowQuality = try c.decodeIfPresent(String.self, forKey: .tomorrowQuality)
        tomorrowTier = try c.decodeIfPresent(LiquidityTier.self, forKey: .tomorrowTier)
        tomorrowReasons = try c.decodeIfPresent([String].self, forKey: .tomorrowReasons)
        tomorrowBreakdown = try c.decodeIfPresent(TomorrowBreakdown.self, forKey: .tomorrowBreakdown)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)

        try c.encode(id, forKey: .id)
        try c.encode(symbol, forKey: .symbol)
        try c.encode(lastDate, forKey: .lastDate)
        try c.encode(lastClose, forKey: .lastClose)
        try c.encode(changePct, forKey: .changePct)

        let raw = patterns.map { CodablePattern(name: $0.pattern.rawValue, score: $0.score) }
        try c.encode(raw, forKey: .patterns)

        // legacy optional: sadece varsa
        try c.encodeIfPresent(signalTotal, forKey: .signalTotal)
        try c.encodeIfPresent(signalDirection, forKey: .signalDirection)
        try c.encodeIfPresent(signalQuality, forKey: .signalQuality)
        try c.encodeIfPresent(signalConfidence, forKey: .signalConfidence)
        try c.encodeIfPresent(signal, forKey: .signal)
        try c.encodeIfPresent(breakdown, forKey: .breakdown)

        // tomorrow optional: sadece varsa
        try c.encodeIfPresent(tomorrowTotal, forKey: .tomorrowTotal)
        try c.encodeIfPresent(tomorrowQuality, forKey: .tomorrowQuality)
        try c.encodeIfPresent(tomorrowTier, forKey: .tomorrowTier)
        try c.encodeIfPresent(tomorrowReasons, forKey: .tomorrowReasons)
        try c.encodeIfPresent(tomorrowBreakdown, forKey: .tomorrowBreakdown)
    }
}

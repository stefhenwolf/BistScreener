import Foundation

/// Manuel ayarlanabilir strateji parametreleri (v2).
/// Tüm presetler softMode kullanır, scoring non-linear fonksiyonlarla yapılır.
/// Bu config'teki threshold'lar softMode=false için hard guard görevi görür.
/// Ağırlıklar ve minScore tüm modlarda aktif.
struct StrategyConfig: Codable, Equatable {

    init() {}

    // MARK: - Core thresholds

    var lookbackDays: Int = 20

    /// Proximity = close / refLevel (1.0 kırılım)
    /// softMode=true iken sadece referans, hard guard olarak kullanılmaz
    var minProximity: Double = 0.90
    var maxProximity: Double = 1.05

    /// ValueMultiple = todayValue / avg20Value
    var minValueMultiple: Double = 0.3

    /// VolumeTrend = (avgVol last 5) / (avgVol prev 10)
    var minVolumeTrend: Double = 0.0    // 0 = filtre kapalı (default)

    /// CLV = (close-low)/(high-low)
    var minCLV: Double = 0.15

    /// RangeCompression = recentRange / olderRange (küçük daha sıkışma)
    var maxRangeCompression: Double = 2.5

    /// Aşırı yükselmiş günü elemek için (EOD %)
    var maxTodayChangePct: Double = 8.0

    /// BUY minimum skor (non-linear scoring ile kalibre)
    var minScore: Int = 52

    /// SoftMode'da ek kalite kapısı (noise azaltma)
    /// total bu skorun altındaysa sinyal üretilmez.
    var softModeMinQualityScore: Int = 48

    // MARK: - Regime-based dynamic min score

    /// Bull rejimde base minScore'a eklenecek delta
    var regimeBullDelta: Int = 0

    /// Sideways rejimde base minScore'a eklenecek delta
    var regimeSidewaysDelta: Int = 6

    /// Bear rejimde base minScore'a eklenecek delta
    var regimeBearDelta: Int = 14

    /// Bear rejimde minimum taban skor
    var regimeBearMinScore: Int = 75

    // MARK: - Regime detection filters (ADX/Volatility)

    /// ADX bunun altındaysa piyasa yönsüz kabul edilir.
    var regimeMinADX: Double = 16.0

    /// ATR/Close (%) bu değerin üstünde ve ADX zayıfsa sideways'e zorla.
    var regimeHighVolATRPercent: Double = 7.5

    /// ATR/Close (%) bu değerin üstünde ise şok volatilite: sideways.
    var regimeShockATRPercent: Double = 9.5

    /// Yüksek volatilitede en az bu ADX yoksa trend kabul edilmez.
    var regimeMinADXWhenHighVol: Double = 22.0

    /// Bull/Bear etiketlemek için minimum ADX.
    var regimeTrendADX: Double = 20.0

    // MARK: - +5% ertesi gün kapasite filtresi

    /// ATR% + son 20 gündeki max günlük getiri ile üretilen kapasite skorunun alt sınırı (0..1)
    var minNextDay5CapacityScore: Double = 0.35

    // MARK: - Weights (toplam normalize edilir, oran önemli)
    //
    // v2 Ağırlık Felsefesi:
    //   proximity=35 → Kırılıma yakınlık EN ÖNEMLİ (pre-breakout stratejisi)
    //   clv=20       → Güçlü kapanış = talep gücü
    //   volume=20    → Hacim artışı = akıllı para birikimi
    //   compression=15 → Sıkışma = patlama enerjisi
    //   trend=10     → Trend kontekst sağlar ama tek başına yeterli değil

    var weightProximity: Double = 35
    var weightVolumeTrend: Double = 20
    var weightCLV: Double = 20
    var weightCompression: Double = 15
    var weightTrend: Double = 10
    var weightNextDay5Capacity: Double = 8

    // MARK: - Quality bands (non-linear skorlama ile kalibre)

    var qualityAPlus: Int = 80    // Çok güçlü sinyal
    var qualityA: Int = 68        // Güçlü sinyal
    var qualityB: Int = 55        // İyi sinyal
    var qualityC: Int = 42        // Zayıf sinyal

    // MARK: - Presets

    static var `default`: StrategyConfig { StrategyConfig() }

    /// Geniş ağ: daha fazla aday, backtestte daha çok sinyal üretir
    static var aggressive: StrategyConfig {
        var c = StrategyConfig()
        c.lookbackDays = 15
        c.minProximity = 0.88
        c.maxProximity = 1.06
        c.minValueMultiple = 0.2
        c.minVolumeTrend = 0.0
        c.minCLV = 0.10
        c.maxRangeCompression = 3.0
        c.maxTodayChangePct = 10.0
        c.minScore = 35
        // Ağırlıklar aynı kalır (non-linear scoring zaten yeterli)
        return c
    }

    /// Dar filtre: sadece en güçlü sinyaller
    static var conservative: StrategyConfig {
        var c = StrategyConfig()
        c.lookbackDays = 25
        c.minProximity = 0.93
        c.maxProximity = 1.02
        c.minValueMultiple = 0.5
        c.minVolumeTrend = 0.8
        c.minCLV = 0.40
        c.maxRangeCompression = 1.5
        c.maxTodayChangePct = 5.0
        c.minScore = 62
        return c
    }

    // MARK: - Persistence

    /// v2: Yeni key → eski v1 ayarları temiz başlangıç için yok sayılır
    private static let key = "strategy.config.v2"

    static func load() -> StrategyConfig {
        let ud = UserDefaults.standard
        guard let data = ud.data(forKey: key) else { return .default }
        do {
            return try JSONDecoder().decode(StrategyConfig.self, from: data)
        } catch {
            return .default
        }
    }

    func save() {
        do {
            let data = try JSONEncoder().encode(self)
            UserDefaults.standard.set(data, forKey: StrategyConfig.key)
            NotificationCenter.default.post(name: .strategySignalConfigChanged, object: nil)
        } catch {
            // no-op
        }
    }

    // MARK: - Codable compatibility

    private enum CodingKeys: String, CodingKey {
        case lookbackDays
        case minProximity
        case maxProximity
        case minValueMultiple
        case minVolumeTrend
        case minCLV
        case maxRangeCompression
        case maxTodayChangePct
        case minScore
        case softModeMinQualityScore
        case regimeBullDelta
        case regimeSidewaysDelta
        case regimeBearDelta
        case regimeBearMinScore
        case regimeMinADX
        case regimeHighVolATRPercent
        case regimeShockATRPercent
        case regimeMinADXWhenHighVol
        case regimeTrendADX
        case minNextDay5CapacityScore
        case weightProximity
        case weightVolumeTrend
        case weightCLV
        case weightCompression
        case weightTrend
        case weightNextDay5Capacity
        case qualityAPlus
        case qualityA
        case qualityB
        case qualityC
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self = .default

        lookbackDays = try c.decodeIfPresent(Int.self, forKey: .lookbackDays) ?? lookbackDays
        minProximity = try c.decodeIfPresent(Double.self, forKey: .minProximity) ?? minProximity
        maxProximity = try c.decodeIfPresent(Double.self, forKey: .maxProximity) ?? maxProximity
        minValueMultiple = try c.decodeIfPresent(Double.self, forKey: .minValueMultiple) ?? minValueMultiple
        minVolumeTrend = try c.decodeIfPresent(Double.self, forKey: .minVolumeTrend) ?? minVolumeTrend
        minCLV = try c.decodeIfPresent(Double.self, forKey: .minCLV) ?? minCLV
        maxRangeCompression = try c.decodeIfPresent(Double.self, forKey: .maxRangeCompression) ?? maxRangeCompression
        maxTodayChangePct = try c.decodeIfPresent(Double.self, forKey: .maxTodayChangePct) ?? maxTodayChangePct
        minScore = try c.decodeIfPresent(Int.self, forKey: .minScore) ?? minScore
        softModeMinQualityScore = try c.decodeIfPresent(Int.self, forKey: .softModeMinQualityScore) ?? softModeMinQualityScore

        regimeBullDelta = try c.decodeIfPresent(Int.self, forKey: .regimeBullDelta) ?? regimeBullDelta
        regimeSidewaysDelta = try c.decodeIfPresent(Int.self, forKey: .regimeSidewaysDelta) ?? regimeSidewaysDelta
        regimeBearDelta = try c.decodeIfPresent(Int.self, forKey: .regimeBearDelta) ?? regimeBearDelta
        regimeBearMinScore = try c.decodeIfPresent(Int.self, forKey: .regimeBearMinScore) ?? regimeBearMinScore
        regimeMinADX = try c.decodeIfPresent(Double.self, forKey: .regimeMinADX) ?? regimeMinADX
        regimeHighVolATRPercent = try c.decodeIfPresent(Double.self, forKey: .regimeHighVolATRPercent) ?? regimeHighVolATRPercent
        regimeShockATRPercent = try c.decodeIfPresent(Double.self, forKey: .regimeShockATRPercent) ?? regimeShockATRPercent
        regimeMinADXWhenHighVol = try c.decodeIfPresent(Double.self, forKey: .regimeMinADXWhenHighVol) ?? regimeMinADXWhenHighVol
        regimeTrendADX = try c.decodeIfPresent(Double.self, forKey: .regimeTrendADX) ?? regimeTrendADX
        minNextDay5CapacityScore = try c.decodeIfPresent(Double.self, forKey: .minNextDay5CapacityScore) ?? minNextDay5CapacityScore

        weightProximity = try c.decodeIfPresent(Double.self, forKey: .weightProximity) ?? weightProximity
        weightVolumeTrend = try c.decodeIfPresent(Double.self, forKey: .weightVolumeTrend) ?? weightVolumeTrend
        weightCLV = try c.decodeIfPresent(Double.self, forKey: .weightCLV) ?? weightCLV
        weightCompression = try c.decodeIfPresent(Double.self, forKey: .weightCompression) ?? weightCompression
        weightTrend = try c.decodeIfPresent(Double.self, forKey: .weightTrend) ?? weightTrend
        weightNextDay5Capacity = try c.decodeIfPresent(Double.self, forKey: .weightNextDay5Capacity) ?? weightNextDay5Capacity

        qualityAPlus = try c.decodeIfPresent(Int.self, forKey: .qualityAPlus) ?? qualityAPlus
        qualityA = try c.decodeIfPresent(Int.self, forKey: .qualityA) ?? qualityA
        qualityB = try c.decodeIfPresent(Int.self, forKey: .qualityB) ?? qualityB
        qualityC = try c.decodeIfPresent(Int.self, forKey: .qualityC) ?? qualityC
    }
}

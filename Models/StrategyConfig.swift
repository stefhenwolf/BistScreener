import Foundation

/// Manuel ayarlanabilir strateji parametreleri.
/// Normal preset bu config'i kullanır.
/// Relaxed/Strict presetler bu config'i override eder.
struct StrategyConfig: Codable, Equatable {

    // MARK: - Core thresholds
    var lookbackDays: Int = 20

    /// Proximity = close / refLevel (1.0 kırılım)
    var minProximity: Double = 0.97
    var maxProximity: Double = 1.005

    /// ValueMultiple = todayValue / avg20Value
    var minValueMultiple: Double = 0.8

    /// VolumeTrend = (avgVol last 5) / (avgVol prev 10)
    var minVolumeTrend: Double = 0.0    // 0 = filtre kapalı (default)

    /// CLV = (close-low)/(high-low)
    var minCLV: Double = 0.50

    /// RangeCompression = recentRange / olderRange (küçük daha sıkışma)
    var maxRangeCompression: Double = 1.50

    /// Aşırı yükselmiş günü elemek için (EOD %)
    var maxTodayChangePct: Double = 6.0

    /// BUY minimum skor
    var minScore: Int = 40

    // MARK: - Weights (0..100 scale recommended)
    var weightProximity: Double = 30
    var weightVolumeTrend: Double = 25
    var weightCLV: Double = 25
    var weightCompression: Double = 20

    // MARK: - Quality bands
    var qualityAPlus: Int = 90
    var qualityA: Int = 82
    var qualityB: Int = 74
    var qualityC: Int = 66

    // MARK: - Presets

    static var `default`: StrategyConfig { StrategyConfig() }

    static var aggressive: StrategyConfig {
        var c = StrategyConfig()
        c.minProximity = 0.92
        c.maxProximity = 1.02
        c.minValueMultiple = 0.5
        c.minVolumeTrend = 0.0
        c.minCLV = 0.30
        c.maxRangeCompression = 2.0
        c.maxTodayChangePct = 8.0
        c.minScore = 25
        return c
    }

    static var conservative: StrategyConfig {
        var c = StrategyConfig()
        c.minProximity = 0.97
        c.maxProximity = 1.002
        c.minValueMultiple = 1.0
        c.minVolumeTrend = 1.05
        c.minCLV = 0.70
        c.maxRangeCompression = 1.15
        c.maxTodayChangePct = 4.0
        c.minScore = 60
        return c
    }

    // MARK: - Persistence

    private static let key = "strategy.config.v1"

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
        } catch {
            // no-op
        }
    }
}

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
    var minValueMultiple: Double = 1.6

    /// VolumeTrend = (avgVol last 5) / (avgVol prev 10)
    var minVolumeTrend: Double = 1.05

    /// CLV = (close-low)/(high-low)
    var minCLV: Double = 0.78

    /// RangeCompression = recentRange / olderRange (küçük daha sıkışma)
    var maxRangeCompression: Double = 1.30

    /// Aşırı yükselmiş günü elemek için (EOD %)
    var maxTodayChangePct: Double = 6.0

    /// BUY minimum skor
    var minScore: Int = 50

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
        c.minProximity = 0.955
        c.maxProximity = 1.015
        c.minValueMultiple = 1.35
        c.minVolumeTrend = 1.00
        c.minCLV = 0.72
        c.maxRangeCompression = 1.45
        c.maxTodayChangePct = 8.0
        c.minScore = 35
        return c
    }

    static var conservative: StrategyConfig {
        var c = StrategyConfig()
        c.minProximity = 0.98
        c.maxProximity = 1.002
        c.minValueMultiple = 1.85
        c.minVolumeTrend = 1.10
        c.minCLV = 0.82
        c.maxRangeCompression = 1.20
        c.maxTodayChangePct = 5.0
        c.minScore = 65
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

import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

struct PortfolioWidgetSnapshot: Codable {
    let totalTRY: Double
    let totalPnLTRY: Double
    let totalPnLPct: Double
    let assetCount: Int
    let updatedAt: Date
}

struct StrategyWidgetSnapshot: Codable {
    let isRunning: Bool
    let pendingCount: Int
    let holdingsCount: Int
    let equityTL: Double
    let cashTL: Double
    let updatedAt: Date
}

enum WidgetSharedKeys {
    static let appGroupID = "group.com.sedat.bistscreener"
    static let portfolioSnapshot = "widget.portfolio.snapshot.v1"
    static let strategySnapshot = "widget.strategy.snapshot.v1"
}

@MainActor
final class WidgetSnapshotBridge {
    static let shared = WidgetSnapshotBridge()

    private init() {}

    func writePortfolioSnapshot(_ snapshot: PortfolioWidgetSnapshot) {
        write(snapshot, key: WidgetSharedKeys.portfolioSnapshot)
    }

    func writeStrategySnapshot(_ snapshot: StrategyWidgetSnapshot) {
        write(snapshot, key: WidgetSharedKeys.strategySnapshot)
    }

    private func write<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        if let sharedDefaults = UserDefaults(suiteName: WidgetSharedKeys.appGroupID) {
            sharedDefaults.set(data, forKey: key)
        }
        UserDefaults.standard.set(data, forKey: key)
#if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
#endif
    }
}

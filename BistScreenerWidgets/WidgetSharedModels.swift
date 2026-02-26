import Foundation

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

func widgetDefaults() -> UserDefaults {
    UserDefaults(suiteName: WidgetSharedKeys.appGroupID) ?? .standard
}

import Foundation

/// Centralized AppStorage keys for backtest exit config & portfolio settings.
/// Used by BacktestView, ScanView (ScanRowTV), and StockDetailView.
enum BacktestKeys {
    // Exit Configuration
    static let takeProfitPct   = "backtest.exit.takeProfitPct"
    static let tp1Pct          = "backtest.exit.tp1Pct"
    static let tp2Pct          = "backtest.exit.tp2Pct"
    static let tp1SellPercent  = "backtest.exit.tp1SellPercent"
    static let stopLossPct     = "backtest.exit.stopLossPct"
    static let maxHoldDays     = "backtest.exit.maxHoldDays"
    static let cooldownDays    = "backtest.exit.cooldownDays"

    // Portfolio Management
    static let maxPerPositionTL = "backtest.portfolio.maxPerPositionTL"
    static let addOnMode        = "backtest.portfolio.addOnMode"
    static let addOnWaitDays    = "backtest.portfolio.addOnWaitDays"
}

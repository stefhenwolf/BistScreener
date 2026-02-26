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
    static let commissionBps   = "backtest.exit.commissionBps"
    static let slippageBps     = "backtest.exit.slippageBps"

    // Portfolio Management
    static let minPerPositionTL = "backtest.portfolio.minPerPositionTL"
    static let maxPerPositionTL = "backtest.portfolio.maxPerPositionTL"
    static let addOnMode        = "backtest.portfolio.addOnMode"
    static let addOnWaitDays    = "backtest.portfolio.addOnWaitDays"
    static let sizingCapitalTL  = "backtest.sizing.capitalTL"
    static let sizingRiskPct    = "backtest.sizing.riskPct"

    // Signal mode
    static let scanPreset       = "settings.scanPreset"
    static let strategyMode     = "backtest.signal.strategyMode"
    static let ultraPreset      = "backtest.signal.ultraPreset"
}

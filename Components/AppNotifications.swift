//
//  AppNotifications.swift
//  BistScreener
//
//  Created by Sedat Pala on 23.02.2026.
//

import Foundation

extension Notification.Name {
    static let pauseMarketTicker  = Notification.Name("pauseMarketTicker")
    static let resumeMarketTicker = Notification.Name("resumeMarketTicker")
    static let appScanSettingsChanged = Notification.Name("appScanSettingsChanged")
    static let strategySignalConfigChanged = Notification.Name("strategySignalConfigChanged")
    static let scanSnapshotSaved = Notification.Name("scanSnapshotSaved")
    static let strategyApprovalCommandQueued = Notification.Name("strategyApprovalCommandQueued")
    static let appOpenDeepLink = Notification.Name("appOpenDeepLink")
}

//
//  HomeDashboardViewModel.swift
//  BistScreener
//
//  Created by Sedat Pala on 20.02.2026.
//

import Foundation
import SwiftUI

@MainActor
final class HomeDashboardViewModel: ObservableObject {

    // ticker
    let tickerVM = MarketTickerViewModel()

    // stats
    @Published var lastScanTitle: String = "—"
    @Published var lastScanSubtitle: String = "Kayıt yok"
    @Published var lastMatchCountText: String = "—"
    @Published var cacheText: String = "—"

    // last snapshot preview
    @Published var lastSnapshotItems: [ScanResult] = []

    func load(watchlist: WatchlistStore) {
        // 1) last snapshot
        do {
            let snap = try ScanSnapshotStore.load()
            lastScanTitle = snap.savedAt.formatted(date: .abbreviated, time: .shortened)
            lastScanSubtitle = IndexOption(rawValue: snap.indexRaw)?.title ?? snap.indexRaw
            lastMatchCountText = "\(snap.results.count)"

            // Persisted -> ScanResult (light)
            lastSnapshotItems = snap.results.map { r in
                let patterns: [CandlePatternScore] = r.patterns.compactMap { p in
                    guard let pat = CandlePattern(rawValue: p.name) else { return nil }
                    return CandlePatternScore(pattern: pat, score: p.score)
                }
                return ScanResult(
                    symbol: r.symbol,
                    lastDate: r.lastDate,
                    lastClose: r.lastClose,
                    changePct: r.changePct,
                    patterns: patterns
                )
            }
        } catch {
            lastScanTitle = "—"
            lastScanSubtitle = "Kayıt yok"
            lastMatchCountText = "—"
            lastSnapshotItems = []
        }

        // 2) cache (basit gösterim)
        cacheText = "—"

        // 3) ticker data

    }
}

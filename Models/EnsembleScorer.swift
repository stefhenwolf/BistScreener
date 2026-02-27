import Foundation

// MARK: - Ensemble Scorer
// ═══════════════════════════════════════════════════════════════════════
// Pre-Breakout (PB) + Ultra Bounce (UB) modellerini birleştirir.
//
// GELİŞTİRMELER:
//   1. Regime-aware ağırlıklar: Piyasa durumuna göre PB/UB ağırlığı değişir
//   2. Consensus bonus/penalty: İki model hemfikirse bonus, ayrışırsa ceza
//   3. Merkezi tek kaynak: ScannerViewModel + StockDetailView aynı kod
//   4. Zengin breakdown: Bireysel PB/UB skorları ve ağırlıklar gösterilir
//   5. Daha iyi tier seçimi: İki modelin en iyi likiditesi alınır
// ═══════════════════════════════════════════════════════════════════════

enum EnsembleScorer {

    // MARK: - Regime-Aware Weights

    struct Weights {
        let pb: Double
        let ub: Double
        let label: String
    }

    /// Piyasa rejimine göre PB/UB ağırlıklarını belirler.
    ///
    /// - Bull: Kırılım senaryosu daha olası → Pre-Breakout'a ağırlık
    /// - Bear: Bounce stratejisi daha geçerli → Ultra Bounce'a ağırlık
    /// - Sideways: İki model dengeli biçimde katkı sağlar
    static func weights(for regime: MarketRegime) -> Weights {
        switch regime {
        case .bull:
            return Weights(pb: 0.65, ub: 0.35, label: "Bull → PB↑")
        case .bear:
            return Weights(pb: 0.40, ub: 0.60, label: "Bear → UB↑")
        case .sideways:
            return Weights(pb: 0.52, ub: 0.48, label: "Sideways → Dengeli")
        }
    }

    // MARK: - Consensus Adjustment

    /// İki modelin uyumu üzerinden bonus veya ceza uygular.
    ///
    /// - İkisi de yüksek ve hemfikir → güvenilir sinyal → bonus
    /// - Büyük ayrışma → belirsiz sinyal → ceza
    static func consensusAdjustment(pbTotal: Int, ubTotal: Int) -> Double {
        let diff    = abs(pbTotal - ubTotal)
        let minScore = min(pbTotal, ubTotal)

        // Her iki model de güçlü ve birbirine yakın → yüksek güven
        if minScore >= 70 && diff <= 10 { return  6.0 }
        if minScore >= 60 && diff <= 14 { return  3.0 }
        if minScore >= 50 && diff <= 10 { return  1.5 }

        // Büyük uyuşmazlık → biri yanlış sinyal üretiyor olabilir
        if diff >= 28 { return -8.0 }
        if diff >= 20 { return -4.0 }
        if diff >= 14 { return -1.5 }

        return 0.0
    }

    // MARK: - Tier Selection

    /// İki modelin likiditesinden daha iyisini seçer (A > B > C > none).
    static func betterTier(_ a: LiquidityTier, _ b: LiquidityTier) -> LiquidityTier {
        let order: [LiquidityTier] = [.a, .b, .c, .none]
        let idxA = order.firstIndex(of: a) ?? 3
        let idxB = order.firstIndex(of: b) ?? 3
        return idxA <= idxB ? a : b
    }

    // MARK: - Quality Band

    private static func qualityBand(total: Int) -> String {
        switch total {
        case 85...: return "S"
        case 75...: return "A+"
        case 65...: return "A"
        case 52...: return "B"
        case 40...: return "C"
        default:    return "D"
        }
    }

    // MARK: - Main Entry Point

    /// PB ve UB skorlarını regime-aware biçimde birleştirir.
    ///
    /// - Parameters:
    ///   - pb: Pre-Breakout modeli sonucu (nil olabilir)
    ///   - ub: Ultra Bounce modeli sonucu (nil olabilir)
    ///   - regime: Tespit edilmiş piyasa rejimi
    /// - Returns: Birleştirilmiş `TomorrowSignalScore` veya nil
    static func blend(
        pb: TomorrowSignalScore?,
        ub: TomorrowSignalScore?,
        regime: MarketRegime
    ) -> TomorrowSignalScore? {
        let w = weights(for: regime)

        switch (pb, ub) {

        // ── Her iki model de sinyal üretti → tam ensemble ──
        case let (p?, u?):
            let consensusAdj = consensusAdjustment(pbTotal: p.total, ubTotal: u.total)
            let blendedRaw   = Double(p.total) * w.pb + Double(u.total) * w.ub + consensusAdj
            let total        = min(100, max(0, Int(round(blendedRaw))))
            let quality      = qualityBand(total: total)

            var seen    = Set<String>()
            var reasons = (p.reasons + u.reasons).filter { seen.insert($0).inserted }
            reasons     = Array(reasons.prefix(3))
            if reasons.isEmpty { reasons = ["Ensemble"] }

            var b = p.breakdown
            b.notes.append(contentsOf: [
                "── Ensemble ──",
                "PB: \(p.total)  |  UB: \(u.total)",
                "Ağırlık: PB %\(Int(w.pb * 100))  UB %\(Int(w.ub * 100))",
                "Regime: \(regime.title)  (\(w.label))",
                consensusAdj != 0
                    ? String(format: "Konsensüs: %+.0f", consensusAdj)
                    : "Konsensüs: —",
                "Ensemble Toplam: \(total)"
            ])

            let tier = betterTier(p.tier, u.tier)

            return TomorrowSignalScore(
                isBuy:     true,
                total:     total,
                quality:   quality,
                signal:    .buy,
                tier:      tier,
                reasons:   reasons,
                breakdown: b
            )

        // ── Sadece PB sinyal üretti → tek model fallback ──
        case let (p?, nil):
            return p.total >= 68 ? p : nil

        // ── Sadece UB sinyal üretti → tek model fallback ──
        case let (nil, u?):
            return u.total >= 70 ? u : nil

        // ── Her iki model de sinyal üretemedi ──
        default:
            return nil
        }
    }
}

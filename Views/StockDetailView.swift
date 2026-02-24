import SwiftUI

struct StockDetailView: View {

    // MARK: - Route

    let route: StockDetailRoute
    private var symbol: String { route.symbol }

    private enum T {
        static let title = Font.system(size: 15, weight: .semibold)
        static let subtitle = Font.system(size: 13, weight: .semibold)
        static let body = Font.system(size: 13, weight: .regular)
        static let foot = Font.system(size: 12, weight: .regular)

        static let headerSymbol = Font.system(size: 18, weight: .semibold)
        static let headerPrice  = Font.system(size: 16, weight: .semibold)
        static let headerPct    = Font.system(size: 12, weight: .semibold)
    }

    // MARK: - State (TEK KAYNAK)

    @State private var candles: [Candle] = []
    @State private var selectedCandle: Candle?

    /// candles -> PatternDetector (UI amaçlı)
    @State private var patterns: [CandlePatternScore] = []

    /// ✅ BUY-only Tomorrow analysis (canlı)
    @State private var tomorrow: TomorrowSignalScore? = nil

    /// Route üzerinden gelen özet veri (header/fallback hesaplamaları için).
    @State private var snapshot: ScanResult? = nil

    @State private var isLoading = false
    @State private var isRefreshing = false
    @State private var errorText: String?
    @AppStorage(BacktestKeys.takeProfitPct) private var takeProfitPct: Double = 20.0
    @AppStorage(BacktestKeys.stopLossPct) private var stopLossPct: Double = 6.0
    @AppStorage(BacktestKeys.maxHoldDays) private var maxHoldDays: Double = 30
    @AppStorage(BacktestKeys.cooldownDays) private var cooldownDays: Double = 3

    // MARK: - Env

    @EnvironmentObject private var services: AppServices
    @EnvironmentObject private var watchlist: WatchlistStore

    // MARK: - Init

    init(route: StockDetailRoute) {
        self.route = route
    }

    // MARK: - Derived

    private var shownCandles: [Candle] { Array(candles.suffix(140)) }
    private var activeCandle: Candle? { selectedCandle ?? shownCandles.last }

    private var isFav: Bool { watchlist.contains(symbol) }

    private var displayLastClose: Double? {
        if let close = activeCandle?.close { return close }
        return snapshot?.lastClose
    }

    private var displayChangePct: Double? {
        if shownCandles.count >= 2 {
            let last = shownCandles[shownCandles.count - 1].close
            let prev = shownCandles[shownCandles.count - 2].close
            if prev != 0 { return ((last - prev) / prev) * 100.0 }
        }
        return snapshot?.changePct
    }

    private var headerScore: Int {
        // Header’da: canlı tomorrow varsa onu göster, yoksa snapshot tomorrow, yoksa 0
        if let live = tomorrow { return live.total }
        if let snap = snapshot, let t = snap.tomorrowTotal { return t }
        return 0
    }

    // MARK: - View

    var body: some View {
        ScrollView {
            VStack(spacing: DS.s16) {

                tvHeader

                // ✅ canlı hesaplanan Tomorrow Bias
                analysisCard

                // ✅ Çıkış stratejisi (TP/SL/MaxDays)
                if tomorrow != nil {
                    exitStrategyCard
                }

                tvChartCard
                tvPatternsCard

                if let e = errorText {
                    AppCard {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(e)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                }
            }
            .padding(.horizontal, DS.s16)
            .padding(.vertical, DS.s12)
        }
#if !os(tvOS)
        .refreshable {
            await refresh()
        }
#endif
        .navigationBarTitleDisplayMode(.inline)
        .task(id: symbol) { await loadInitial() }
        .animation(.snappy, value: candles.count)
        .animation(.snappy, value: patterns.count)
        .tvBackground()
    }

    // MARK: - Header

    private var tvHeader: some View {
        let price = displayLastClose ?? 0
        let pct = displayChangePct
        let isUp = (pct ?? 0) >= 0

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(symbol)
                    .font(T.headerSymbol)
                    .foregroundStyle(TVTheme.text)

                Text(price == 0 ? "--" : String(format: "%.2f", price))
                    .font(T.headerPrice)
                    .foregroundStyle(TVTheme.text)

                if let pct {
                    Text(String(format: "%+.2f%%", pct))
                        .font(T.headerPct)
                        .foregroundStyle(isUp ? TVTheme.up : TVTheme.down)
                }

                let dataDate = activeCandle?.date ?? snapshot?.lastDate
                if let dataDate {
                    TVChip("Veri: \(dataDate.formatted(date: .abbreviated, time: .omitted))", systemImage: "calendar")
                }

                if let c = activeCandle {
                    HStack(spacing: 10) {
                        miniStat("H", String(format: "%.2f", c.high))
                        miniStat("L", String(format: "%.2f", c.low))
                        miniStat("O", String(format: "%.2f", c.open))
                    }
                }
            }

            Spacer()

            ScorePill(score: headerScore)

            Button { watchlist.toggle(symbol) } label: {
                Image(systemName: isFav ? "star.fill" : "star")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isFav ? .yellow : TVTheme.subtext)
                    .padding(10)
                    .background(TVTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(TVTheme.stroke, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(TVTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(TVTheme.stroke, lineWidth: 1)
        )
    }

    private func miniStat(_ k: String, _ v: String) -> some View {
        HStack(spacing: 6) {
            Text(k).foregroundStyle(TVTheme.subtext)
            Text(v).foregroundStyle(TVTheme.text)
        }
        .font(.system(size: 12, weight: .semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(TVTheme.surface2)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(TVTheme.stroke, lineWidth: 1))
    }

    // MARK: - Cards

    /// ✅ Canlı: candles -> compute tomorrow
    private var analysisCard: some View {
        TVCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Tomorrow Bias")
                        .font(T.title)
                        .foregroundStyle(TVTheme.text)

                    Spacer()

                    if let t = tomorrow {
                        qualityBadge(t.quality)
                    } else {
                        TVChip("—", systemImage: "bolt.fill")
                    }
                }

                if let t = tomorrow {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            TVChip("BUY", systemImage: "arrow.up.circle.fill")
                            TVChip("Σ \(t.total)", systemImage: "sum")
                            TVChip(t.tier.label, systemImage: "drop.fill")
                        }
                        .padding(.vertical, 2)
                    }

                    if let meta = metaLine(from: t) {
                        Text(meta)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(TVTheme.subtext)
                            .lineLimit(2)
                    }

                    if !t.reasons.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(t.reasons.prefix(3)), id: \.self) { s in
                                    TVChip(s, systemImage: "sparkles")
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } else {
                    Text("BUY sinyali yok (veya veri yok).")
                        .font(T.foot)
                        .foregroundStyle(TVTheme.subtext)
                }
            }
        }
    }

    // MARK: - Exit Strategy Card

    private var savedExitConfig: BacktestExitConfig {
        BacktestExitConfig(
            takeProfitPct: takeProfitPct,
            stopLossPct: stopLossPct,
            maxHoldDays: Int(maxHoldDays),
            cooldownDays: Int(cooldownDays)
        )
    }

    private var exitStrategyCard: some View {
        let price = candles.last?.close ?? 0
        let cfg = savedExitConfig

        let tpPrice = price * (1.0 + cfg.takeProfitPct / 100.0)
        let slPrice = price * (1.0 - cfg.stopLossPct / 100.0)
        let signalDate = shownCandles.last?.date ?? snapshot?.lastDate ?? Date()
        let projectedExit = Calendar.current.date(byAdding: .day, value: cfg.maxHoldDays, to: signalDate) ?? signalDate

        return TVCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Çıkış Stratejisi")
                        .font(T.title)
                        .foregroundStyle(TVTheme.text)
                    Spacer()
                    TVChip("Multi-Day", systemImage: "calendar.badge.clock")
                }

                // Fiyat seviyeleri
                HStack(spacing: 0) {
                    exitLevelView(
                        emoji: "🎯",
                        label: "Kâr Al",
                        pct: "+\(Int(cfg.takeProfitPct))%",
                        price: tpPrice,
                        color: TVTheme.up
                    )
                    exitLevelView(
                        emoji: "🛑",
                        label: "Zarar Kes",
                        pct: "-\(Int(cfg.stopLossPct))%",
                        price: slPrice,
                        color: TVTheme.down
                    )
                }

                // Alt bilgi
                HStack(spacing: 12) {
                    exitMiniChip("Max: \(cfg.maxHoldDays) gün", TVTheme.subtext)
                    exitMiniChip("Giriş: \(String(format: "%.2f", price))", TVTheme.text)
                }

                HStack(spacing: 12) {
                    exitMiniChip("Sinyal: \(signalDate.formatted(date: .abbreviated, time: .omitted))", TVTheme.subtext)
                    exitMiniChip("Max Çıkış: \(projectedExit.formatted(date: .abbreviated, time: .omitted))", TVTheme.subtext)
                }

                // Risk/Reward
                if cfg.stopLossPct > 0 {
                    let rr = cfg.takeProfitPct / cfg.stopLossPct
                    HStack(spacing: 6) {
                        Text("Risk/Reward:")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(TVTheme.subtext)
                        Text(String(format: "1:%.1f", rr))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(rr >= 2.5 ? TVTheme.up : (rr >= 1.5 ? .orange : TVTheme.down))
                    }
                }
            }
        }
    }

    private func exitLevelView(emoji: String, label: String, pct: String, price: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(emoji)
                .font(.system(size: 16))
            Text(pct)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(color)
            Text(String(format: "%.2f", price))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(TVTheme.text)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(TVTheme.subtext)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func exitMiniChip(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func metaLine(from t: TomorrowSignalScore) -> String? {
        let bd = t.breakdown
        let prox = String(format: "Proximity %+.1f%%", (bd.proximityPct - 1.0) * 100)
        let vol = String(format: "Vol x%.1f", bd.volumeTrend)
        let comp = String(format: "Range %.2f", bd.rangeCompression)
        let clv = String(format: "CLV %.2f", bd.clv)
        return [prox, vol, comp, clv].joined(separator: " • ")
    }

    private func qualityBadge(_ q: String) -> some View {
        let c: Color = {
            switch q {
            case "A+": return TVTheme.up
            case "A":  return TVTheme.up.opacity(0.85)
            case "B":  return Color(red: 0.85, green: 0.65, blue: 0.15)
            case "C":  return TVTheme.subtext
            default:   return TVTheme.subtext.opacity(0.85)
            }
        }()

        return HStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 12, weight: .bold))
            Text(q)
                .font(.system(size: 13, weight: .bold))
        }
        .foregroundStyle(c)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(c.opacity(0.18))
        .clipShape(Capsule())
    }

    private var tvChartCard: some View {
        ZStack {
            TVTheme.surface2
            TVGrid()

            CandlestickChartView(
                candles: shownCandles,
                selected: $selectedCandle
            )
            .padding(10)
        }
        .frame(height: 340)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(TVTheme.stroke, lineWidth: 1)
        )
    }

    private var tvPatternsCard: some View {
        VStack(alignment: .leading, spacing: 12) {

            HStack {
                Text("Patterns")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(TVTheme.text)

                Spacer()

                TVChip("\(patterns.count)", systemImage: "list.bullet")
            }

            if patterns.isEmpty {
                Text("Belirgin pattern yok (veya veri yok).")
                    .font(.subheadline)
                    .foregroundStyle(TVTheme.subtext)
            } else {
                VStack(spacing: 10) {
                    ForEach(patterns.sorted { $0.score > $1.score }.prefix(10), id: \.id) { p in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(p.pattern.rawValue)
                                    .foregroundStyle(TVTheme.text)
                                    .font(.system(size: 13, weight: .semibold))
                                    .lineLimit(1)

                                Text(p.pattern.direction == .bullish ? "Yukselen" : p.pattern.direction == .bearish ? "Dusen" : "Notr")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(
                                        p.pattern.direction == .bullish ? TVTheme.up :
                                        p.pattern.direction == .bearish ? TVTheme.down :
                                        TVTheme.subtext
                                    )
                            }

                            Spacer()

                            ScorePill(score: p.score)
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .padding(12)
                        .background(TVTheme.surface2)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(TVTheme.stroke, lineWidth: 1)
                        )
                    }
                }
            }
        }
        .padding(16)
        .background(TVTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(TVTheme.stroke, lineWidth: 1)
        )
    }

    // MARK: - Data

    @MainActor
    private func loadInitial() async {
        candles = []
        selectedCandle = nil
        patterns = []
        tomorrow = nil
        errorText = nil

        if case .snapshot(let r) = route {
            snapshot = r
            // snapshot’tan patterns göster (UI için)
            patterns = r.patterns
        } else {
            snapshot = nil
        }

        await fetchCandles(forceRefresh: false)
        recalcLiveTomorrowIfNeeded()
    }

    @MainActor
    private func refresh() async {
        errorText = nil
        await fetchCandles(forceRefresh: true)
        recalcLiveTomorrowIfNeeded()
    }

    @MainActor
    private func fetchCandles(forceRefresh: Bool) async {
        if isLoading || isRefreshing { return }

        if candles.isEmpty { isLoading = true }
        else { isRefreshing = true }

        do {
            let fetched = try await services.candles.getCandles(
                symbol: symbol,
                range: .mo6,
                minCount: 160,
                forceRefresh: forceRefresh
            )
            self.candles = fetched
        } catch {
            self.errorText = error.localizedDescription
        }

        isLoading = false
        isRefreshing = false
    }

    /// ✅ Canlı tomorrow hesapla (snapshot olsa bile canlı hesap göstermek istiyoruz)
    @MainActor
    private func recalcLiveTomorrowIfNeeded() {
        guard !candles.isEmpty else {
            tomorrow = nil
            return
        }

        let recent = Array(candles.suffix(160))
        guard recent.count >= 80 else {
            tomorrow = nil
            return
        }

        // Patterns: canlı tespit et. Boş gelirse snapshot’takini koru.
        let livePatterns = PatternDetector.detectScored(last: Array(recent.suffix(120)))
        if !livePatterns.isEmpty {
            patterns = livePatterns
        } else if patterns.isEmpty, let snap = snapshot {
            // Canlı boş VE mevcut de boş ise snapshot’tan yükle
            patterns = snap.patterns
        }

        // PRE-BREAKOUT v2: lookback preset'ten otomatik gelir
        tomorrow = SignalScorer.scoreTomorrowBuyOnly(
            candles: recent,
            preset: .normal
        )
    }
}

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

    /// ✅ Sadece bilgi amaçlı: route snapshot geldiyse “Tarama Özeti” kartında göster
    @State private var snapshot: ScanResult? = nil

    @State private var isLoading = false
    @State private var isRefreshing = false
    @State private var errorText: String?

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

                // ✅ Tarama’dan geldiyse meta
                if let snap = snapshot {
                    snapshotCard(snap)

                    // ✅ snapshot tomorrow varsa ayrıca göster (BUY-only kart)
                    if let snapCard = snapshotTomorrowCard(snap) {
                        snapCard
                    }
                }

                // ✅ canlı hesaplanan Tomorrow Bias
                analysisCard

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
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.plain)
                .disabled(isLoading || isRefreshing)
            }
        }
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

    /// ✅ Sadece bilgilendirme: tarama snapshot metadata
    private func snapshotCard(_ snap: ScanResult) -> some View {
        TVCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Tarama Özeti")
                        .font(T.title)
                        .foregroundStyle(TVTheme.text)

                    Spacer()

                    TVChip("Snapshot", systemImage: "doc.text.magnifyingglass")
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        TVChip("\(snap.patterns.count) pattern", systemImage: "sparkles")
                        TVChip(snap.lastDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                        if let q = snap.tomorrowQuality {
                            TVChip("Q \(q)", systemImage: "checkmark.seal")
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    /// Snapshot içinde tomorrow varsa göster
    private func snapshotTomorrowCard(_ snap: ScanResult) -> AnyView? {
        guard let t = snap.tomorrowTotal else { return nil }

        let q = snap.tomorrowQuality ?? snap.uiQuality
        let tier = snap.uiTierText ?? "—"
        let meta = snap.uiMetaLine ?? ""

        let reasons = (snap.tomorrowReasons ?? []).prefix(3)

        return AnyView(
            TVCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Tomorrow Bias (Snapshot)")
                            .font(T.title)
                            .foregroundStyle(TVTheme.text)

                        Spacer()

                        qualityBadge(q)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            TVChip("BUY", systemImage: "arrow.up.circle.fill")
                            TVChip("Σ \(t)", systemImage: "sum")
                            TVChip(tier, systemImage: "drop.fill")
                        }
                        .padding(.vertical, 2)
                    }

                    if !meta.isEmpty {
                        Text(meta)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(TVTheme.subtext)
                            .lineLimit(2)
                    }

                    if !reasons.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(reasons), id: \.self) { s in
                                    TVChip(s, systemImage: "sparkles")
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        )
    }

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

    private func metaLine(from t: TomorrowSignalScore) -> String? {
        let bd = t.breakdown
        let clv = String(format: "CLV %.2f", bd.clv)
        let vx  = String(format: "Value x%.2f", bd.valueMultiple)
        let brk = (t.tier == .c) ? "Breakout \(bd.lookback)d High" : "Breakout \(bd.lookback)d Close"
        return [clv, vx, brk].joined(separator: " • ")
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
                            Text(p.pattern.rawValue)
                                .foregroundStyle(TVTheme.text)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)

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

        // Patterns UI için güncelle (snapshot’tan gelmişse de canlıdakiyle değişmesi sorun değil)
        patterns = PatternDetector.detectScored(last: Array(recent.suffix(120)))

        // Detail’de preset’i şimdilik normal tutuyoruz
        tomorrow = SignalScorer.scoreTomorrowBuyOnly(
            candles: recent,
            preset: .normal,
            lookback: 20
        )
    }
}

import SwiftUI
#if os(iOS)
import UIKit
#endif

struct HomeView: View {
    private enum NavRoute: Hashable {
        case assets
    }

    @Binding var selectedTab: AppTab
    let openStrategyPage: () -> Void
    @ObservedObject var scannerVM: ScannerViewModel
    @ObservedObject var tickerVM: MarketTickerViewModel

    @EnvironmentObject private var watchlist: WatchlistStore

    @StateObject private var favVM = FavoritesViewModel()
    @EnvironmentObject private var portfolioVM: PortfolioViewModel
    @EnvironmentObject private var strategyStore: LiveStrategyStore

    @ObservedObject private var scanStats = ScanStatsStore.shared
    @State private var showAddSheet = false
    @State private var isRefreshingHome = false

    @AppStorage("home_showPortfolioCard") private var showPortfolioCard: Bool = true

    private var homeIsLoading: Bool {
        portfolioVM.isLoading || favVM.isLoading || tickerVM.isLoading || strategyStore.isRefreshing
    }

    var body: some View {
        ZStack {
            TVTheme.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: DS.s16) {

                    quickActionsCard

                    if showPortfolioCard {
                        portfolioCard
                    } else {
                        portfolioRevealCard
                    }
                    strategyCard

                    scanSummaryCard
                    favoritesMoversCard
                }
                .padding(.horizontal, DS.s16)
                .padding(.vertical, DS.s12)
            }
            .tint(.white)
            .refreshable {
                await refreshHomeData(triggerHaptic: true)
            }
        }
        .navigationTitle("Anasayfa")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(TVTheme.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .safeAreaInset(edge: .top) {
            MarketTickerBar(vm: tickerVM)
                .padding(.horizontal, DS.s16)
                .background(TVTheme.bg)
        }
        .sheet(isPresented: $showAddSheet) {
            AddFavoriteSheet {
                favVM.refresh(symbols: watchlist.symbols)
            }
            .environmentObject(watchlist)
            .presentationBackground(TVTheme.bg)
        }
        .onAppear {
            Task { await refreshHomeData(triggerHaptic: false) }
        }
        .onChangeCompat(of: watchlist.symbols) { new in
            favVM.refresh(symbols: new)
        }
        .onChangeCompat(of: scannerVM.isScanning) { scanning in
            if scanning == false {
                tickerVM.refreshNow()
                favVM.refresh(symbols: watchlist.symbols)
            }
        }
        .navigationDestination(for: NavRoute.self) { route in
            switch route {
            case .assets:
                AssetsTabRoot()
            }
        }
        .tvNavStyle()
    }

    @MainActor
    private func refreshHomeData(triggerHaptic: Bool) async {
        guard !isRefreshingHome else { return }
        isRefreshingHome = true

        if triggerHaptic {
            hapticImpact()
        }

        portfolioVM.clearPriceCache()
        portfolioVM.loadFromDiskAndRefresh()
        favVM.refresh(symbols: watchlist.symbols)
        tickerVM.refreshNow()
        if strategyStore.isRunning {
            await strategyStore.refreshNow()
        }

        // Refreshable spinner için kısa bir bekleme + yük durumunun sakinleşmesi
        try? await Task.sleep(nanoseconds: 180_000_000)
        await waitUntilSettled(timeout: 2.8)

        if triggerHaptic {
            let hasError =
                (portfolioVM.errorText?.isEmpty == false) ||
                (favVM.errorText?.isEmpty == false) ||
                (tickerVM.errorText?.isEmpty == false)
            hapticResult(success: !hasError)
        }

        isRefreshingHome = false
    }

    @MainActor
    private func waitUntilSettled(timeout: TimeInterval) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !homeIsLoading { break }
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
    }

    private func hapticImpact() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    private func hapticResult(success: Bool) {
        #if os(iOS)
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(success ? .success : .warning)
        #endif
    }

    // MARK: - Quick Actions

    private var quickActionsCard: some View {
        TVCard {
            VStack(alignment: .leading, spacing: DS.s12) {
                HStack {
                    Text("Hızlı İşlemler")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(TVTheme.text)
                    Spacer()
                    TVChip("Dashboard", systemImage: "sparkles")
                }

                HStack(spacing: 10) {
                    Button {
                        if scannerVM.isScanning { scannerVM.cancelScan() }
                        else { scannerVM.startScan() }
                    } label: {
                        actionPill(
                            title: scannerVM.isScanning ? "Durdur" : "Tara",
                            icon: scannerVM.isScanning ? "stop.fill" : "play.fill"
                        )
                    }
                    .buttonStyle(.plain)

                    Button { selectedTab = .favorites } label: {
                        actionPill(title: "Favoriler", icon: "star.fill")
                    }
                    .buttonStyle(.plain)

                    Button { selectedTab = .profile } label: {
                        actionPill(title: "Profil", icon: "person.crop.circle")
                    
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func actionPill(title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(TVTheme.text)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(TVTheme.text)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(TVTheme.surface2)
        .clipShape(RoundedRectangle(cornerRadius: DS.r14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.r14, style: .continuous)
                .stroke(TVTheme.stroke, lineWidth: 1)
        )
    }

    // MARK: - Portfolio

    private var portfolioCard: some View {
        TVCard {
            VStack(alignment: .leading, spacing: DS.s12) {
                HStack {
                    Text("Toplam Portföy")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(TVTheme.text)
                    Spacer()

                    NavigationLink(value: NavRoute.assets) {
                        TVChip("Detay", systemImage: "arrow.right")
                    }
                    .buttonStyle(.plain)

                    Button { showPortfolioCard = false } label: {
                        Image(systemName: "eye.slash")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(TVTheme.subtext)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Portföy kartını gizle")
                }

                Group {
                    if portfolioVM.assets.isEmpty && !portfolioVM.isLoading {
                        if #available(iOS 17.0, *) {
                            ContentUnavailableView(
                                "Henüz varlık yok",
                                systemImage: "tray",
                                description: Text("Portföy oluşturmak için varlık ekleyebilirsin.")
                            )
                            .foregroundStyle(TVTheme.subtext)
                        } else {
                            Text("Henüz varlık eklenmedi.")
                                .foregroundStyle(TVTheme.subtext)
                                .font(.subheadline)
                        }
                    } else {
                        let total = portfolioVM.totalTRY
                        let pnl = portfolioVM.rows.compactMap(\.pnlTRY).reduce(0, +)
                        let investedBase = max(0, total - pnl)
                        let pnlPct = investedBase > 0 ? (pnl / investedBase) * 100.0 : 0

                        Text(total.formatted(.currency(code: "TRY")))
                            .font(.title2.bold())
                            .foregroundStyle(TVTheme.text)
                            .skeletonize(if: portfolioVM.isLoading)

                        HStack(spacing: 8) {
                            Text("Toplam K/Z:")
                                .font(.subheadline)
                                .foregroundStyle(TVTheme.subtext)
                                .skeletonize(if: portfolioVM.isLoading)

                            Text(pnl.formatted(.currency(code: "TRY")))
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(pnl >= 0 ? TVTheme.up : TVTheme.down)
                                .skeletonize(if: portfolioVM.isLoading)

                            Text(String(format: "(%+.2f%%)", pnlPct))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(pnl >= 0 ? TVTheme.up : TVTheme.down)
                                .skeletonize(if: portfolioVM.isLoading)
                        }
                    }
                }

                HStack(spacing: 10) {
                    if portfolioVM.isLoading {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.9)
                        Text("Güncelleniyor…")
                            .font(.caption)
                            .foregroundStyle(TVTheme.subtext)
                    } else if let e = portfolioVM.errorText {
                        Label(e, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    } else if let d = portfolioVM.lastUpdated {
                        Text("Güncelleme: \(d.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(TVTheme.subtext)
                    } else {
                        Text("—")
                            .font(.caption)
                            .foregroundStyle(TVTheme.subtext)
                    }

                    Spacer()

                    Button { portfolioVM.clearPriceCache(); portfolioVM.refreshPrices() } label: {
                        TVChip("Yenile", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .disabled(portfolioVM.isLoading)
                }
            }
        }
    }

    private var portfolioRevealCard: some View {
        TVCard {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Portföy kartı gizli")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(TVTheme.text)

                    Text("İstersen tekrar görünür yapabilirsin.")
                        .font(.caption)
                        .foregroundStyle(TVTheme.subtext)
                }
                Spacer()
                Button { showPortfolioCard = true } label: {
                    TVChip("Göster", systemImage: "eye")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var strategyCard: some View {
        TVCard {
            VStack(alignment: .leading, spacing: DS.s12) {
                HStack {
                    Text("Canlı Strateji")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(TVTheme.text)
                    Spacer()
                    TVChip("Stratejiye Git", systemImage: "arrow.right")
                }

                if strategyStore.isRunning {
                    let pnl = strategyStore.totalReturnTL
                    Text(strategyStore.totalValueTL.formatted(.currency(code: "TRY")))
                        .font(.title3.bold())
                        .foregroundStyle(TVTheme.text)

                    HStack(spacing: 8) {
                        Text("Toplam K/Z:")
                            .font(.subheadline)
                            .foregroundStyle(TVTheme.subtext)
                        Text(pnl.formatted(.currency(code: "TRY")))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(pnl >= 0 ? TVTheme.up : TVTheme.down)
                        Text(String(format: "%+.2f%%", strategyStore.totalReturnPct))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(pnl >= 0 ? TVTheme.up : TVTheme.down)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(TVTheme.surface2)
                            .clipShape(Capsule())
                    }

                    HStack(spacing: 10) {
                        Text("Açık Pozisyon: \(strategyStore.holdings.count)")
                            .font(.caption)
                            .foregroundStyle(TVTheme.subtext)
                        Spacer()
                        if strategyStore.isRefreshing {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.9)
                        } else if let d = strategyStore.lastUpdated {
                            Text("Güncelleme: \(d.formatted(date: .omitted, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(TVTheme.subtext)
                        }
                    }
                } else {
                    Text("Strateji pasif. Strateji sekmesinden başlangıç sermayesi ile başlatabilirsin.")
                        .font(.subheadline)
                        .foregroundStyle(TVTheme.subtext)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            openStrategyPage()
        }
    }

    // MARK: - Scan Summary

    private var scanSummaryCard: some View {
        TVCard {
            VStack(alignment: .leading, spacing: DS.s12) {
                HStack {
                    Text("Tarama Özeti")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(TVTheme.text)
                    Spacer()
                    Button { selectedTab = .scan } label: {
                        TVChip("Taramaya Git", systemImage: "arrow.right")
                    }
                    .buttonStyle(.plain)
                }

                if let tErr = tickerVM.errorText, !tErr.isEmpty {
                    Label("Piyasa verisi: \(tErr)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }

                Group {
                    if scannerVM.isScanning {
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView(value: scannerVM.progressValue)
                                .tint(TVTheme.up)
                            Text(scannerVM.progressText)
                                .font(.footnote)
                                .foregroundStyle(TVTheme.subtext)
                        }
                    } else if let d = scanStats.lastScanDate {
                        Text("Son tarama: \(d.formatted(date: .abbreviated, time: .shortened))")
                            .foregroundStyle(TVTheme.subtext)
                            .font(.subheadline)

                        HStack(spacing: 10) {
                            TVChip("Taranan \(scanStats.lastUniverseCount)", systemImage: "list.number")
                            TVChip("Eşleşen \(scanStats.lastMatchesCount)", systemImage: "waveform.path.ecg")
                        }
                    } else {
                        if #available(iOS 17.0, *) {
                            ContentUnavailableView(
                                "Henüz tarama yok",
                                systemImage: "magnifyingglass",
                                description: Text("Tarama ekranından tüm hisseleri tarayabilirsin.")
                            )
                            .foregroundStyle(TVTheme.subtext)
                        } else {
                            Text("Henüz tarama yapılmadı.")
                                .foregroundStyle(TVTheme.subtext)
                                .font(.subheadline)
                        }
                    }
                }
                .skeletonize(if: homeIsLoading && scanStats.lastScanDate == nil)

                if let u = tickerVM.lastUpdated {
                    Text("Piyasa güncelleme: \(u.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(TVTheme.subtext)
                }
            }
        }
    }

    // MARK: - Favorites Movers

    private var favoritesMoversCard: some View {
        let gainers = favVM.rows
            .compactMap { r -> (String, Double)? in
                guard let ch = r.changePct, ch > 0 else { return nil }
                return (r.symbol, ch)
            }
            .sorted { $0.1 > $1.1 }

        let losers = favVM.rows
            .compactMap { r -> (String, Double)? in
                guard let ch = r.changePct, ch < 0 else { return nil }
                return (r.symbol, ch)
            }
            .sorted { $0.1 < $1.1 }

        return TVCard {
            VStack(alignment: .leading, spacing: DS.s12) {

                HStack {
                    Text("Favoriler: Artan/Azalan")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(TVTheme.text)
                    Spacer()
                    Button { selectedTab = .favorites } label: {
                        TVChip("Favorilere Git", systemImage: "arrow.right")
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 10) {
                    TVChip("Toplam \(watchlist.symbols.count)", systemImage: "star.fill")
                    if favVM.isLoading { whiteLoadingChip("Yükleniyor", systemImage: "hourglass") }
                }
                .skeletonize(if: favVM.isLoading)

                Group {
                    if watchlist.symbols.isEmpty {
                        if #available(iOS 17.0, *) {
                            ContentUnavailableView(
                                "Henüz favori yok",
                                systemImage: "star",
                                description: Text("Favori ekleyerek hızlı takip edebilirsin.")
                            )
                            .foregroundStyle(TVTheme.subtext)
                        } else {
                            Text("Henüz favori eklenmedi.")
                                .foregroundStyle(TVTheme.subtext)
                                .font(.subheadline)
                        }
                    } else if let err = favVM.errorText, !err.isEmpty, !favVM.isLoading {
                        if #available(iOS 17.0, *) {
                            ContentUnavailableView(
                                "Favoriler yüklenemedi",
                                systemImage: "wifi.exclamationmark",
                                description: Text(err)
                            )
                            .foregroundStyle(TVTheme.subtext)
                        } else {
                            Text(err).foregroundStyle(.red).font(.subheadline)
                        }
                    } else {
                        HStack(alignment: .top, spacing: 14) {
                            moversColumn(title: "↑ Artanlar",
                                         items: Array(gainers.prefix(3)),
                                         isPositive: true,
                                         isLoading: favVM.isLoading)
                            moversColumn(title: "↓ Azalanlar",
                                         items: Array(losers.prefix(3)),
                                         isPositive: false,
                                         isLoading: favVM.isLoading)
                        }
                    }
                }

                if watchlist.symbols.isEmpty {
                    Button { showAddSheet = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                            Text("Favori Ekle")
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(TVTheme.text)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(TVTheme.surface2)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(TVTheme.stroke, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func moversColumn(
        title: String,
        items: [(String, Double)],
        isPositive: Bool,
        isLoading: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(TVTheme.subtext)

            if isLoading {
                moversPlaceholderList
            } else if items.isEmpty {
                Text("—").foregroundStyle(TVTheme.subtext)
            } else {
                ForEach(items, id: \.0) { sym, ch in
                    HStack {
                        Text(sym)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(TVTheme.text)
                        Spacer()
                        Text(String(format: "%+.2f%%", ch))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isPositive ? TVTheme.up : TVTheme.down)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var moversPlaceholderList: some View {
        VStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { _ in
                HStack {
                    Text("XXXX")
                    Spacer()
                    Text("+0.00%")
                }
                .font(.subheadline)
                .skeletonize(if: true)
            }
        }
    }

    private func whiteLoadingChip(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(TVTheme.surface2)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(TVTheme.stroke, lineWidth: 1))
    }
}

// MARK: - Skeleton helper
private extension View {
    @ViewBuilder
    func skeletonize(if isLoading: Bool) -> some View {
        if isLoading {
            self.redacted(reason: .placeholder).opacity(0.85)
        } else {
            self
        }
    }
}

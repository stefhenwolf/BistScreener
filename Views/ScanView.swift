import SwiftUI

struct ScanView: View {
    @ObservedObject var vm: ScannerViewModel
    @ObservedObject var engine: BacktestEngine

    // UI
    @State private var sort: SortMode = .scoreDesc
    @State private var showInfo: Bool = false
    @State private var showFilters: Bool = false

    private enum NavRoute: Hashable {
        case backtest
        case detail(StockDetailRoute)
    }

    // Cache
    private var sortedAndFilteredResults: [ScanResult] {
        sortedResults(vm.results)
    }

    private var summaryStats: (count: Int, aPlus: Int, a: Int, b: Int, best: Int, avg: Int) {
        let items = sortedAndFilteredResults
        let count = items.count
        let best = items.map { $0.uiScore }.max() ?? 0
        let avg = count == 0 ? 0 : Int(Double(items.map { $0.uiScore }.reduce(0, +)) / Double(count))
        let aPlus = items.filter { $0.uiQuality == "A+" }.count
        let a = items.filter { $0.uiQuality == "A" }.count
        let b = items.filter { $0.uiQuality == "B" }.count
        return (count, aPlus, a, b, best, avg)
    }

    enum SortMode: String, CaseIterable, Identifiable {
        var id: String { rawValue }
        case scoreDesc = "Skor ↓"
        case changeDesc = "% ↓"
        case patternsDesc = "Pattern ↓"
        case symbolAsc = "Sembol ↑"
    }

    var body: some View {
        ZStack {
            TVTheme.bg.ignoresSafeArea()
            content
        }
        .onChangeCompat(of: vm.selectedIndex, initial: true) { newValue in
            vm.switchIndex(newValue)
        }
        .toolbarBackground(TVTheme.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .sheet(isPresented: $showInfo) {
            // TODO: bunu TomorrowBias info view’a çevireceğiz
            ScanScoringInfoView(sample: vm.results.first)
        }
        .sheet(isPresented: $showFilters) {
            ScanFilterSheet(vm: vm)
        }
        .navigationDestination(for: NavRoute.self) { route in
            switch route {
            case .backtest:
                BacktestView(engine: engine)
            case .detail(let detailRoute):
                StockDetailView(route: detailRoute)
            }
        }
        .tvNavStyle()
    }

    private var content: some View {
        VStack(spacing: DS.s12) {

            headerCard
                .padding(.horizontal, DS.s16)
                .padding(.top, DS.s12)

            if vm.isScanning {
                progressCard
                    .padding(.horizontal, DS.s16)
            } else if let e = vm.errorText {
                errorCard(e)
                    .padding(.horizontal, DS.s16)
            }

            listBody
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("Tarama")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 14) {

                    NavigationLink(value: NavRoute.backtest) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(TVTheme.text)
                    }
                    .buttonStyle(.plain)

                    Button { showFilters = true } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(TVTheme.text)
                    }
                    .buttonStyle(.plain)

                    Button { showInfo = true } label: {
                        Image(systemName: "info.circle")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(TVTheme.text)
                    }
                    .buttonStyle(.plain)

                    Button { vm.deleteSnapshotAndReset() } label: {
                        Image(systemName: "trash")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(TVTheme.text)
                    }
                    .buttonStyle(.plain)

                    Button {
                        if vm.isScanning { vm.cancelScan() }
                        else { vm.startScan() }
                    } label: {
                        Image(systemName: vm.isScanning ? "stop.fill" : "play.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(TVTheme.text)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        TVCard {
            VStack(spacing: DS.s12) {

                // Strateji modu seçimi
                Picker("Strateji", selection: $vm.strategyMode) {
                    ForEach(ScanStrategyMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Endeks", selection: $vm.selectedIndex) {
                    ForEach(IndexOption.allCases) { opt in
                        Text(opt.title).tag(opt)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 10) {
                    TVChip("Preset", systemImage: "slider.horizontal.3")
                    if vm.strategyMode == .ultraBounce {
                        Text(vm.ultraPreset.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(TVTheme.text)
                    } else {
                        Text(vm.preset.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(TVTheme.text)
                    }

                    Spacer()

                    TVChip("Sırala", systemImage: "arrow.up.arrow.down")
                    Menu {
                        Picker("Sırala", selection: $sort) {
                            ForEach(SortMode.allCases) { s in
                                Text(s.rawValue).tag(s)
                            }
                        }
                    } label: {
                        Text(sort.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(TVTheme.text)
                    }

                    Spacer()

                    if vm.isScanning {
                        TVChip("Taranıyor", systemImage: "hourglass")
                    } else {
                        TVChip("\(summaryStats.count) BUY", systemImage: "list.bullet")
                    }
                }
            }
        }
    }

    // MARK: - Progress / Error

    private var progressCard: some View {
        TVCard {
            VStack(alignment: .leading, spacing: DS.s12) {
                HStack {
                    Text("İlerleme")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(TVTheme.text)
                    Spacer()
                    Text("\(Int(vm.progressValue * 100))%")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(TVTheme.subtext)
                }

                ProgressView(value: vm.progressValue)
                    .tint(TVTheme.text)

                Text(vm.progressText)
                    .font(.footnote)
                    .foregroundStyle(TVTheme.subtext)
            }
        }
    }

    private func errorCard(_ text: String) -> some View {
        TVCard {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(TVTheme.subtext)
                Spacer()
                Button("Tekrar") {
                    if vm.isScanning { vm.cancelScan() }
                    vm.startScan()
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(TVTheme.text)
            }
        }
    }

    // MARK: - List

    @ViewBuilder
    private var listBody: some View {
        let buyResults = sortedAndFilteredResults

        if buyResults.isEmpty {
            emptyState
                .padding(.horizontal, DS.s16)
        } else {
            let rowInsets = EdgeInsets(top: 8, leading: DS.s16, bottom: 8, trailing: DS.s16)

            List {
                summaryHeaderRow(items: buyResults)
                    .listRowInsets(EdgeInsets(top: 8, leading: DS.s16, bottom: 6, trailing: DS.s16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                ForEach(buyResults, id: \.symbol) { r in
                    NavigationLink(value: NavRoute.detail(.snapshot(r))) {
                        ScanRowTV(r: r)
                    }
                    .listRowInsets(rowInsets)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .id(vm.selectedIndex)
            .transaction { $0.animation = nil }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
    }

    private func summaryHeaderRow(items: [ScanResult]) -> some View {
        let stats = summaryStats

        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                Text("BUY (Yarın Bias)")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.black)

            Spacer()

            HStack(spacing: 8) {
                Text("\(stats.count) adet")
                if stats.aPlus > 0 { Text("A+ \(stats.aPlus)") }
                if stats.a > 0     { Text("A \(stats.a)") }
                if stats.b > 0     { Text("B \(stats.b)") }
                Text("Best \(stats.best)")
                Text("Avg \(stats.avg)")
            }
            .font(.caption)
            .foregroundStyle(.black.opacity(0.75))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
        }
        .padding(12)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.black.opacity(0.12), lineWidth: 1)
        )
    }

    private var emptyState: some View {
        TVCard {
            VStack(spacing: 10) {
                Image(systemName: vm.isScanning ? "hourglass" : "chart.bar.xaxis")
                    .font(.system(size: 34))
                    .foregroundStyle(TVTheme.subtext)

                Text(vm.isScanning ? "Taranıyor…" : "Sonuç yok")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(TVTheme.text)

                Text(vm.isScanning ? "Lütfen bekle" : "Tarama başlat veya preset değiştir.")
                    .font(.footnote)
                    .foregroundStyle(TVTheme.subtext)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
    }

    // MARK: - Sort

    private func sortedResults(_ arrIn: [ScanResult]) -> [ScanResult] {
        var arr = arrIn
        switch sort {
        case .scoreDesc:
            arr.sort {
                if $0.uiScore != $1.uiScore { return $0.uiScore > $1.uiScore }
                return $0.changePct > $1.changePct
            }
        case .changeDesc:
            arr.sort { $0.changePct > $1.changePct }
        case .patternsDesc:
            arr.sort { $0.patternCount > $1.patternCount }
        case .symbolAsc:
            arr.sort { $0.symbol.localizedCaseInsensitiveCompare($1.symbol) == .orderedAscending }
        }
        return arr
    }
}

// MARK: - TV Row

private struct ScanRowTV: View {
    let r: ScanResult
    @AppStorage(BacktestKeys.takeProfitPct) private var takeProfitPct: Double = 20.0
    @AppStorage(BacktestKeys.stopLossPct) private var stopLossPct: Double = 6.0
    @AppStorage(BacktestKeys.maxHoldDays) private var maxHoldDays: Double = 30
    @AppStorage(BacktestKeys.cooldownDays) private var cooldownDays: Double = 3
    @AppStorage(BacktestKeys.commissionBps) private var commissionBps: Double = 12
    @AppStorage(BacktestKeys.slippageBps) private var slippageBps: Double = 8

    private var changeText: String { String(format: "%+.2f%%", r.changePct) }
    private var qualityText: String { r.uiQuality }
    private var metaLine: String? { r.uiMetaLine }

    private var sortedPatterns: [CandlePatternScore] {
        r.patterns.sorted { $0.score > $1.score }
    }

    private var chips: [String] {
        if let reasons = r.tomorrowReasons, !reasons.isEmpty {
            return Array(reasons.prefix(3))
        }
        let p = sortedPatterns.map { $0.pattern.rawValue }
        return Array(p.prefix(3))
    }

    private var qualityColor: Color {
        switch qualityText {
        case "A+": return TVTheme.up
        case "A":  return TVTheme.up.opacity(0.85)
        case "B":  return Color(red: 0.85, green: 0.65, blue: 0.15) // amber
        case "C":  return TVTheme.subtext
        default:   return TVTheme.subtext.opacity(0.85)
        }
    }

    private func qualityMultiplier(_ q: String) -> Double {
        switch q {
        case "A+": return 1.15
        case "A":  return 1.00
        case "B":  return 0.85
        case "C":  return 0.70
        default:   return 0.55
        }
    }

    var body: some View {
        let cfg = BacktestExitConfig(
            takeProfitPct: takeProfitPct,
            stopLossPct: stopLossPct,
            maxHoldDays: Int(maxHoldDays),
            cooldownDays: Int(cooldownDays)
        )
        let signalDate = r.lastDate
        let projectedExit = Calendar.current.date(byAdding: .day, value: cfg.maxHoldDays, to: signalDate) ?? signalDate

        VStack(alignment: .leading, spacing: 10) {

            HStack(alignment: .firstTextBaseline) {
                Text(r.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(TVTheme.text)

                Spacer()

                HStack(spacing: 10) {
                    ScorePill(score: r.uiScore)

                    Text(qualityText)
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(qualityColor.opacity(0.18))
                        .clipShape(Capsule())
                        .foregroundStyle(qualityColor)
                }
            }

            HStack(spacing: 10) {
                Text(r.lastDate, format: .dateTime.day().month().year())
                    .font(.caption)
                    .foregroundStyle(TVTheme.subtext)

                Text(String(format: "%.2f", r.lastClose))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TVTheme.subtext)

                Spacer()

                Text(changeText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(r.changePct >= 0 ? TVTheme.up : TVTheme.down)
            }

            HStack(spacing: 10) {
                Text("Sinyal: \(signalDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption2)
                    .foregroundStyle(TVTheme.subtext)
                Text("Max Çıkış: \(projectedExit.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption2)
                    .foregroundStyle(TVTheme.subtext)
                Spacer()
            }

            if let metaLine {
                Text(metaLine)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TVTheme.subtext)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            // ── Çıkış Stratejisi (TP/SL hedefleri) ──
            exitTargetsRow

            scoreBar

            if !chips.isEmpty {
                HStack(spacing: 8) {
                    TVChip(chips[0], systemImage: "sparkles")
                    if chips.count >= 2 { TVChip(chips[1], systemImage: "sparkles") }
                    if chips.count >= 3 { TVChip(chips[2], systemImage: "sparkles") }
                    Spacer()
                }
            }
        }
        .padding(14)
        .background(TVTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(TVTheme.stroke, lineWidth: 1)
        )
    }

    // ── Exit Targets (TP/SL/R:R) ──
    private var exitTargetsRow: some View {
        let price = r.lastClose
        let cfg = BacktestExitConfig(
            takeProfitPct: takeProfitPct,
            stopLossPct: stopLossPct,
            maxHoldDays: Int(maxHoldDays),
            cooldownDays: Int(cooldownDays)
        )

        let totalBps = (commissionBps + slippageBps) / 10_000.0
        let entryNet = price * (1.0 + totalBps)
        let tpPrice = price * (1.0 + cfg.takeProfitPct / 100.0)
        let slPrice = price * (1.0 - cfg.stopLossPct / 100.0)
        let tpNet = tpPrice * (1.0 - totalBps)
        let slNet = slPrice * (1.0 - totalBps)
        let netRewardPct = entryNet > 0 ? ((tpNet - entryNet) / entryNet) * 100.0 : 0
        let netRiskPct = entryNet > 0 ? ((entryNet - slNet) / entryNet) * 100.0 : 0
        let rr = netRiskPct > 0 ? netRewardPct / netRiskPct : 0
        let expectedR = rr * qualityMultiplier(qualityText)

        return HStack(spacing: 6) {
            // TP
            HStack(spacing: 3) {
                Text("🎯")
                    .font(.system(size: 9))
                Text(String(format: "%.2f", tpPrice))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(TVTheme.up)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(TVTheme.up.opacity(0.10))
            .clipShape(Capsule())

            // SL
            HStack(spacing: 3) {
                Text("🛑")
                    .font(.system(size: 9))
                Text(String(format: "%.2f", slPrice))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(TVTheme.down)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(TVTheme.down.opacity(0.10))
            .clipShape(Capsule())

            // R:R
            HStack(spacing: 3) {
                Text("⚖️")
                    .font(.system(size: 9))
                Text(String(format: "Net 1:%.1f", rr))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(rr >= 2.5 ? TVTheme.up : (rr >= 1.5 ? .orange : TVTheme.down))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(TVTheme.surface2)
            .clipShape(Capsule())

            HStack(spacing: 3) {
                Text("📈")
                    .font(.system(size: 9))
                Text(String(format: "ER %.2fR", expectedR))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(expectedR >= 2.0 ? TVTheme.up : (expectedR >= 1.2 ? .orange : TVTheme.down))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(TVTheme.surface2)
            .clipShape(Capsule())

            // Max days
            HStack(spacing: 3) {
                Text("⏰")
                    .font(.system(size: 9))
                Text("\(cfg.maxHoldDays)g")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(TVTheme.subtext)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(TVTheme.surface2)
            .clipShape(Capsule())

            Spacer()
        }
    }

    private var scoreBar: some View {
        let pct = min(max(Double(r.uiScore) / 100.0, 0), 1)

        return GeometryReader { geo in
            let w = geo.size.width

            let fill: Color = {
                switch qualityText {
                case "A+", "A": return TVTheme.up
                case "B":       return Color(red: 0.85, green: 0.65, blue: 0.15)
                default:        return TVTheme.subtext
                }
            }()

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(TVTheme.surface2)

                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(fill.opacity(0.60))
                    .frame(width: max(10, w * pct))
            }
        }
        .frame(height: 10)
    }
}

import SwiftUI

struct BacktestView: View {
    @ObservedObject var engine: BacktestEngine
    private let initialCapitalTL: Double = 100_000
    private let hardMaxPerPositionTL: Double = 5_000

    @State private var selectedIndex: IndexOption = .xu030
    @AppStorage(BacktestKeys.scanPreset) private var selectedPresetRaw: String = TomorrowPreset.normal.rawValue
    @AppStorage(BacktestKeys.strategyMode) private var selectedStrategyModeRaw: String = ScanStrategyMode.preBreakout.rawValue
    @AppStorage(BacktestKeys.ultraPreset) private var selectedUltraPresetRaw: String = UltraPreset.hunter.rawValue

    // ── Exit Config (Multi-Day) ──
    @AppStorage(BacktestKeys.tp1Pct) private var tp1Pct: Double = 5.0
    @AppStorage(BacktestKeys.tp2Pct) private var tp2Pct: Double = 10.0
    @AppStorage(BacktestKeys.tp1SellPercent) private var tp1SellPercent: Double = 50.0
    @AppStorage(BacktestKeys.takeProfitPct) private var legacyTakeProfitPct: Double = 10.0
    @AppStorage(BacktestKeys.stopLossPct) private var stopLossPct: Double = 6.0
    @AppStorage(BacktestKeys.maxHoldDays) private var maxHoldDays: Double = 30
    @AppStorage(BacktestKeys.cooldownDays) private var cooldownDays: Double = 3
    @AppStorage(BacktestKeys.commissionBps) private var commissionBps: Double = 12
    @AppStorage(BacktestKeys.slippageBps) private var slippageBps: Double = 8
    @AppStorage(BacktestKeys.minPerPositionTL) private var minPerPositionTL: Double = 400
    @AppStorage(BacktestKeys.maxPerPositionTL) private var maxPerPositionTL: Double = 5_000
    @AppStorage(BacktestKeys.addOnMode) private var addOnMode: Int = 0
    @AppStorage(BacktestKeys.addOnWaitDays) private var addOnWaitDays: Double = 5

    @State private var showStrategyEditor = false
    @State private var portfolioSimulation: PortfolioSimulationResult?
    @State private var isComputingPortfolioSimulation = false
    @State private var portfolioSimulationTask: Task<Void, Never>?
    @State private var expandedCashFlowDayKeys: Set<TimeInterval> = []

    private var exitConfig: BacktestExitConfig {
        BacktestExitConfig(
            tp1Pct: tp1Pct,
            tp2Pct: tp2Pct,
            tp1SellPercent: tp1SellPercent,
            stopLossPct: stopLossPct,
            maxHoldDays: Int(maxHoldDays),
            cooldownDays: Int(cooldownDays),
            commissionBps: commissionBps,
            slippageBps: slippageBps
        )
    }

    private var portfolioConfig: BacktestPortfolioConfig {
        BacktestPortfolioConfig(
            addOnMode: BacktestAddOnMode(rawValue: addOnMode) ?? .off,
            addOnWaitDays: Int(addOnWaitDays)
        )
    }

    private var selectedPreset: TomorrowPreset {
        TomorrowPreset(rawValue: selectedPresetRaw) ?? .normal
    }

    private var selectedStrategyMode: ScanStrategyMode {
        ScanStrategyMode(rawValue: selectedStrategyModeRaw) ?? .preBreakout
    }

    private var selectedUltraPreset: UltraPreset {
        UltraPreset(rawValue: selectedUltraPresetRaw) ?? .hunter
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DS.s16) {
                configCard
                exitConfigCard
                actionCard

                if engine.isRunning {
                    progressCard
                }

                if let e = engine.errorText {
                    errorCard(e)
                }

                if engine.summary.totalSignals > 0 {
                    summaryCard
                    portfolioSimulationCard
                    exitBreakdownCard
                    tradesList
                }
            }
            .padding(.horizontal, DS.s16)
            .padding(.vertical, DS.s12)
        }
        .navigationTitle("Backtest")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showStrategyEditor) {
            NavigationStack {
                StrategyConfigEditorView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Kapat") { showStrategyEditor = false }
                                .foregroundStyle(TVTheme.text)
                        }
                    }
            }
            .presentationBackground(TVTheme.bg)
        }
        .onAppear {
            if tp2Pct <= 0 {
                tp2Pct = min(max(legacyTakeProfitPct, 4), 40)
            }
            tp2Pct = min(max(tp2Pct, 4), 40)
            tp1Pct = min(max(tp1Pct, 1), 30)
            if tp1Pct >= tp2Pct { tp1Pct = max(1, tp2Pct - 1) }
            tp1SellPercent = min(max(tp1SellPercent, 10), 90)
            legacyTakeProfitPct = tp2Pct
            stopLossPct = min(max(stopLossPct, 2), 15)
            maxHoldDays = min(max(maxHoldDays, 5), 60)
            cooldownDays = min(max(cooldownDays, 0), 10)
            commissionBps = min(max(commissionBps, 0), 100)
            slippageBps = min(max(slippageBps, 0), 100)
            minPerPositionTL = min(max(minPerPositionTL, 100), hardMaxPerPositionTL)
            maxPerPositionTL = min(max(maxPerPositionTL, 100), hardMaxPerPositionTL)
            if minPerPositionTL > maxPerPositionTL {
                minPerPositionTL = maxPerPositionTL
            }
            addOnMode = min(max(addOnMode, 0), 2)
            addOnWaitDays = min(max(addOnWaitDays, 1), 30)
            recomputePortfolioSimulation()
        }
        .onChange(of: engine.summary.totalSignals) { _ in
            recomputePortfolioSimulation()
        }
        .onChange(of: minPerPositionTL) { _ in
            if minPerPositionTL > maxPerPositionTL { minPerPositionTL = maxPerPositionTL }
            recomputePortfolioSimulation()
        }
        .onChange(of: maxPerPositionTL) { _ in
            if maxPerPositionTL < minPerPositionTL { maxPerPositionTL = minPerPositionTL }
            recomputePortfolioSimulation()
        }
        .onDisappear {
            portfolioSimulationTask?.cancel()
            portfolioSimulationTask = nil
        }
        .tvBackground()
    }

    private var addOnModeLabel: String {
        switch addOnMode {
        case 1: return "Ek Alım: Serbest"
        case 2: return "Ek Alım: \(Int(addOnWaitDays))g"
        default: return "Ek Alım: Kapalı"
        }
    }

    // MARK: - Sinyal Config

    private var configCard: some View {
        TVCard {
            VStack(spacing: DS.s12) {
                HStack {
                    Text("Sinyal Ayarları")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(TVTheme.text)
                    Spacer()

                    Button {
                        showStrategyEditor = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "slider.horizontal.3")
                            Text("Strateji")
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(TVTheme.text)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(TVTheme.surface2)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(TVTheme.stroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }

                Picker("Endeks", selection: $selectedIndex) {
                    ForEach(IndexOption.allCases) { opt in
                        Text(opt.title).tag(opt)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 12) {
                    Text("Preset")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(TVTheme.subtext)

                    Picker("Preset", selection: Binding(
                        get: { selectedPreset },
                        set: { selectedPresetRaw = $0.rawValue }
                    )) {
                        ForEach(TomorrowPreset.allCases, id: \.self) { p in
                            Text(p.title).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(selectedStrategyMode != .preBreakout)
                    .opacity(selectedStrategyMode == .preBreakout ? 1 : 0.45)
                }

                HStack(spacing: 12) {
                    Text("Strateji")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(TVTheme.subtext)

                    Picker("Strateji", selection: Binding(
                        get: { selectedStrategyMode },
                        set: { selectedStrategyModeRaw = $0.rawValue }
                    )) {
                        Text("Pre-Breakout").tag(ScanStrategyMode.preBreakout)
                        Text("Ultra Bounce").tag(ScanStrategyMode.ultraBounce)
                    }
                    .pickerStyle(.segmented)
                }

                if selectedStrategyMode == .ultraBounce {
                    HStack(spacing: 12) {
                        Text("Ultra Preset")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(TVTheme.subtext)

                        Picker("Ultra Preset", selection: Binding(
                            get: { selectedUltraPreset },
                            set: { selectedUltraPresetRaw = $0.rawValue }
                        )) {
                            Text("Sniper").tag(UltraPreset.sniper)
                            Text("Hunter").tag(UltraPreset.hunter)
                            Text("Scout").tag(UltraPreset.scout)
                        }
                        .pickerStyle(.segmented)
                    }
                }

                Text("Backtest sinyal modu: Pre-Breakout veya Ultra Bounce. Ultra modda Sniper/Hunter/Scout eşikleri kullanılır.")
                    .font(.footnote)
                    .foregroundStyle(TVTheme.subtext)
            }
        }
    }

    // MARK: - Exit Config

    private var exitConfigCard: some View {
        TVCard {
            VStack(alignment: .leading, spacing: DS.s12) {
                HStack {
                    Text("Çıkış Stratejisi")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(TVTheme.text)
                    Spacer()
                    TVChip("Multi-Day", systemImage: "calendar.badge.clock")
                }

                // Take Profit
                sliderRow(
                    title: "🎯 TP1 (İlk Kâr Al)",
                    value: $tp1Pct,
                    range: 1...30,
                    step: 0.5,
                    format: "+%.1f%%"
                )

                sliderRow(
                    title: "🎯 TP2 (Nihai Kâr Al)",
                    value: $tp2Pct,
                    range: 4...40,
                    step: 0.5,
                    format: "+%.1f%%"
                )

                sliderRow(
                    title: "📦 TP1 Satış Oranı",
                    value: $tp1SellPercent,
                    range: 10...90,
                    step: 5,
                    format: "%%%.0f"
                )

                // Stop Loss
                sliderRow(
                    title: "🛑 Zarar Kes (SL)",
                    value: $stopLossPct,
                    range: 2...15,
                    step: 0.5,
                    format: "-%.1f%%"
                )

                // Max Hold Days
                sliderRow(
                    title: "⏰ Max Süre",
                    value: $maxHoldDays,
                    range: 5...60,
                    step: 1,
                    format: "%.0f gün"
                )

                // Cooldown Days
                sliderRow(
                    title: "⏳ Cooldown",
                    value: $cooldownDays,
                    range: 0...10,
                    step: 1,
                    format: "%.0f gün"
                )

                sliderRow(
                    title: "💸 Komisyon (tek yön)",
                    value: $commissionBps,
                    range: 0...100,
                    step: 1,
                    format: "%.0f bps"
                )

                sliderRow(
                    title: "↔️ Slippage (tek yön)",
                    value: $slippageBps,
                    range: 0...100,
                    step: 1,
                    format: "%.0f bps"
                )

                sliderRow(
                    title: "💵 Hisse Başı Min",
                    value: $minPerPositionTL,
                    range: 100...5_000,
                    step: 100,
                    format: "₺%.0f"
                )

                sliderRow(
                    title: "💵 Hisse Başı Max",
                    value: $maxPerPositionTL,
                    range: 100...5_000,
                    step: 100,
                    format: "₺%.0f"
                )

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("➕ Açık Pozisyonda Ek Alım")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(TVTheme.text)
                        Spacer()
                    }
                    Picker("Ek Alım", selection: $addOnMode) {
                        Text("Kapalı").tag(0)
                        Text("Serbest").tag(1)
                        Text("X Gün Sonra").tag(2)
                    }
                    .pickerStyle(.segmented)

                    if addOnMode == 2 {
                        sliderRow(
                            title: "⏱️ Ek Alım Bekleme",
                            value: $addOnWaitDays,
                            range: 1...30,
                            step: 1,
                            format: "%.0f gün"
                        )
                    }
                }

                // Config summary
                HStack(spacing: 8) {
                    Button("LargeCap 8/4") {
                        commissionBps = 8
                        slippageBps = 4
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(TVTheme.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(TVTheme.surface2)
                    .clipShape(Capsule())
                    .buttonStyle(.plain)

                    Button("Mid/Small 12/8") {
                        commissionBps = 12
                        slippageBps = 8
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(TVTheme.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(TVTheme.surface2)
                    .clipShape(Capsule())
                    .buttonStyle(.plain)

                    Spacer()
                }

                HStack(spacing: 8) {
                    miniChip("TP1 +\(String(format: "%.1f", tp1Pct))%", TVTheme.up)
                    miniChip("TP2 +\(String(format: "%.1f", tp2Pct))%", TVTheme.up)
                    miniChip("TP1 Sat %\(Int(tp1SellPercent))", TVTheme.subtext)
                    miniChip("SL -\(String(format: "%.1f", stopLossPct))%", TVTheme.down)
                    miniChip("\(Int(maxHoldDays))g", TVTheme.subtext)
                    miniChip("Kom \(Int(commissionBps))bps", TVTheme.subtext)
                    miniChip("Slip \(Int(slippageBps))bps", TVTheme.subtext)
                    miniChip("Min ₺\(Int(minPerPositionTL))", TVTheme.subtext)
                    miniChip("Max ₺\(Int(maxPerPositionTL))", TVTheme.subtext)
                    miniChip(addOnModeLabel, TVTheme.subtext)
                }

                Text("Sinyal günü kapanışta giriş → TP1'de kısmi satış, TP2/SL/MaxDays ile kalan lot yönetimi. Komisyon + slippage tek yön bps olarak net getiriye uygulanır. Nakit o günün önerilerine tek tur paylaştırılır; hisse başı min/max tutarları uygulanır.")
                    .font(.footnote)
                    .foregroundStyle(TVTheme.subtext)
            }
        }
    }

    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, format: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TVTheme.text)
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(TVTheme.subtext)
            }
            Slider(value: value, in: range, step: step)
                .tint(TVTheme.up)
        }
    }

    private func miniChip(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }

    // MARK: - Action

    private var actionCard: some View {
        HStack(spacing: 12) {
            Button {
                engine.run(
                    indexOption: selectedIndex,
                    preset: selectedPreset,
                    strategyMode: selectedStrategyMode,
                    ultraPreset: selectedUltraPreset,
                    exitConfig: exitConfig,
                    portfolioConfig: portfolioConfig
                )
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                    Text("Backtest Başlat")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(engine.isRunning ? Color.gray : TVTheme.up)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(engine.isRunning)
            .buttonStyle(.plain)

            if engine.isRunning {
                Button {
                    engine.cancel()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "stop.fill")
                        Text("Durdur")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(TVTheme.down)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Progress

    private var progressCard: some View {
        TVCard {
            VStack(alignment: .leading, spacing: DS.s12) {
                HStack {
                    Text("İlerleme")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(TVTheme.text)
                    Spacer()
                    Text("\(Int(engine.progress * 100))%")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(TVTheme.subtext)
                }

                ProgressView(value: engine.progress)
                    .tint(TVTheme.text)

                Text(engine.progressText)
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
            }
        }
    }

    // MARK: - Summary

    private var summaryCard: some View {
        let s = engine.summary

        return TVCard {
            VStack(alignment: .leading, spacing: DS.s12) {
                HStack {
                    Text("Backtest Sonucu")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(TVTheme.text)
                    Spacer()

                    Text(String(format: "WR: %.0f%%", s.winRate * 100))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(s.winRate >= 0.70 ? TVTheme.up : (s.winRate >= 0.55 ? TVTheme.text : TVTheme.down))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background((s.winRate >= 0.70 ? TVTheme.up : TVTheme.down).opacity(0.15))
                        .clipShape(Capsule())
                }

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 10) {
                    statCell("Toplam Sinyal", "\(s.totalSignals)")
                    statCell("Kazanan", "\(s.wins)", color: TVTheme.up)
                    statCell("Kaybeden", "\(s.losses)", color: TVTheme.down)

                    statCell("Ort. Getiri", String(format: "%+.2f%%", s.avgReturn),
                             color: s.avgReturn >= 0 ? TVTheme.up : TVTheme.down)
                    statCell("Ort. Kâr", String(format: "%+.2f%%", s.avgWinReturn), color: TVTheme.up)
                    statCell("Ort. Zarar", String(format: "%+.2f%%", s.avgLossReturn), color: TVTheme.down)

                    statCell("Max Kâr", String(format: "%+.2f%%", s.maxWin), color: TVTheme.up)
                    statCell("Max Zarar", String(format: "%+.2f%%", s.maxLoss), color: TVTheme.down)
                    statCell("Profit Factor", String(format: "%.2f", s.profitFactor),
                             color: s.profitFactor >= 1.5 ? TVTheme.up : (s.profitFactor >= 1.0 ? TVTheme.text : TVTheme.down))

                    statCell("Ort. Gün", String(format: "%.1f", s.avgDaysHeld))
                    statCell("Ort. Peak", String(format: "%+.1f%%", s.avgPeakReturn), color: TVTheme.up)
                    statCell("Ort. DD", String(format: "%.1f%%", s.avgDrawdown), color: TVTheme.down)
                    statCell("Expectancy", String(format: "%+.2f%%", s.expectancyPct),
                             color: s.expectancyPct >= 0 ? TVTheme.up : TVTheme.down)
                }

                regimePerformanceCard(trades: s.trades)
            }
        }
    }

    private struct RegimeStat: Identifiable {
        let regime: String
        let count: Int
        let winRate: Double
        let expectancy: Double
        let avgDrawdown: Double
        var id: String { regime }
    }

    private func regimePerformanceCard(trades: [BacktestTradeResult]) -> some View {
        let groups = Dictionary(grouping: trades, by: { $0.regime })
        let stats: [RegimeStat] = ["Bull", "Sideways", "Bear"].compactMap { r in
            guard let arr = groups[r], !arr.isEmpty else { return nil }
            let wins = arr.filter(\.isWin).count
            let wr = Double(wins) / Double(arr.count)
            let avg = arr.map(\.returnPct).reduce(0, +) / Double(arr.count)
            let dd = arr.map(\.maxDrawdownPct).reduce(0, +) / Double(arr.count)
            return RegimeStat(regime: r, count: arr.count, winRate: wr, expectancy: avg, avgDrawdown: dd)
        }

        return VStack(alignment: .leading, spacing: 8) {
            Text("Rejim Bazlı Performans")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(TVTheme.text)

            if stats.isEmpty {
                Text("Rejim verisi yok")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(TVTheme.subtext)
            } else {
                ForEach(stats) { st in
                    HStack(spacing: 8) {
                        Text(st.regime)
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 70, alignment: .leading)
                            .foregroundStyle(TVTheme.text)

                        Text("n=\(st.count)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(TVTheme.subtext)

                        Spacer()

                        Text(String(format: "WR %.0f%%", st.winRate * 100))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(st.winRate >= 0.55 ? TVTheme.up : TVTheme.down)

                        Text(String(format: "Exp %+.2f%%", st.expectancy))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(st.expectancy >= 0 ? TVTheme.up : TVTheme.down)

                        Text(String(format: "DD %.1f%%", st.avgDrawdown))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(TVTheme.down)
                    }
                }
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Exit Breakdown

    private struct PortfolioSimulationResult: Sendable {
        let initialCapital: Double
        let finalCapital: Double
        let endingCash: Double
        let openCapital: Double
        let totalReturnPct: Double
        let annualizedReturnPct: Double
        let investedSignals: Int
        let skippedSignals: Int
        let openPositions: Int
        let totalSignals: Int
        let holdings: [PortfolioHolding]
        let events: [PortfolioEvent]
    }

    private struct PortfolioHolding: Identifiable, Sendable {
        var id: String { symbol }
        let symbol: String
        let lots: Double
        let markToMarketTL: Double
    }

    private struct PortfolioEvent: Identifiable, Sendable {
        enum Kind: Sendable {
            case buy
            case sell
            case skip
        }

        let id = UUID()
        let date: Date
        let kind: Kind
        let symbol: String
        let amountTL: Double
        let cashAfterTL: Double
        let note: String
        let holdingsText: String
    }

    private struct CashFlowDaySection: Identifiable {
        let day: Date
        let events: [PortfolioEvent]
        let endCashTL: Double
        let endHoldingsText: String

        var dayKey: TimeInterval { day.timeIntervalSinceReferenceDate }
        var id: TimeInterval { dayKey }
    }

    private var portfolioSimulationCard: some View {
        return TVCard {
            VStack(alignment: .leading, spacing: DS.s12) {
                Text("100.000 TL Portföy Simülasyonu")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(TVTheme.text)

                if isComputingPortfolioSimulation && portfolioSimulation == nil {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(TVTheme.text)
                        Text("Simülasyon hazırlanıyor…")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(TVTheme.subtext)
                    }
                } else if let result = portfolioSimulation {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 10) {
                        statCell("Başlangıç", String(format: "₺%.0f", result.initialCapital))
                        statCell("Final", String(format: "₺%.0f", result.finalCapital),
                                 color: result.finalCapital >= result.initialCapital ? TVTheme.up : TVTheme.down)
                        statCell("Toplam Getiri", String(format: "%+.1f%%", result.totalReturnPct),
                                 color: result.totalReturnPct >= 0 ? TVTheme.up : TVTheme.down)

                        statCell("Yıllıklandırılmış", String(format: "%+.1f%%", result.annualizedReturnPct),
                                 color: result.annualizedReturnPct >= 0 ? TVTheme.up : TVTheme.down)
                        statCell("Yatırım Yapılan", "\(result.investedSignals)")
                        statCell("Toplam Sinyal", "\(result.totalSignals)")
                        statCell("Hisse Başı Min", String(format: "₺%.0f", minPerPositionTL))
                        statCell("Hisse Başı Max", String(format: "₺%.0f", maxPerPositionTL))
                        statCell("Atlanan", "\(result.skippedSignals)", color: result.skippedSignals > 0 ? .orange : TVTheme.text)
                        statCell("Açık Pozisyon", "\(result.openPositions)")
                        statCell("Açık Sermaye", String(format: "₺%.0f", max(0, result.openCapital)))
                        statCell("Nakit", String(format: "₺%.0f", max(0, result.endingCash)))
                    }

                    Text("Varsayım: Kaldıraç yok. Her gün önce çıkışlar işlenir, sonra o günün al sinyallerine nakit paylaştırılır. Hisse başı min/max limiti uygulanır.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(TVTheme.subtext)

                    if !result.events.isEmpty {
                        Divider().overlay(TVTheme.stroke)
                        Text("Gün Sonu Hareketleri")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(TVTheme.subtext)

                        ForEach(cashFlowDaySections(from: result.events)) { section in
                            dayCashFlowCard(section)
                        }
                    }
                } else {
                    Text("Simülasyon sonucu bekleniyor.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(TVTheme.subtext)
                }
            }
        }
    }

    private func cashFlowRow(_ e: PortfolioEvent) -> some View {
        let color: Color = {
            switch e.kind {
            case .buy: return TVTheme.up
            case .sell: return Color(red: 0.88, green: 0.70, blue: 0.18)
            case .skip: return TVTheme.subtext
            }
        }()

        let action: String = {
            switch e.kind {
            case .buy: return "AL"
            case .sell: return "SAT"
            case .skip: return "PAS"
            }
        }()

        return HStack(spacing: 8) {
            Text(e.date.formatted(date: .abbreviated, time: .omitted))
                .font(.caption2)
                .foregroundStyle(TVTheme.subtext)
                .frame(width: 78, alignment: .leading)

            Text(action)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color.opacity(0.15))
                .clipShape(Capsule())

            Text(e.symbol.replacingOccurrences(of: ".IS", with: ""))
                .font(.caption.weight(.semibold))
                .foregroundStyle(TVTheme.text)
                .frame(width: 56, alignment: .leading)

            Text(String(format: "₺%.0f", e.amountTL))
                .font(.caption)
                .foregroundStyle(color)

            Text(e.note)
                .font(.caption2)
                .foregroundStyle(TVTheme.subtext)
                .lineLimit(1)

            Spacer()

            Text(String(format: "Nakit ₺%.0f", e.cashAfterTL))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(TVTheme.subtext)
        }
        .padding(8)
        .background(TVTheme.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func dayCashFlowCard(_ section: CashFlowDaySection) -> some View {
        let isExpanded = expandedCashFlowDayKeys.contains(section.dayKey)

        return VStack(alignment: .leading, spacing: 8) {
            Button {
                if isExpanded {
                    expandedCashFlowDayKeys.remove(section.dayKey)
                } else {
                    expandedCashFlowDayKeys.insert(section.dayKey)
                }
            } label: {
                HStack(spacing: 10) {
                    Text(section.day.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(TVTheme.text)

                    Text("\(section.events.count) hareket")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(TVTheme.subtext)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(TVTheme.surface2)
                        .clipShape(Capsule())

                    Spacer()

                    Text("Nakit ₺\(Int(section.endCashTL))")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(TVTheme.subtext)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(TVTheme.subtext)
                }
            }
            .buttonStyle(.plain)

            Text("Gün sonu elde: \(section.endHoldingsText)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(TVTheme.subtext)
                .lineLimit(2)

            if isExpanded {
                ForEach(Array(section.events.reversed())) { e in
                    cashFlowRow(e)
                }
            }
        }
        .padding(10)
        .background(TVTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(TVTheme.stroke, lineWidth: 1)
        )
    }

    private func cashFlowDaySections(from events: [PortfolioEvent]) -> [CashFlowDaySection] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: events) { cal.startOfDay(for: $0.date) }

        return grouped.keys.sorted(by: >).map { day in
            let dayEvents = grouped[day] ?? []
            let dayEnd = dayEvents.last
            return CashFlowDaySection(
                day: day,
                events: dayEvents,
                endCashTL: dayEnd?.cashAfterTL ?? 0,
                endHoldingsText: dayEnd?.holdingsText ?? "Yok"
            )
        }
    }

    nonisolated private static func simulatePortfolioFromSignals(
        initialCapital: Double,
        trades: [BacktestTradeResult],
        minPerPositionTL: Double,
        maxPerPositionTL: Double,
        hardMaxPerPositionTL: Double
    ) -> PortfolioSimulationResult {
        guard !trades.isEmpty else {
            return PortfolioSimulationResult(
                initialCapital: initialCapital,
                finalCapital: initialCapital,
                endingCash: initialCapital,
                openCapital: 0,
                totalReturnPct: 0,
                annualizedReturnPct: 0,
                investedSignals: 0,
                skippedSignals: 0,
                openPositions: 0,
                totalSignals: 0,
                holdings: [],
                events: []
            )
        }

        let cal = Calendar.current
        let orderedTrades = trades.sorted { $0.entryDate < $1.entryDate }
        let entryBuckets = Dictionary(grouping: orderedTrades) { cal.startOfDay(for: $0.entryDate) }

        struct OpenPosition {
            let invested: Double
            let symbol: String
            let lots: Double
            let entryDay: Date
            let returnPct: Double
            let exitDay: Date
            let exitReason: ExitReason
            let daysHeld: Int
        }

        var cash = initialCapital
        var open: [UUID: OpenPosition] = [:]
        var investedSignals = 0
        var skippedSignals = 0
        var events: [PortfolioEvent] = []
        let maxEventCount = 240

        func holdingsSummaryText(_ openPositions: [UUID: OpenPosition]) -> String {
            guard !openPositions.isEmpty else { return "Yok" }
            var bySymbol: [String: Double] = [:]
            for p in openPositions.values {
                bySymbol[p.symbol, default: 0] += p.lots
            }
            return bySymbol
                .sorted { $0.value > $1.value }
                .map { "\($0.key.replacingOccurrences(of: ".IS", with: "")) \(String(format: "%.2f", $0.value))" }
                .joined(separator: " | ")
        }

        func appendEvent(_ event: PortfolioEvent) {
            events.append(event)
            if events.count > maxEventCount {
                events.removeFirst(events.count - maxEventCount)
            }
        }

        let entryDays = Set(entryBuckets.keys)
        let exitDays = Set(orderedTrades.map { cal.startOfDay(for: $0.exitDate) })
        let timeline = Array(entryDays.union(exitDays)).sorted()

        for day in timeline {
            let closingIDs = open.compactMap { id, p in
                (p.exitReason != .open && p.exitDay == day) ? id : nil
            }
            for id in closingIDs {
                if let p = open.removeValue(forKey: id) {
                    let proceeds = p.invested * (1.0 + p.returnPct / 100.0)
                    cash += proceeds
                    appendEvent(
                        PortfolioEvent(
                            date: day,
                            kind: .sell,
                            symbol: p.symbol,
                            amountTL: proceeds,
                            cashAfterTL: cash,
                            note: "\(p.exitReason.rawValue) • \(p.daysHeld)g • " + String(format: "%+.1f%%", p.returnPct),
                            holdingsText: holdingsSummaryText(open)
                        )
                    )
                }
            }

            let todaysSignals = (entryBuckets[day] ?? []).sorted { $0.signalScore > $1.signalScore }
            if !todaysSignals.isEmpty && cash > 0 {
                var eligible: [BacktestTradeResult] = []
                var seenSymbols: Set<String> = []
                for t in todaysSignals {
                    // Aynı gün aynı hisseyi tekrar tekrar alma.
                    if seenSymbols.contains(t.symbol) { continue }
                    seenSymbols.insert(t.symbol)
                    eligible.append(t)
                }

                if !eligible.isEmpty {
                    let allocation = cash / Double(eligible.count)
                    let perSymbolCap = min(maxPerPositionTL, hardMaxPerPositionTL)
                    let perSymbolMin = min(max(0, minPerPositionTL), perSymbolCap)

                    for t in eligible {
                        if cash <= 0 {
                            skippedSignals += 1
                            appendEvent(
                                PortfolioEvent(
                                    date: day,
                                    kind: .skip,
                                    symbol: t.symbol,
                                    amountTL: 0,
                                    cashAfterTL: cash,
                                    note: "Nakit yok",
                                    holdingsText: holdingsSummaryText(open)
                                )
                            )
                            continue
                        }

                        let entryDay = cal.startOfDay(for: t.entryDate)
                        let investCap = min(perSymbolCap, allocation, cash)
                        if investCap < perSymbolMin || investCap <= 0 {
                            skippedSignals += 1
                            appendEvent(
                                PortfolioEvent(
                                    date: day,
                                    kind: .skip,
                                    symbol: t.symbol,
                                    amountTL: 0,
                                    cashAfterTL: cash,
                                    note: "Min alım (\(String(format: "₺%.0f", perSymbolMin))) sağlanamadı",
                                    holdingsText: holdingsSummaryText(open)
                                )
                            )
                            continue
                        }
                        let invest = investCap

                        cash -= invest
                        let lots = t.entryPrice > 0 ? (invest / t.entryPrice) : 0
                        open[UUID()] = OpenPosition(
                            invested: invest,
                            symbol: t.symbol,
                            lots: lots,
                            entryDay: entryDay,
                            returnPct: t.returnPct,
                            exitDay: cal.startOfDay(for: t.exitDate),
                            exitReason: t.exitReason,
                            daysHeld: t.daysHeld
                        )
                        investedSignals += 1
                        appendEvent(
                            PortfolioEvent(
                                date: day,
                                kind: .buy,
                                symbol: t.symbol,
                                amountTL: invest,
                                cashAfterTL: cash,
                                note: "S\(t.signalScore) \(t.signalQuality) -> \(t.exitReason.rawValue) \(t.daysHeld)g",
                                holdingsText: holdingsSummaryText(open)
                            )
                        )
                    }
                }
            } else if !todaysSignals.isEmpty {
                skippedSignals += todaysSignals.count
                for t in todaysSignals {
                    appendEvent(
                        PortfolioEvent(
                            date: day,
                            kind: .skip,
                            symbol: t.symbol,
                            amountTL: 0,
                            cashAfterTL: cash,
                            note: "Nakit yok",
                            holdingsText: holdingsSummaryText(open)
                        )
                    )
                }
            }
        }

        let openCapital = open.values.reduce(0) { partial, p in
            partial + (p.invested * (1.0 + p.returnPct / 100.0))
        }
        var holdingsMap: [String: (lots: Double, value: Double)] = [:]
        for p in open.values {
            let mtm = p.invested * (1.0 + p.returnPct / 100.0)
            var current = holdingsMap[p.symbol] ?? (lots: 0, value: 0)
            current.lots += p.lots
            current.value += mtm
            holdingsMap[p.symbol] = current
        }
        let holdings = holdingsMap.map { symbol, agg in
            PortfolioHolding(symbol: symbol, lots: agg.lots, markToMarketTL: agg.value)
        }
        .sorted { $0.markToMarketTL > $1.markToMarketTL }

        let finalCapital = cash + openCapital
        let totalReturnPct = initialCapital > 0 ? ((finalCapital / initialCapital) - 1.0) * 100.0 : 0

        let firstEntry = orderedTrades.map(\.entryDate).min() ?? Date()
        let lastExit = orderedTrades.map(\.exitDate).max() ?? firstEntry
        let totalDays = max(1, cal.dateComponents([.day], from: firstEntry, to: lastExit).day ?? 1)
        let years = Double(totalDays) / 365.25
        let annualizedReturnPct = years > 0 && finalCapital > 0 && initialCapital > 0
            ? (pow(finalCapital / initialCapital, 1.0 / years) - 1.0) * 100.0
            : 0

        return PortfolioSimulationResult(
            initialCapital: initialCapital,
            finalCapital: finalCapital,
            endingCash: cash,
            openCapital: openCapital,
            totalReturnPct: totalReturnPct,
            annualizedReturnPct: annualizedReturnPct,
            investedSignals: investedSignals,
            skippedSignals: skippedSignals,
            openPositions: open.count,
            totalSignals: orderedTrades.count,
            holdings: holdings,
            events: events
        )
    }

    private func recomputePortfolioSimulation() {
        portfolioSimulationTask?.cancel()
        portfolioSimulationTask = nil

        guard engine.summary.totalSignals > 0 else {
            portfolioSimulation = nil
            isComputingPortfolioSimulation = false
            expandedCashFlowDayKeys = []
            return
        }

        let trades = engine.summary.trades
        let initialCapital = initialCapitalTL
        let minPerPosition = minPerPositionTL
        let maxPerPosition = maxPerPositionTL
        let hardMax = hardMaxPerPositionTL
        isComputingPortfolioSimulation = true

        portfolioSimulationTask = Task.detached(priority: .utility) {
            let result = BacktestView.simulatePortfolioFromSignals(
                initialCapital: initialCapital,
                trades: trades,
                minPerPositionTL: minPerPosition,
                maxPerPositionTL: maxPerPosition,
                hardMaxPerPositionTL: hardMax
            )

            if Task.isCancelled { return }

            await MainActor.run {
                self.portfolioSimulation = result
                self.isComputingPortfolioSimulation = false
                if let latest = result.events.last {
                    let latestDay = Calendar.current.startOfDay(for: latest.date)
                    self.expandedCashFlowDayKeys = [latestDay.timeIntervalSinceReferenceDate]
                } else {
                    self.expandedCashFlowDayKeys = []
                }
            }
        }
    }

    private var exitBreakdownCard: some View {
        let s = engine.summary
        let total = max(1, s.totalSignals)

        return TVCard {
            VStack(alignment: .leading, spacing: DS.s12) {
                Text("Çıkış Dağılımı")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(TVTheme.text)

                HStack(spacing: 8) {
                    exitBar("🎯 TP", count: s.tpCount, total: total, color: TVTheme.up)
                    exitBar("🛑 SL", count: s.slCount, total: total, color: TVTheme.down)
                    exitBar("⏰ Süre", count: s.maxDaysCount, total: total, color: TVTheme.subtext)
                    exitBar("🟡 Açık", count: s.openCount, total: total, color: .yellow)
                }

                if s.maxDaysCount > 0 {
                    let maxDaysTotal = max(1, s.maxDaysCount)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Süre Çıkış Kalitesi")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(TVTheme.subtext)
                        HStack(spacing: 8) {
                            exitBar("A+/A", count: s.maxDaysStrongCount, total: maxDaysTotal, color: TVTheme.up)
                            exitBar("B", count: s.maxDaysMediumCount, total: maxDaysTotal, color: .orange)
                            exitBar("C/D", count: s.maxDaysWeakCount, total: maxDaysTotal, color: TVTheme.subtext)
                        }
                    }
                }
            }
        }
    }

    private func exitBar(_ label: String, count: Int, total: Int, color: Color) -> some View {
        let pct = Double(count) / Double(total) * 100
        return VStack(spacing: 4) {
            Text("\(count)")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(color)
            Text(String(format: "%.0f%%", pct))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color.opacity(0.8))
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(TVTheme.subtext)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func statCell(_ title: String, _ value: String, color: Color = TVTheme.text) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(TVTheme.subtext)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(TVTheme.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Trades list

    private var tradesList: some View {
        let trades = engine.summary.trades

        return TVCard {
            VStack(alignment: .leading, spacing: DS.s12) {
                HStack {
                    Text("İşlem Listesi")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(TVTheme.text)
                    Spacer()
                    TVChip("\(trades.count)", systemImage: "list.bullet")
                }

                ForEach(trades.prefix(80)) { trade in
                    tradeRow(trade)
                }
            }
        }
    }

    private func tradeRow(_ t: BacktestTradeResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(t.symbol.replacingOccurrences(of: ".IS", with: ""))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TVTheme.text)

                Text("S\(t.signalScore)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(TVTheme.subtext)

                Text(t.signalQuality)
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(TVTheme.surface2)
                    .clipShape(Capsule())
                    .foregroundStyle(TVTheme.subtext)

                Text(t.exitReason.emoji + " " + t.exitReason.rawValue)
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(exitReasonColor(t.exitReason).opacity(0.15))
                    .clipShape(Capsule())
                    .foregroundStyle(exitReasonColor(t.exitReason))

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: t.isWin ? "arrow.up" : "arrow.down")
                        .font(.system(size: 10, weight: .bold))
                    Text(String(format: "%+.1f%%", t.returnPct))
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(t.isWin ? TVTheme.up : TVTheme.down)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background((t.isWin ? TVTheme.up : TVTheme.down).opacity(0.15))
                .clipShape(Capsule())
            }

            HStack(spacing: 8) {
                Text("Al: \(t.entryDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(TVTheme.subtext)

                Text("Çık: \(t.exitDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(TVTheme.subtext)

                Text("\(t.daysHeld)g")
                    .font(.caption)
                    .foregroundStyle(TVTheme.subtext)

                Spacer()

                Text(String(format: "Prox %.1f%%", (t.proximity - 1.0) * 100))
                    .font(.caption)
                    .foregroundStyle(TVTheme.subtext)

                Text(String(format: "Vol x%.1f", t.volumeTrend))
                    .font(.caption)
                    .foregroundStyle(TVTheme.subtext)

                Text(String(format: "Pk %+.0f%%", t.peakReturnPct))
                    .font(.caption)
                    .foregroundStyle(TVTheme.subtext)
            }
        }
        .padding(10)
        .background(TVTheme.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func exitReasonColor(_ reason: ExitReason) -> Color {
        switch reason {
        case .takeProfit:   return TVTheme.up
        case .stopLoss:     return TVTheme.down
        case .maxDays:      return TVTheme.subtext
        case .open:         return .yellow
        }
    }
}

import SwiftUI

struct BacktestView: View {
    @ObservedObject var engine: BacktestEngine

    @State private var selectedIndex: IndexOption = .xu030
    @State private var selectedPreset: TomorrowPreset = .normal
    @State private var lookback: Int = 20

    @State private var showStrategyEditor = false

    // Manual config (Normal preset bunu kullanıyor)
    private var manualCfg: StrategyConfig { .load() }

    var body: some View {
        ScrollView {
            VStack(spacing: DS.s16) {
                configCard
                actionCard

                if engine.isRunning {
                    progressCard
                }

                if let e = engine.errorText {
                    errorCard(e)
                }

                if engine.summary.totalSignals > 0 {
                    summaryCard
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
        .tvBackground()
    }

    // MARK: - Config

    private var configCard: some View {
        let cfg = manualCfg

        return TVCard {
            VStack(spacing: DS.s12) {
                HStack {
                    Text("Backtest Ayarları")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(TVTheme.text)
                    Spacer()

                    Button {
                        showStrategyEditor = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "slider.horizontal.3")
                            Text("Strateji Ayarı")
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

                    Picker("Preset", selection: $selectedPreset) {
                        ForEach(TomorrowPreset.allCases, id: \.self) { p in
                            Text(p.title).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                HStack(spacing: 12) {
                    Text("Lookback")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(TVTheme.subtext)

                    Picker("Lookback", selection: $lookback) {
                        Text("10").tag(10)
                        Text("15").tag(15)
                        Text("20").tag(20)
                        Text("30").tag(30)
                    }
                    .pickerStyle(.segmented)
                }

                Divider().opacity(0.25)

                // Config summary (manual config'i görünür yap)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Aktif Config Özeti")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(TVTheme.text)
                        Spacer()
                        Text(selectedPreset == .normal ? "Manual" : "Preset Override")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(selectedPreset == .normal ? TVTheme.up : TVTheme.subtext)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            chip("MinScore \(cfg.minScore)", "target")
                            chip(String(format: "CLV ≥ %.2f", cfg.minCLV), "arrow.up.right")
                            chip(String(format: "Value x≥ %.2f", cfg.minValueMultiple), "chart.bar.fill")
                            chip(String(format: "Prox %.3f–%.3f", cfg.minProximity, cfg.maxProximity), "scope")
                            chip(String(format: "Range ≤ %.2f", cfg.maxRangeCompression), "square.3.layers.3d.down.right")
                            chip(String(format: "Today ≤ %.1f%%", cfg.maxTodayChangePct), "percent")
                            chip("LB \(cfg.lookbackDays)d", "calendar")
                        }
                        .padding(.vertical, 2)
                    }

                    Text("Not: Normal preset, kaydettiğin StrategyConfig'i kullanır. Relaxed/Strict kendi override'larını uygular.")
                        .font(.footnote)
                        .foregroundStyle(TVTheme.subtext)
                }
            }
        }
    }

    private func chip(_ text: String, _ icon: String) -> some View {
        TVChip(text, systemImage: icon)
    }

    // MARK: - Action

    private var actionCard: some View {
        HStack(spacing: 12) {
            Button {
                engine.run(
                    indexOption: selectedIndex,
                    preset: selectedPreset,
                    lookback: lookback
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

                    Text(String(format: "Win Rate: %.1f%%", s.winRate * 100))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(s.winRate >= 0.55 ? TVTheme.up : TVTheme.down)
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
                    statCell("Ort. Kar", String(format: "%+.2f%%", s.avgWinReturn), color: TVTheme.up)
                    statCell("Ort. Zarar", String(format: "%+.2f%%", s.avgLossReturn), color: TVTheme.down)

                    statCell("Max Kar", String(format: "%+.2f%%", s.maxWin), color: TVTheme.up)
                    statCell("Max Zarar", String(format: "%+.2f%%", s.maxLoss), color: TVTheme.down)
                    statCell("Profit Factor", String(format: "%.2f", s.profitFactor),
                             color: s.profitFactor >= 1.0 ? TVTheme.up : TVTheme.down)
                }
            }
        }
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
                    Text("Son Sinyaller (D+1 sonucu)")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(TVTheme.text)
                    Spacer()
                    TVChip("\(trades.count)", systemImage: "list.bullet")
                }

                ForEach(trades.prefix(50)) { trade in
                    tradeRow(trade)
                }
            }
        }
    }

    private func tradeRow(_ t: BacktestTradeResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(t.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TVTheme.text)

                Text("Skor \(t.signalScore)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(TVTheme.subtext)

                Text(t.signalQuality)
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(TVTheme.surface2)
                    .clipShape(Capsule())
                    .foregroundStyle(TVTheme.subtext)

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: t.isWin ? "arrow.up" : "arrow.down")
                        .font(.system(size: 10, weight: .bold))
                    Text(String(format: "%+.2f%%", t.nextDayChangePct))
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(t.isWin ? TVTheme.up : TVTheme.down)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background((t.isWin ? TVTheme.up : TVTheme.down).opacity(0.15))
                .clipShape(Capsule())
            }

            HStack(spacing: 8) {
                Text(t.signalDate, format: .dateTime.day().month().year())
                    .font(.caption)
                    .foregroundStyle(TVTheme.subtext)

                Spacer()

                Text(String(format: "Prox %.1f%%", (t.proximity - 1.0) * 100))
                    .font(.caption)
                    .foregroundStyle(TVTheme.subtext)

                Text(String(format: "Vol x%.1f", t.volumeTrend))
                    .font(.caption)
                    .foregroundStyle(TVTheme.subtext)

                Text(String(format: "Range %.2f", t.rangeCompression))
                    .font(.caption)
                    .foregroundStyle(TVTheme.subtext)
            }
        }
        .padding(10)
        .background(TVTheme.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

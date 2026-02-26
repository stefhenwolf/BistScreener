import SwiftUI

struct ScanFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: ScannerViewModel

    @State private var tempPreset: TomorrowPreset
    @State private var tempUltraPreset: UltraPreset
    @State private var tempStrategyMode: ScanStrategyMode
    @State private var tempMaxResults: Int
    @State private var rescanOnApply: Bool = true

    init(vm: ScannerViewModel) {
        self.vm = vm
        _tempPreset = State(initialValue: vm.preset)
        _tempUltraPreset = State(initialValue: vm.ultraPreset)
        _tempStrategyMode = State(initialValue: vm.strategyMode)
        _tempMaxResults = State(initialValue: vm.maxResults)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                TVTheme.bg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: DS.s12) {

                        // 0) Strateji Modu
                        TVCard {
                            VStack(alignment: .leading, spacing: DS.s12) {
                                Text("Strateji Modu")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(TVTheme.text)

                                Picker("Mod", selection: $tempStrategyMode) {
                                    ForEach(ScanStrategyMode.allCases, id: \.self) { mode in
                                        Text(mode.title).tag(mode)
                                    }
                                }
                                .pickerStyle(.segmented)

                                Text(strategyModeDescription(tempStrategyMode))
                                    .font(.footnote)
                                    .foregroundStyle(TVTheme.subtext)
                            }
                        }

                        // 1) Preset
                        TVCard {
                            VStack(alignment: .leading, spacing: DS.s12) {
                                if tempStrategyMode == .ultraBounce {
                                    // Ultra Bounce presets
                                    HStack {
                                        Text("Ultra Preset")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(TVTheme.text)
                                        Spacer()
                                        TVChip(tempUltraPreset.title, systemImage: "bolt.fill")
                                    }

                                    Picker("Ultra Preset", selection: $tempUltraPreset) {
                                        Text("Sniper").tag(UltraPreset.sniper)
                                        Text("Hunter").tag(UltraPreset.hunter)
                                        Text("Scout").tag(UltraPreset.scout)
                                    }
                                    .pickerStyle(.segmented)

                                    Divider().opacity(0.25)

                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(ultraPresetDescription(tempUltraPreset))
                                            .font(.footnote)
                                            .foregroundStyle(TVTheme.subtext)

                                        Text(ultraPresetRulesLine(tempUltraPreset))
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(TVTheme.text.opacity(0.85))
                                    }
                                } else {
                                    // Pre-Breakout presets
                                    HStack {
                                        Text("Strateji Preset’i")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(TVTheme.text)
                                        Spacer()
                                        TVChip(tempPreset.title, systemImage: "slider.horizontal.3")
                                    }

                                    Picker("Preset", selection: $tempPreset) {
                                        Text("Relaxed").tag(TomorrowPreset.relaxed)
                                        Text("Normal").tag(TomorrowPreset.normal)
                                        Text("Strict").tag(TomorrowPreset.strict)
                                    }
                                    .pickerStyle(.segmented)

                                    Divider().opacity(0.25)

                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(presetDescription(tempPreset))
                                            .font(.footnote)
                                            .foregroundStyle(TVTheme.subtext)

                                        Text(presetRulesLine(tempPreset))
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(TVTheme.text.opacity(0.85))
                                    }
                                }
                            }
                        }

                        // 2) Görünüm
                        TVCard {
                            VStack(alignment: .leading, spacing: DS.s12) {
                                HStack {
                                    Text("Görünüm")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(TVTheme.text)
                                    Spacer()
                                    TVChip(vm.selectedIndex.title, systemImage: "chart.bar")
                                }

                                HStack {
                                    Text("Max Sonuç")
                                        .foregroundStyle(TVTheme.subtext)
                                    Spacer()
                                    Picker("", selection: $tempMaxResults) {
                                        Text("Hepsi").tag(0)
                                        Text("25").tag(25)
                                        Text("50").tag(50)
                                        Text("100").tag(100)
                                        Text("200").tag(200)
                                    }
                                    .pickerStyle(.menu)
                                }
                            }
                        }

                        // 3) Apply behavior
                        TVCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Toggle("Uygulayınca yeniden tara", isOn: $rescanOnApply)
                                    .tint(TVTheme.up)

                                Text("Not: Preset değişince BUY koşulları değişir. En doğru sonuç için yeniden tarama önerilir.")
                                    .font(.footnote)
                                    .foregroundStyle(TVTheme.subtext)
                            }
                        }

                        Spacer(minLength: 8)
                    }
                    .padding(.horizontal, DS.s16)
                    .padding(.top, DS.s12)
                    .padding(.bottom, 16)
                }
            }
            .navigationTitle("Filtreler")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(TVTheme.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Kapat") { dismiss() }
                        .foregroundStyle(TVTheme.text)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Uygula") { apply() }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(TVTheme.text)
                }
            }
        }
        .presentationBackground(TVTheme.bg)
    }

    private func apply() {
        vm.strategyMode = tempStrategyMode
        vm.preset = tempPreset
        vm.ultraPreset = tempUltraPreset
        vm.maxResults = tempMaxResults

        dismiss()

        if rescanOnApply {
            if vm.isScanning { vm.cancelScan(silent: true) }
            vm.startScan()
        }
    }

    private func presetDescription(_ p: TomorrowPreset) -> String {
        switch p {
        case .relaxed:
            return "Daha fazla aday gösterir. Eşikler daha gevşektir (daha çok BUY)."
        case .normal:
            return "Dengeli mod. Günlük 0–15 arası BUY hedefi için uygundur."
        case .strict:
            return "En seçici mod. Sinyal sayısı azalır, kalite artar."
        }
    }

    private func presetRulesLine(_ p: TomorrowPreset) -> String {
        switch p {
        case .relaxed:
            return "Min BUY: \(p.minBuyTotal) • Tier C açık"
        case .normal:
            return "Min BUY: \(p.minBuyTotal) • Tier C açık"
        case .strict:
            return "Min BUY: \(p.minBuyTotal) • Tier C kapalı"
        }
    }

    // MARK: - Ultra Descriptions

    private func strategyModeDescription(_ mode: ScanStrategyMode) -> String {
        switch mode {
        case .preBreakout:
            return "Kırılıma yakın hisseleri tarar. Breakout potansiyeli yüksek olan seviyelere yakınlığı ölçer."
        case .ultraBounce:
            return "9-faktörlü ultra strateji: RSI bounce, hacim gücü, trend hizalama, pullback kalitesi ve daha fazlası. Günlük %5+ hareket potansiyeli olan hisseleri bulur."
        case .ensemble:
            return "Pre-Breakout + Ultra birlikte değerlendirilir. İki model onayıyla daha seçici ve daha güvenli sinyal üretir."
        }
    }

    private func ultraPresetDescription(_ p: UltraPreset) -> String {
        switch p {
        case .sniper:
            return "En seçici mod. Sadece en güçlü sinyaller geçer. Az ama çok kaliteli BUY sinyalleri."
        case .hunter:
            return "Dengeli mod. 9 faktörün optimal dengesini kurar. Günlük 5-15 BUY hedefi."
        case .scout:
            return "Geniş tarama modu. Daha fazla aday gösterir. Keşif ve izleme için uygundur."
        }
    }

    private func ultraPresetRulesLine(_ p: UltraPreset) -> String {
        let cfg = p.config
        return "Min Skor: \(cfg.minScore) • ATR > %\(String(format: "%.1f", cfg.minATRPct)) • ADX > \(Int(cfg.minADX))"
    }
}

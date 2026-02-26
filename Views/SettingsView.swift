import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @AppStorage(BacktestKeys.commissionBps) private var commissionBps: Double = 12
    @AppStorage(BacktestKeys.slippageBps) private var slippageBps: Double = 8

    let hasPendingChanges: Bool
    let onApply: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                TVTheme.bg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: DS.s12) {

                        // MARK: - Tarama
                        TVCard {
                            VStack(alignment: .leading, spacing: DS.s12) {
                                HStack {
                                    Text("Tarama")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(TVTheme.text)
                                    Spacer()
                                    TVChip("Scanner", systemImage: "magnifyingglass")
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Varsayılan Endeks")
                                        .font(.caption)
                                        .foregroundStyle(TVTheme.subtext)

                                    Picker("Varsayılan Endeks", selection: $settings.defaultIndex) {
                                        ForEach(IndexOption.allCases, id: \.self) { idx in
                                            Text(idx.title).tag(idx)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                }

                                Divider().opacity(0.25)

                                // ✅ Preset (BUY-only)
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Tomorrow Preset (BUY-only)")
                                        .font(.caption)
                                        .foregroundStyle(TVTheme.subtext)

                                    Picker("Preset", selection: $settings.preset) {
                                        Text("Relaxed").tag(TomorrowPreset.relaxed)
                                        Text("Normal").tag(TomorrowPreset.normal)
                                        Text("Strict").tag(TomorrowPreset.strict)
                                    }
                                    .pickerStyle(.segmented)

                                    Text(presetHint(settings.preset))
                                        .font(.footnote)
                                        .foregroundStyle(TVTheme.subtext)
                                }

                                // ✅ Manuel strateji ayarı (StrategyConfig)
                                Divider().opacity(0.25)

                                NavigationLink {
                                    StrategyConfigEditorView()
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "slider.horizontal.3")
                                        Text("Strateji Ayarı (Manual)")
                                            .font(.system(size: 15, weight: .semibold))
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(TVTheme.subtext)
                                    }
                                    .foregroundStyle(TVTheme.text)
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 12)
                                    .background(TVTheme.surface2)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(TVTheme.stroke, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)

                                Divider().opacity(0.25)

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("İşlem Maliyeti (BPS)")
                                        .font(.caption)
                                        .foregroundStyle(TVTheme.subtext)

                                    HStack(spacing: 8) {
                                        Button("LargeCap 8/4") {
                                            commissionBps = 8
                                            slippageBps = 4
                                        }
                                        .buttonStyle(.bordered)

                                        Button("Mid/Small 12/8") {
                                            commissionBps = 12
                                            slippageBps = 8
                                        }
                                        .buttonStyle(.bordered)
                                    }

                                    Text("Aktif: Komisyon \(Int(commissionBps)) bps, Slippage \(Int(slippageBps)) bps (tek yön)")
                                        .font(.footnote)
                                        .foregroundStyle(TVTheme.subtext)
                                }

                                Divider().opacity(0.25)

                                stepperRow(
                                    title: "Concurrency",
                                    valueText: "\(settings.concurrencyLimit)",
                                    stepper: Stepper("", value: $settings.concurrencyLimit, in: 1...16, step: 1).labelsHidden()
                                )

                                stepperRow(
                                    title: "Max Sonuç (0 = sınırsız)",
                                    valueText: "\(settings.maxResults)",
                                    stepper: Stepper("", value: $settings.maxResults, in: 0...300, step: 10).labelsHidden()
                                )
                            }
                        }

                        // MARK: - Uygulama
                        TVCard {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Uygulama")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(TVTheme.text)
                                    Spacer()
                                    TVChip(hasPendingChanges ? "Bekliyor" : "Güncel",
                                           systemImage: hasPendingChanges ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                                }

                                Button {
                                    onApply()
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "checkmark.seal.fill")
                                        Text("Değişiklikleri uygula")
                                            .font(.system(size: 15, weight: .semibold))
                                        Spacer()
                                        Text(hasPendingChanges ? "Bekliyor" : "Güncel")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(hasPendingChanges ? .orange : TVTheme.subtext)
                                    }
                                    .foregroundStyle(TVTheme.text)
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 12)
                                    .background(TVTheme.surface2)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(TVTheme.stroke, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                                .disabled(!hasPendingChanges)
                                .opacity(hasPendingChanges ? 1 : 0.55)

                                if hasPendingChanges {
                                    Text("Not: Ayarlar kaydedilir; ancak tarama motoru Uygula deyince yeni ayarlarla yeniden başlatılır.")
                                        .font(.footnote)
                                        .foregroundStyle(TVTheme.subtext)
                                }
                            }
                        }

                        // MARK: - Depolama
                        TVCard {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Depolama")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(TVTheme.text)
                                    Spacer()
                                    TVChip("Snapshot", systemImage: "internaldrive")
                                }

                                Button(role: .destructive) {
                                    try? ScanSnapshotStore.deleteAll()
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "trash")
                                        Text("Tüm taramaları sil")
                                            .font(.system(size: 15, weight: .semibold))
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(TVTheme.subtext)
                                    }
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 12)
                                    .background(TVTheme.surface2)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(TVTheme.stroke, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        // MARK: - Reset
                        TVCard {
                            Button {
                                settings.resetToDefaults()

                                // Opsiyonel: StrategyConfig'i de default’a döndürmek istersen aç:
                                // StrategyConfig.default.save()
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "arrow.counterclockwise")
                                    Text("Varsayılanlara dön")
                                        .font(.system(size: 15, weight: .semibold))
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(TVTheme.subtext)
                                }
                                .foregroundStyle(TVTheme.text)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 12)
                                .background(TVTheme.surface2)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(TVTheme.stroke, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        Spacer(minLength: 12)
                    }
                    .padding(.horizontal, DS.s16)
                    .padding(.top, DS.s12)
                    .padding(.bottom, 16)
                }
            }
            .navigationTitle("Ayarlar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(TVTheme.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .tvNavStyle()
        }
    }

    private func presetHint(_ p: TomorrowPreset) -> String {
        switch p {
        case .relaxed:
            return "Daha fazla aday çıkarır (daha gevşek eşikler)."
        case .normal:
            return "Normal mod StrategyConfig (manuel ayarlarını) kullanır."
        case .strict:
            return "En seçici mod: Tier C kapalı + daha sıkı eşikler."
        }
    }

    private func stepperRow(title: String, valueText: String, stepper: some View) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(TVTheme.text)

            Spacer()

            Text(valueText)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(TVTheme.subtext)

            stepper
        }
        .padding(.vertical, 6)
    }
}

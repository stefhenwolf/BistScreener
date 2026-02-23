import SwiftUI

struct StrategyConfigEditorView: View {

    @Environment(\.dismiss) private var dismiss

    @State private var cfg: StrategyConfig = .load()
    @State private var showSavedToast = false

    var body: some View {
        ScrollView {
            VStack(spacing: DS.s12) {

                presetsCard
                proximityCard
                volumeCard
                clvCard
                compressionCard
                todayChangeCard
                weightsCard
                scoreCard
                qualityBandsCard
                actionsCard

            }
            .padding(.horizontal, DS.s16)
            .padding(.vertical, DS.s12)
        }
        .navigationTitle("Strateji Ayarı")
        .navigationBarTitleDisplayMode(.inline)
        .tvBackground()
    }

    // MARK: - Cards

    private var presetsCard: some View {
        TVCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Preset")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(TVTheme.text)
                    Spacer()
                    TVChip("StrategyConfig", systemImage: "slider.horizontal.3")
                }

                HStack(spacing: 10) {
                    presetButton("Default") {
                        cfg = .default
                        save()
                    }
                    presetButton("Aggressive") {
                        cfg = .aggressive
                        save()
                    }
                    presetButton("Conservative") {
                        cfg = .conservative
                        save()
                    }
                }

                Text("Not: Preset uygulayınca anında kaydedilir.")
                    .font(.footnote)
                    .foregroundStyle(TVTheme.subtext)
            }
        }
    }

    private func presetButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(TVTheme.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(TVTheme.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(TVTheme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var proximityCard: some View {
        TVCard {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Kırılıma Yakınlık (Proximity)")
                doubleSliderRow("Min Proximity", value: $cfg.minProximity, range: 0.90...0.99, step: 0.001)
                doubleSliderRow("Max Proximity", value: $cfg.maxProximity, range: 0.95...1.05, step: 0.001)
                hint("close / refLevel aralığı. 1.0 = kırılım seviyesi.")
            }
        }
    }

    private var volumeCard: some View {
        TVCard {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Hacim")
                doubleSliderRow("Min Value Multiple", value: $cfg.minValueMultiple, range: 0.3...3.0, step: 0.05)
                doubleSliderRow("Min Volume Trend", value: $cfg.minVolumeTrend, range: 0.0...3.0, step: 0.05)
                hint("ValueMultiple = (today value) / (avg20 value). VolumeTrend = (son 5 gün avg vol) / (önceki 10 gün avg vol)")
            }
        }
    }

    private var clvCard: some View {
        TVCard {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Kapanış Gücü (CLV)")
                doubleSliderRow("Min CLV", value: $cfg.minCLV, range: 0.0...1.0, step: 0.05)
                hint("CLV = (Close - Low) / (High - Low). 0.70+ güçlü kapanış.")
            }
        }
    }

    private var compressionCard: some View {
        TVCard {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Sıkışma (Range Compression)")
                doubleSliderRow("Max Range Compression", value: $cfg.maxRangeCompression, range: 0.6...2.0, step: 0.05)
                hint("recentRange / olderRange. Küçük = daha sıkışmış.")
            }
        }
    }

    private var todayChangeCard: some View {
        TVCard {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Bugün Değişim Filtresi")
                doubleSliderRow("Max Today Change %", value: $cfg.maxTodayChangePct, range: 0.5...10.0, step: 0.25)
                hint("Aşırı yükselmiş günleri elemek için.")
            }
        }
    }

    private var weightsCard: some View {
        TVCard {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Ağırlıklar (Toplam 100 önerilir)")
                doubleSliderRow("w Proximity", value: $cfg.weightProximity, range: 0...60, step: 1)
                doubleSliderRow("w VolumeTrend", value: $cfg.weightVolumeTrend, range: 0...60, step: 1)
                doubleSliderRow("w CLV", value: $cfg.weightCLV, range: 0...60, step: 1)
                doubleSliderRow("w Compression", value: $cfg.weightCompression, range: 0...60, step: 1)

                let sum = cfg.weightProximity + cfg.weightVolumeTrend + cfg.weightCLV + cfg.weightCompression
                Text("Toplam: \(Int(sum))")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(sum >= 95 && sum <= 105 ? TVTheme.up : TVTheme.down)

                hint("SignalScorer içinde normalize ediliyor; 100 şart değil ama 100'e yakın tutmak iyi.")
            }
        }
    }

    private var scoreCard: some View {
        TVCard {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Eşik")
                StepperRowInt(title: "Min Score", value: $cfg.minScore, range: 0...100, step: 1)
                StepperRowInt(title: "Lookback Days", value: $cfg.lookbackDays, range: 10...60, step: 1)
            }
        }
    }

    private var qualityBandsCard: some View {
        TVCard {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Kalite Bantları")
                StepperRowInt(title: "A+ ≥", value: $cfg.qualityAPlus, range: 0...100, step: 1)
                StepperRowInt(title: "A ≥", value: $cfg.qualityA, range: 0...100, step: 1)
                StepperRowInt(title: "B ≥", value: $cfg.qualityB, range: 0...100, step: 1)
                StepperRowInt(title: "C ≥", value: $cfg.qualityC, range: 0...100, step: 1)
                hint("D = kalanlar.")
            }
        }
    }

    private var actionsCard: some View {
        TVCard {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    save()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill")
                        Text("Kaydet")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                        if showSavedToast { Text("Kaydedildi") }
                    }
                    .foregroundStyle(TVTheme.text)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(TVTheme.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(TVTheme.stroke, lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "xmark.circle.fill")
                        Text("Kapat")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                    }
                    .foregroundStyle(TVTheme.subtext)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Helpers UI

    private func sectionTitle(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(TVTheme.text)
    }

    private func hint(_ s: String) -> some View {
        Text(s)
            .font(.footnote)
            .foregroundStyle(TVTheme.subtext)
    }

    private func doubleSliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TVTheme.text)
                Spacer()
                Text(String(format: "%.3f", value.wrappedValue))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TVTheme.subtext)
            }
            Slider(value: value, in: range, step: step)
                .tint(TVTheme.up)
        }
        .padding(.vertical, 4)
    }

    private func save() {
        cfg.save()
        showSavedToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            showSavedToast = false
        }
    }
}

// Small helper row
private struct StepperRowInt: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(TVTheme.text)
            Spacer()
            Text("\(value)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(TVTheme.subtext)

            Stepper("", value: $value, in: range, step: step).labelsHidden()
        }
        .padding(.vertical, 4)
    }
}

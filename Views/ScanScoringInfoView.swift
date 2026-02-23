import SwiftUI

struct ScanScoringInfoView: View {
    @Environment(\.dismiss) private var dismiss

    /// Tarama ekranından gönderiyoruz (vm.results.first gibi)
    let sample: ScanResult?

    // Eşik: biasScore >= threshold => bullish, <= -threshold => bearish
    @State private var threshold: Int = 12

    var body: some View {
        NavigationStack {
            List {
                Section("Canlı Örnek (Tarama verisinden)") {
                    if let s = sample {
                        let b = s.breakdown(threshold: threshold)

                        LabeledContent("Sembol", value: s.symbol)
                        LabeledContent("Total Score", value: "\(b.totalScore)")
                        LabeledContent("Bullish Score", value: "\(b.bullishScore)")
                        LabeledContent("Bearish Score", value: "\(b.bearishScore)")
                        LabeledContent("Bias Score", value: "\(b.biasScore)")
                        LabeledContent("Signal", value: "\(b.signal.rawValue)")
                        LabeledContent("Pattern Count", value: "\(b.patternCount)")

                        Stepper("Signal threshold: \(threshold)", value: $threshold, in: 1...30)

                        codeBlock("""
                        bullishScore = Σ(score where pattern.isBullish)
                        bearishScore = Σ(score where pattern.isBearish)
                        biasScore    = bullishScore - bearishScore

                        if biasScore >= \(threshold)  -> bullish
                        if biasScore <= -\(threshold) -> bearish
                        else                          -> neutral

                        totalScore = ScanResult.totalScore (tarama sırasında hesaplanan değer)
                        """)
                    } else {
                        Text("Henüz örnek veri yok. Tarama sonuçları gelince burası otomatik dolacak.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Total Score ne?") {
                    Text("Total Score tarama motorunun ürettiği nihai skor. Uygulamada listeye basılan değer budur. Info ekranı, bu skorun yanında bullish/bearish dağılımını ve bias’ı canlı örnekle gösterir.")
                        .foregroundStyle(.secondary)
                }

                Section("Pattern kataloğu (otomatik)") {
                    ForEach(CandlePattern.allCases, id: \.self) { p in
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 10) {
                                    PatternDiagramView(diagram: PatternDiagram.forPattern(p))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(PatternMeta.meta[p]?.title ?? p.rawValue)
                                            .font(.headline)
                                        Text(PatternMeta.meta[p]?.subtitle ?? directionText(p))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }

                                Text(PatternMeta.meta[p]?.notes ?? defaultNotes(p))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)

                                LabeledContent("Direction", value: p.direction.rawValue)
                            }
                        } label: {
                            HStack {
                                Text(p.rawValue)
                                Spacer()
                                Text(p.direction.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Puanlama & Formasyonlar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }

    private func directionText(_ p: CandlePattern) -> String {
        switch p.direction {
        case .bullish: return "Boğa (bullish) formasyon"
        case .bearish: return "Ayı (bearish) formasyon"
        case .neutral: return "Nötr"
        }
    }

    private func defaultNotes(_ p: CandlePattern) -> String {
        switch p.direction {
        case .bullish: return "Genelde düşüş sonrası alıcı dönüşü olarak yorumlanır; grafikte teyit aranır."
        case .bearish: return "Genelde yükseliş sonrası satıcı dönüşü olarak yorumlanır; grafikte teyit aranır."
        case .neutral: return "Tek başına yön vermez; bağlama göre değerlendirilir."
        }
    }

    private func codeBlock(_ t: String) -> some View {
        Text(t)
            .font(.system(.callout, design: .monospaced)) // monospaced destek  [oai_citation:1‡Apple Developer](https://developer.apple.com/documentation/swiftui/font/monospaced%28%29?utm_source=chatgpt.com)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Pattern meta (senin dilinle açıklamalar)

enum PatternMeta {
    struct Info {
        let title: String
        let subtitle: String
        let notes: String
    }

    static let meta: [CandlePattern: Info] = [
        .bullishEngulfing: .init(title: "Bullish Engulfing", subtitle: "Güçlü alıcı dönüşü", notes: "Kırmızı gövdeyi takip eden daha büyük yeşil gövde; momentum değişimi."),
        .bearishEngulfing: .init(title: "Bearish Engulfing", subtitle: "Güçlü satıcı dönüşü", notes: "Yeşil gövdeyi takip eden daha büyük kırmızı gövde; tepe dönüşü riski."),
        .hammer: .init(title: "Hammer", subtitle: "Dipte reddediş", notes: "Küçük gövde + uzun alt fitil; satışın reddi."),
        .shootingStar: .init(title: "Shooting Star", subtitle: "Tepede reddediş", notes: "Küçük gövde + uzun üst fitil; alımın reddi.")
    ]
}

// MARK: - Diagram mapping (otomatik üretim)

private enum PatternDiagram {
    case bullishEngulfing, bearishEngulfing, hammer, shootingStar, genericBull, genericBear, generic

    static func forPattern(_ p: CandlePattern) -> PatternDiagram {
        switch p {
        case .bullishEngulfing: return .bullishEngulfing
        case .bearishEngulfing: return .bearishEngulfing
        case .hammer: return .hammer
        case .shootingStar: return .shootingStar
        default:
            switch p.direction {
            case .bullish: return .genericBull
            case .bearish: return .genericBear
            case .neutral: return .generic
            }
        }
    }
}

private struct PatternDiagramView: View {
    let diagram: PatternDiagram

    var body: some View {
        HStack(spacing: 6) {
            switch diagram {
            case .bullishEngulfing:
                CandleMini(colorUp: false, bodyHeight: 14, upperWick: 6, lowerWick: 8)
                CandleMini(colorUp: true,  bodyHeight: 22, upperWick: 6, lowerWick: 8)

            case .bearishEngulfing:
                CandleMini(colorUp: true,  bodyHeight: 14, upperWick: 6, lowerWick: 8)
                CandleMini(colorUp: false, bodyHeight: 22, upperWick: 6, lowerWick: 8)

            case .hammer:
                CandleMini(colorUp: true,  bodyHeight: 10, upperWick: 4,  lowerWick: 18)

            case .shootingStar:
                CandleMini(colorUp: false, bodyHeight: 10, upperWick: 18, lowerWick: 4)

            case .genericBull:
                CandleMini(colorUp: true, bodyHeight: 16, upperWick: 8, lowerWick: 8)

            case .genericBear:
                CandleMini(colorUp: false, bodyHeight: 16, upperWick: 8, lowerWick: 8)

            case .generic:
                CandleMini(colorUp: true, bodyHeight: 10, upperWick: 10, lowerWick: 10)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct CandleMini: View {
    let colorUp: Bool
    let bodyHeight: CGFloat
    let upperWick: CGFloat
    let lowerWick: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(.secondary.opacity(0.6)).frame(width: 2, height: upperWick)
            RoundedRectangle(cornerRadius: 2)
                .fill(colorUp ? Color.green.opacity(0.8) : Color.red.opacity(0.8))
                .frame(width: 10, height: bodyHeight)
            Rectangle().fill(.secondary.opacity(0.6)).frame(width: 2, height: lowerWick)
        }
        .frame(width: 14, height: upperWick + bodyHeight + lowerWick)
    }
}

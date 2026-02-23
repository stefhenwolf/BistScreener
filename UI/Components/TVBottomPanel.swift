import SwiftUI

struct TVBottomPanel: View {
    let symbol: String
    let active: Candle?
    let patterns: [CandlePatternScore]

    var body: some View {
        VStack(spacing: 12) {
            Capsule()
                .fill(Color.white.opacity(0.25))
                .frame(width: 42, height: 5)
                .padding(.top, 8)

            HStack {
                Text("Overview")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 16)

            VStack(spacing: 10) {
                row("Last Close", active.map { String(format: "%.2f", $0.close) } ?? "--")
                row("High", active.map { String(format: "%.2f", $0.high) } ?? "--")
                row("Low", active.map { String(format: "%.2f", $0.low) } ?? "--")
            }
            .padding(16)
            .background(TVTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(TVTheme.stroke, lineWidth: 1)
            )
            .padding(.horizontal, 16)

            HStack {
                Text("Patterns")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 16)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(patterns, id: \.id) { p in
                        HStack {
                            // ✅ Eğer p.name yoksa kesin çalışan:
                            Text(p.pattern.rawValue)
                                .foregroundStyle(TVTheme.text)

                            Spacer()

                            ScorePill(score: p.score)
                                
                        }
                        .padding(12)
                        .background(TVTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(TVTheme.stroke, lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
            }
        }
        .tvBackground()
    }

    private func row(_ left: String, _ right: String) -> some View {
        HStack {
            Text(left).foregroundStyle(TVTheme.subtext)
            Spacer()
            Text(right).foregroundStyle(TVTheme.text)
        }
        .font(.system(size: 14, weight: .medium))
    }
}   

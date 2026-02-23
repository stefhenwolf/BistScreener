import SwiftUI

struct ScorePill: View {
    let score: Int

    var body: some View {
        Text("\(score)")
            .font(.system(size: 12, weight: .bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(fg)
            .background(bg)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(TVTheme.stroke, lineWidth: 1))
    }

    private var fg: Color {
        if score >= 70 { return TVTheme.up }
        if score >= 30 { return TVTheme.text.opacity(0.85) }
        return TVTheme.down
    }

    private var bg: some ShapeStyle {
        if score >= 70 { return TVTheme.up.opacity(0.18) }
        if score >= 30 { return TVTheme.surface2 }
        return TVTheme.down.opacity(0.18)
    }
}

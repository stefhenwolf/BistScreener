//
//  ScoreBadge.swift
//  BistScreener
//
//  Created by Sedat Pala on 20.02.2026.
//

import SwiftUI

struct ScoreBadge: View {
    let score: Int

    private var label: String {
        switch score {
        case 90...: return "A+"
        case 80..<90: return "A"
        case 70..<80: return "B"
        case 60..<70: return "C"
        default: return "D"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption.weight(.bold))
            Text("\(score)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(Color.primary.opacity(0.10), lineWidth: 0.8)
        )
    }
}

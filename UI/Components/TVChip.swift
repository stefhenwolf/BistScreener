//
//  TVChip.swift
//  BistScreener
//
//  Created by Sedat Pala on 21.02.2026.
//

import SwiftUI

struct TVChip: View {
    let text: String
    let systemImage: String?

    init(_ text: String, systemImage: String? = nil) {
        self.text = text
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TVTheme.subtext)
            }
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .foregroundStyle(TVTheme.subtext)   // ✅ bunu ekle
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(TVTheme.surface2)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(TVTheme.stroke, lineWidth: 1))
    }
}

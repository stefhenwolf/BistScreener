//
//  TVCard.swift
//  BistScreener
//
//  Created by Sedat Pala on 21.02.2026.
//

import SwiftUI

struct TVCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .background(TVTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(TVTheme.stroke, lineWidth: 1)
                    .allowsHitTesting(false)   // ✅ NavigationLink tap’i artık kesin çalışır
            )
    }
}

//
//  AppCard.swift
//  BistScreener
//
//  Created by Sedat Pala on 20.02.2026.
//

import SwiftUI

struct AppCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(DS.s16)
            .background(DS.cardBackground())
            .clipShape(RoundedRectangle(cornerRadius: DS.r22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.r22, style: .continuous)
                    .stroke(DS.cardStroke(), lineWidth: DS.stroke)
            )
            .shadow(color: .black.opacity(0.10), radius: DS.shadowRadius, x: 0, y: DS.shadowY)
    }
}

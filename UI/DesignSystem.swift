//
//  DesignSystem.swift
//  BistScreener
//
//  Created by Sedat Pala on 20.02.2026.
//

import SwiftUI

enum DS {
    // Spacing
    static let s8: CGFloat = 8
    static let s12: CGFloat = 12
    static let s16: CGFloat = 16
    static let s24: CGFloat = 24

    // Radius
    static let r14: CGFloat = 14
    static let r18: CGFloat = 18
    static let r22: CGFloat = 22

    // Stroke
    static let stroke: CGFloat = 0.9

    // Card
    static func cardBackground() -> some ShapeStyle { .thinMaterial }
    static func cardStroke() -> some ShapeStyle { Color.primary.opacity(0.10) }

    // Shadow (daha doğal)
    static let shadowRadius: CGFloat = 14
    static let shadowY: CGFloat = 8

    // ✅ App Background (premium)
    static func appBackground() -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(.systemBackground),
                    Color(.secondarySystemBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // very subtle glow blobs
            Circle()
                .fill(Color.accentColor.opacity(0.10))
                .frame(width: 420, height: 420)
                .blur(radius: 40)
                .offset(x: 140, y: -220)

            Circle()
                .fill(Color.accentColor.opacity(0.08))
                .frame(width: 340, height: 340)
                .blur(radius: 40)
                .offset(x: -160, y: 260)
        }
        .ignoresSafeArea()
    }
}

// ✅ Her ekranda tek satırla uygulamak için
extension View {
    func appScreenBackground() -> some View {
        self.background(DS.appBackground())
    }
}

//
//  TVTickerHeader.swift
//  BistScreener
//
//  Created by Sedat Pala on 21.02.2026.
//

import SwiftUI

struct TVTickerHeader: View {
    let symbol: String
    let priceText: String
    let changeText: String
    let isUp: Bool
    let isFav: Bool
    let onToggleFav: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(symbol)
                    .font(.system(size: 20, weight: .semibold))

                HStack(spacing: 8) {
                    Text(priceText)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(TVTheme.text)

                    Text(changeText)
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background((isUp ? TVTheme.up : TVTheme.down).opacity(0.18))
                        .clipShape(Capsule())
                        .foregroundStyle(isUp ? TVTheme.up : TVTheme.down)
                }
            }

            Spacer()

            Button(action: onToggleFav) {
                Image(systemName: isFav ? "star.fill" : "star")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isFav ? Color.yellow : TVTheme.subtext)
                    .padding(10)
                    .background(TVTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(TVTheme.stroke, lineWidth: 1)
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 6)
    }
}

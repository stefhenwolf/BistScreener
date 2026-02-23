//
//  TVTheme.swift
//  BistScreener
//
//  Created by Sedat Pala on 21.02.2026.
//

// TVTheme.swift  ← YENİ DOSYA

import SwiftUI

enum TVTheme {
    // ── Ana Renkler (TradingView Dark benzeri)
    static let bg       = Color(hex: "#131722")   // Koyu zemin
    static let surface  = Color(hex: "#1E222D")   // Kart yüzeyi
    static let surface2 = Color(hex: "#2A2E39")   // İkincil yüzey
    static let stroke   = Color(hex: "#363C4E")   // Sınır rengi
    static let text     = Color(hex: "#D1D4DC")   // Ana metin
    static let subtext  = Color(hex: "#787B86")   // İkincil metin
    static let accent   = Color(hex: "#2962FF")   // Mavi aksan
    static let up       = Color(hex: "#26A69A")   // Yeşil (artış)
    static let down     = Color(hex: "#EF5350")   // Kırmızı (düşüş)
    static let warning  = Color(hex: "#FF9800")   // Turuncu uyarı

    // ── Grafik Mum Renkleri
    static let candleUp     = Color(hex: "#26A69A")
    static let candleDown   = Color(hex: "#EF5350")
    static let candleUpFill = Color(hex: "#26A69A").opacity(0.8)
    static let candleDownFill = Color(hex: "#EF5350").opacity(0.8)

    // ── İndikatör Çizgi Renkleri
    static let ema9   = Color(hex: "#FF6D00")   // Turuncu
    static let ema21  = Color(hex: "#E040FB")   // Mor
    static let ema50  = Color(hex: "#00BCD4")   // Cyan
    static let macdLine   = Color(hex: "#2196F3")
    static let signalLine = Color(hex: "#FF5722")
    static let rsiLine    = Color(hex: "#9C27B0")
    static let bbUpper    = Color(hex: "#787B86")
    static let bbLower    = Color(hex: "#787B86")
    static let bbMiddle   = Color(hex: "#B0BEC5")

    // ── Gradient
    static func upGradient() -> LinearGradient {
        LinearGradient(
            colors: [up.opacity(0.3), up.opacity(0)],
            startPoint: .top, endPoint: .bottom
        )
    }
    static func downGradient() -> LinearGradient {
        LinearGradient(
            colors: [down.opacity(0.3), down.opacity(0)],
            startPoint: .top, endPoint: .bottom
        )
    }
}

// MARK: - Hex Color Extension

extension Color {
    init(hex: String) {
        var clean = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        clean = clean.hasPrefix("#") ? String(clean.dropFirst()) : clean
        var rgb: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8)  & 0xFF) / 255
        let b = Double(rgb & 0xFF)         / 255
        self.init(red: r, green: g, blue: b)
    }
}

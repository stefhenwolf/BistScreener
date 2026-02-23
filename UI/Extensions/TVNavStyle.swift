//
//  TVNavStyle.swift
//  BistScreener
//
//  Created by Sedat Pala on 21.02.2026.
//

import SwiftUI

extension View {
    /// ✅ NavigationBar başlığı + ikonları her yerde beyaz yapar
    func tvNavStyle() -> some View {
        self
            .toolbarBackground(TVTheme.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)   // ✅ başlık beyaz
    }

    /// ✅ TVTheme arka planını safeArea dahil uygular
    func tvBackground() -> some View {
        self.background(TVTheme.bg.ignoresSafeArea())
    }
}

//
//  SettingsButtonModifier.swift
//  BistScreener
//
//  Created by Sedat Pala on 21.02.2026.
//

import SwiftUI

private struct SettingsButtonModifier: ViewModifier {
    @Binding var show: Bool

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        show = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(TVTheme.text)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Ayarlar")
                }
            }
            .toolbarBackground(TVTheme.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

extension View {
    func settingsButton(show: Binding<Bool>) -> some View {
        modifier(SettingsButtonModifier(show: show))
    }
}

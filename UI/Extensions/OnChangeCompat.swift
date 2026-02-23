//
//  OnChangeCompat.swift
//  BistScreener
//
//  Created by Sedat Pala on 21.02.2026.
//

import SwiftUI

extension View {
    /// iOS 17'deki `initial:` parametresi ile uyumlu, iOS 16'da fallback yapan helper.
    @ViewBuilder
    func onChangeCompat<T: Equatable>(
        of value: T,
        initial: Bool = false,
        perform action: @escaping (T) -> Void
    ) -> some View {
        if #available(iOS 17.0, *) {
            self.onChange(of: value, initial: initial) { _, newValue in
                action(newValue)
            }
        } else {
            self.onChange(of: value) { newValue in
                // iOS 16'da initial davranışını manuel tetikle
                action(newValue)
            }
            .onAppear {
                if initial { action(value) }
            }
        }
    }
}

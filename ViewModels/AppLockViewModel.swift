//
//  AppLockViewModel.swift
//  BistScreener
//
//  Created by Sedat Pala on 18.02.2026.
//

import Foundation
import LocalAuthentication

@MainActor
final class AppLockViewModel: ObservableObject {
    @Published var isUnlocked: Bool = false
    @Published var errorText: String?

    func lock() {
        isUnlocked = false
        errorText = nil
    }

    func unlock() async {
        errorText = nil

        let ctx = LAContext()
        var err: NSError?

        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            errorText = "FaceID/TouchID kullanılamıyor. Ayarlardan etkinleştir."
            return
        }

        do {
            let ok = try await ctx.evaluatePolicy(.deviceOwnerAuthentication,
                                                 localizedReason: "Varlıklarını görmek için doğrulama gerekiyor.")
            if ok { isUnlocked = true }
        } catch {
            errorText = "Doğrulama iptal edildi / başarısız."
        }
    }
}

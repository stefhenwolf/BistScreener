//
//  AsyncSemaphore.swift
//  BistScreener
//
//  Created by Sedat Pala on 20.02.2026.
//

import Foundation

/// Swift Concurrency için actor tabanlı basit semaphore.
/// Aynı anda maksimum `value` kadar işi çalıştırmak için.
actor AsyncSemaphore {
    private var value: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(value: Int) {
        self.value = max(0, value)
    }

    func wait() async {
        if value > 0 {
            value -= 1
            return
        }

        await withCheckedContinuation { cont in
            waiters.append(cont)
        }
    }

    func signal() {
        if waiters.isEmpty {
            value += 1
        } else {
            let cont = waiters.removeFirst()
            cont.resume()
        }
    }

    /// defer bloklarında kullanılabilir (await gerekmez).
    nonisolated func signalFromSync() {
        Task { await self.signal() }
    }
}

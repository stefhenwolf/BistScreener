//
//  AsyncThrottle.swift
//  BistScreener
//
//  Created by Sedat Pala on 20.02.2026.
//

import Foundation

/// Basit throttle: iki "permit" arasında en az `minInterval` bırakır.
/// Yahoo gibi servislerde 429/limit riskini azaltır.
actor AsyncThrottle {
    private let minInterval: TimeInterval
    private var nextAllowed: ContinuousClock.Instant?

    init(minInterval: TimeInterval) {
        self.minInterval = max(0, minInterval)
    }

    func wait() async {
        guard minInterval > 0 else { return }

        let now = ContinuousClock.now
        if let next = nextAllowed, next > now {
            let delta = next.duration(to: now) * -1
            try? await Task.sleep(for: delta)
        }
        nextAllowed = ContinuousClock.now.advanced(by: .seconds(minInterval))
    }
}

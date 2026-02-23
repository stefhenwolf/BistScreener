//
//  CacheStats.swift
//  BistScreener
//
//  Created by Sedat Pala on 22.02.2026.
//

import Foundation

@MainActor
final class CacheStats: ObservableObject {
    @Published private(set) var diskHits: Int = 0
    @Published private(set) var networkFetches: Int = 0
    @Published private(set) var merges: Int = 0

    func hitDisk() { diskHits += 1 }
    func hitNetwork() { networkFetches += 1 }
    func didMerge() { merges += 1 }

    func reset() {
        diskHits = 0
        networkFetches = 0
        merges = 0
    }

    var oneLine: String {
        "CacheStats • disk:\(diskHits) net:\(networkFetches) merge:\(merges)"
    }
}


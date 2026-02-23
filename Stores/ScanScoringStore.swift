//
//  ScanScoringStore.swift
//  BistScreener
//
//  Created by Sedat Pala on 22.02.2026.
//

import Foundation

@MainActor
final class ScanScoringStore: ObservableObject {
    @Published var config: ScanScoringConfig {
        didSet { save() }
    }

    private let key = "scan.scoring.config.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(ScanScoringConfig.self, from: data) {
            self.config = decoded
        } else {
            self.config = .default
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

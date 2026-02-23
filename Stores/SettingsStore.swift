//
//  SettingsStore.swift
//  BistScreener
//
//  Created by Sedat Pala on 21.02.2026.
//

import Foundation

@MainActor
final class SettingsStore: ObservableObject {

    // MARK: - Keys
    private enum Keys {
        static let defaultIndex = "settings.defaultIndex"
        static let concurrency  = "settings.concurrency"
        static let preset       = "settings.scanPreset"      // ✅ NEW
        static let maxResults   = "settings.maxResults"

        // legacy (minScore) key'i okumaya devam edebilirsin; ama artık kullanılmayacak.
        static let minScore     = "settings.minScore"
    }

    // MARK: - Published

    @Published var defaultIndex: IndexOption {
        didSet { UserDefaults.standard.set(defaultIndex.rawValue, forKey: Keys.defaultIndex) }
    }

    /// Tarama paralellik limiti (ScannerViewModel init’inde kullanacağız)
    @Published var concurrencyLimit: Int {
        didSet {
            let clamped = min(max(concurrencyLimit, 1), 16)
            if clamped != concurrencyLimit { concurrencyLimit = clamped; return }
            UserDefaults.standard.set(concurrencyLimit, forKey: Keys.concurrency)
        }
    }

    /// ✅ BUY-only preset
    @Published var preset: TomorrowPreset {
        didSet { UserDefaults.standard.set(preset.rawValue, forKey: Keys.preset) }
    }

    @Published var maxResults: Int {
        didSet {
            let clamped = max(0, maxResults)
            if clamped != maxResults { maxResults = clamped; return }
            UserDefaults.standard.set(maxResults, forKey: Keys.maxResults)
        }
    }

    // MARK: - Init

    init() {
        let raw = UserDefaults.standard.string(forKey: Keys.defaultIndex) ?? IndexOption.xu100.rawValue
        self.defaultIndex = IndexOption(rawValue: raw) ?? .xu100

        let savedConc = UserDefaults.standard.object(forKey: Keys.concurrency) as? Int
        self.concurrencyLimit = min(max(savedConc ?? 8, 1), 16)

        // ✅ preset load (yoksa default normal)
        let rawPreset = UserDefaults.standard.string(forKey: Keys.preset)
        self.preset = TomorrowPreset(rawValue: rawPreset ?? "") ?? .normal

        let savedMax = UserDefaults.standard.object(forKey: Keys.maxResults) as? Int
        self.maxResults = max(0, savedMax ?? 0)
    }

    // MARK: - Helpers

    func resetToDefaults() {
        defaultIndex = .xu100
        concurrencyLimit = 8
        preset = .normal
        maxResults = 0
    }
}

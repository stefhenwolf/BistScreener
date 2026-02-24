//
//  WatchlistStore.swift
//  BistScreener
//
//  Created by Sedat Pala on 18.02.2026.
//

import Foundation

@MainActor
final class WatchlistStore: ObservableObject {
    @Published private(set) var symbols: [String] = []

    private let key = "watchlist_symbols_v1"
    private let limit = 100

    enum AddResult {
        case added
        case duplicate
        case full
        case invalid
    }

    init() { load() }

    func contains(_ symbol: String) -> Bool {
        symbols.contains(symbol.normalizedBISTSymbol())
    }

    @discardableResult
    func add(_ symbol: String) -> AddResult {
        let s = symbol.normalizedBISTSymbol()
        guard !s.isEmpty else { return .invalid }
        if symbols.contains(s) { return .duplicate }
        guard symbols.count < limit else { return .full }

        symbols.append(s)
        symbols.sort()
        save()
        return .added
    }

    func remove(_ symbol: String) {
        let s = symbol.normalizedBISTSymbol()
        symbols.removeAll { $0 == s }
        save()
    }

    func toggle(_ symbol: String) {
        let s = symbol.normalizedBISTSymbol()
        if let idx = symbols.firstIndex(of: s) {
            symbols.remove(at: idx)
            save()
        } else {
            _ = add(s)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        if let decoded = try? JSONDecoder().decode([String].self, from: data) {
            symbols = decoded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(symbols) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - Shared symbol normalization

extension String {
    /// Normalizes BIST symbols for Yahoo Finance.
    /// - Behavior:
    ///   - trims whitespace/newlines
    ///   - uppercases
    ///   - global Yahoo sembolleri (=, -, ^, /) olduğu gibi bırakır
    ///   - diğerlerinde market suffix yoksa `.IS` ekler
    func normalizedBISTSymbol() -> String {
        let t = trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !t.isEmpty else { return "" }
        let isGlobalYahoo = t.contains("=") || t.contains("-") || t.contains("^") || t.contains("/")
        if t.contains(".") || isGlobalYahoo { return t }
        return t + ".IS"
    }
}

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

    private let keyPrefix = "watchlist_symbols_v1"
    private let limit = 100
    private var activeUserKey: String = "guest"
    private let cloudRepository: any CloudDataRepository
    private var cloudUserID: String?

    enum AddResult {
        case added
        case duplicate
        case full
        case invalid
    }

    init(cloudRepository: any CloudDataRepository = NoopCloudDataRepository()) {
        self.cloudRepository = cloudRepository
        load()
    }

    func setUserContext(localUserKey: String?, cloudUserID: String?) {
        let normalizedCloud = cloudUserID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCloud = (normalizedCloud?.isEmpty == false) ? normalizedCloud : nil
        let cleaned = sanitize(localUserKey)
        let changed = cleaned != activeUserKey || cleanCloud != self.cloudUserID
        guard changed else { return }
        activeUserKey = cleaned
        self.cloudUserID = cleanCloud
        load()
        Task { [weak self] in
            guard let self else { return }
            await self.hydrateFromCloudOrUploadFallback()
        }
    }

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
        syncToCloud()
        return .added
    }

    func remove(_ symbol: String) {
        let s = symbol.normalizedBISTSymbol()
        symbols.removeAll { $0 == s }
        save()
        syncToCloud()
    }

    func toggle(_ symbol: String) {
        let s = symbol.normalizedBISTSymbol()
        if let idx = symbols.firstIndex(of: s) {
            symbols.remove(at: idx)
            save()
            syncToCloud()
        } else {
            _ = add(s)
        }
    }

    private func load() {
        let key = "\(keyPrefix).\(activeUserKey)"
        guard let data = UserDefaults.standard.data(forKey: key) else {
            symbols = []
            return
        }
        if let decoded = try? JSONDecoder().decode([String].self, from: data) {
            symbols = decoded
        } else {
            symbols = []
        }
    }

    private func save() {
        let key = "\(keyPrefix).\(activeUserKey)"
        if let data = try? JSONEncoder().encode(symbols) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func sanitize(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "guest" }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        let chars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let out = String(chars)
        return out.isEmpty ? "guest" : out
    }

    private func hydrateFromCloudOrUploadFallback() async {
        guard let uid = cloudUserID else { return }
        do {
            if let remote = try await cloudRepository.fetchWatchlist(userID: uid) {
                await MainActor.run {
                    self.symbols = remote.sorted()
                    self.save()
                }
            } else {
                try await cloudRepository.upsertWatchlist(userID: uid, symbols: symbols)
            }
        } catch {
            // Sessiz: local fallback devam eder.
        }
    }

    private func syncToCloud() {
        guard let uid = cloudUserID else { return }
        let snapshot = symbols
        Task { [cloudRepository] in
            try? await cloudRepository.upsertWatchlist(userID: uid, symbols: snapshot)
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

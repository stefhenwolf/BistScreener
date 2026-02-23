//
//  CandleCache.swift
//  BistScreener
//
//  Created by Sedat Pala on 18.02.2026.
//

import Foundation

actor CandleCache {
    static let shared = CandleCache()

    private let fm = FileManager.default
    private let baseURL: URL

    private init() {
        let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        baseURL = dir.appendingPathComponent("CandleCache", isDirectory: true)
        try? fm.createDirectory(at: baseURL, withIntermediateDirectories: true)
    }

    // MARK: - Public

    /// Cache klasöründeki json dosya sayısı (yaklaşık cache key sayısı)
    func estimatedKeyCount() -> Int {
        guard let items = try? fm.contentsOfDirectory(
            at: baseURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        return items.filter { $0.pathExtension.lowercased() == "json" }.count
    }

    func load(symbol: String) -> [Candle]? {
        let url = fileURL(symbol: symbol)
        guard fm.fileExists(atPath: url.path) else { return nil }

        do {
            let data = try Data(contentsOf: url)
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            return try dec.decode([Candle].self, from: data)
        } catch {
            return nil
        }
    }

    func save(symbol: String, candles: [Candle]) {
        let url = fileURL(symbol: symbol)

        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted]
            enc.dateEncodingStrategy = .iso8601
            let data = try enc.encode(candles)
            try data.write(to: url, options: [.atomic])
        } catch {
            // debug istersen: print("CandleCache.save error:", error)
        }
    }

    /// İstersen: tek sembolü cache’den sil
    func remove(symbol: String) {
        let url = fileURL(symbol: symbol)
        try? fm.removeItem(at: url)
    }

    /// İstersen: tüm cache’i temizle
    func removeAll() {
        guard let items = try? fm.contentsOfDirectory(
            at: baseURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for u in items where u.pathExtension.lowercased() == "json" {
            try? fm.removeItem(at: u)
        }
    }

    // MARK: - Private

    private func fileURL(symbol: String) -> URL {
        // Dosya adına uygun hale getir
        let safe = symbol
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "_")
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: ":", with: "_")

        return baseURL.appendingPathComponent("\(safe).json")
    }
}

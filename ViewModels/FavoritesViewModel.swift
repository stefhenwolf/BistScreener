//
//  FavoritesViewModel.swift
//  BistScreener
//
//  Created by Sedat Pala on 18.02.2026.
//

import Foundation

struct FavoriteRow: Identifiable, Hashable, Codable {
    var id: String { symbol }
    let symbol: String
    let lastDate: Date?
    let lastClose: Double?
    let changePct: Double?   // ✅ artık opsiyonel (1 mum gelirse nil)
}

@MainActor
final class FavoritesViewModel: ObservableObject {
    @Published var rows: [FavoriteRow] = []
    @Published var isLoading = false
    @Published var errorText: String?

    private let yahoo = YahooFinanceService()

    // Persist (kullanıcı "Güncelle" butonuna basmadan da liste boş kalmasın)
    private let cacheKeyPrefix = "favorites_rows_cache_v1"
    private var activeUserKey: String = "guest"

    init() {
        loadFromDisk()
    }

    func setActiveUserKey(_ userKey: String?) {
        let cleaned = sanitize(userKey)
        guard cleaned != activeUserKey else { return }
        activeUserKey = cleaned
        loadFromDisk()
    }

    /// Sadece sembol listesini UI'ya yansıt (network yok).
    /// Yeni eklenenleri placeholder olarak ekler; kaldırılanları listeden düşürür.
    func setSymbols(_ symbols: [String]) {
        let uniq = Array(Set(symbols)).sorted()
        let existing = Dictionary(uniqueKeysWithValues: rows.map { ($0.symbol, $0) })
        rows = uniq.map { existing[$0] ?? FavoriteRow(symbol: $0, lastDate: nil, lastClose: nil, changePct: nil) }
    }

    func refresh(symbols: [String]) {
        isLoading = true
        errorText = nil

        Task {
            do {
                let fetched = try await fetchRows(symbols: symbols)
                // Favoriler sırası alfabetik
                self.rows = fetched.sorted { $0.symbol < $1.symbol }
                self.saveToDisk()
                self.isLoading = false
            } catch {
                self.errorText = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    private func loadFromDisk() {
        let cacheKey = "\(cacheKeyPrefix).\(activeUserKey)"
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return }
        do {
            let decoded = try JSONDecoder().decode([FavoriteRow].self, from: data)
            self.rows = decoded
        } catch {
            UserDefaults.standard.removeObject(forKey: cacheKey)
        }
    }

    private func saveToDisk() {
        let cacheKey = "\(cacheKeyPrefix).\(activeUserKey)"
        do {
            let data = try JSONEncoder().encode(rows)
            UserDefaults.standard.set(data, forKey: cacheKey)
        } catch {
            // sessiz
        }
    }

    private func sanitize(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "guest" }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        let chars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let out = String(chars)
        return out.isEmpty ? "guest" : out
    }

    private func fetchRows(symbols: [String]) async throws -> [FavoriteRow] {
        let limit = 3
        var iter = symbols.makeIterator()
        var out: [FavoriteRow] = []
        out.reserveCapacity(symbols.count)

        try await withThrowingTaskGroup(of: FavoriteRow.self) { group in
            for _ in 0..<min(limit, symbols.count) {
                if let s = iter.next() {
                    group.addTask { [yahoo] in
                        return await Self.fetchOneSafe(symbol: s, yahoo: yahoo)
                    }
                }
            }

            while let res = try await group.next() {
                out.append(res)

                if let next = iter.next() {
                    group.addTask { [yahoo] in
                        return await Self.fetchOneSafe(symbol: next, yahoo: yahoo)
                    }
                }
            }
        }

        return out
    }

    // ✅ Hata olsa bile satırı geri döndür (UI'da sembol en azından görünsün)
    private static func fetchOneSafe(symbol: String, yahoo: YahooFinanceService) async -> FavoriteRow {
        do {
            // 5d yerine 1mo: tatillerde bile genelde 2+ işlem günü yakalar
            let candles = try await yahoo.fetchDailyCandles(symbol: symbol, range: "1mo")

            guard let last = candles.last else {
                return FavoriteRow(symbol: symbol, lastDate: nil, lastClose: nil, changePct: nil)
            }

            let lastClose = last.close
            let lastDate = last.date

            var changePct: Double? = nil
            if candles.count >= 2 {
                let prev = candles[candles.count - 2]
                changePct = ((last.close - prev.close) / max(prev.close, 0.000001)) * 100.0
            }

            return FavoriteRow(symbol: symbol, lastDate: lastDate, lastClose: lastClose, changePct: changePct)
        } catch {
            return FavoriteRow(symbol: symbol, lastDate: nil, lastClose: nil, changePct: nil)
        }
    }
}

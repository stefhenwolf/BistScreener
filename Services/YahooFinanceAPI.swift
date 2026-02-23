//
//  YahooFinanceAPI.swift
//  BistScreener
//
//  Created by Sedat Pala on 18.02.2026.
//

import Foundation

// MARK: - Candle Model

struct Candle: Identifiable, Hashable, Codable {
    let id: UUID
    let date: Date
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Int

    init(date: Date, open: Double, high: Double, low: Double, close: Double, volume: Int) {
        self.id = UUID()
        self.date = date
        self.open = open
        self.high = high
        self.low = low
        self.close = close
        self.volume = volume
    }
}

// MARK: - Yahoo Finance (v8/finance/chart) Response

struct YahooChartResponse: Decodable {
    let chart: Chart

    struct Chart: Decodable {
        let result: [Result]?
        let error: YahooError?
    }

    struct YahooError: Decodable {
        let code: String?
        let description: String?
    }

    struct Result: Decodable {
        let timestamp: [Int]?
        let indicators: Indicators
    }

    struct Indicators: Decodable {
        let quote: [Quote]?
    }

    struct Quote: Decodable {
        let open: [Double?]?
        let high: [Double?]?
        let low: [Double?]?
        let close: [Double?]?
        let volume: [Int?]?
    }
}

// MARK: - Optional helpers (flatten Double?? -> Double?)

private protocol AnyOptional {
    associatedtype Wrapped
    var wrapped: Wrapped? { get }
}

extension Optional: AnyOptional {
    var wrapped: Wrapped? { self }
}

extension Array where Element: AnyOptional {
    func unwrapped(at index: Int) -> Element.Wrapped? {
        guard indices.contains(index) else { return nil }
        return self[index].wrapped
    }
}

// MARK: - Service

final class YahooFinanceService {

    // MARK: - Global rate limiting (shared across all instances)

    /// Yahoo zaman zaman 429 (Too Many Requests) döndürür. Uygulama içinde nereden çağrılırsa çağrılsın
    /// aynı global throttle'dan geçsin diye static tutulur.
    private static let globalThrottle = AsyncThrottle(minInterval: 0.50)

    /// Aynı anda en fazla 3 istek uçsun (Yahoo 429'u önler)
    private static let concurrencyGate = AsyncSemaphore(value: 3)

    /// Retry ayarları
    private struct RetryPolicy {
        let maxAttempts: Int
        let baseDelay: TimeInterval
        let maxDelay: TimeInterval

        static let `default` = RetryPolicy(maxAttempts: 5, baseDelay: 0.7, maxDelay: 8.0)
    }

    /// range examples: "10d", "1mo", "3mo", "6mo", "1y", "5y", "max"
    func fetchDailyCandles(symbol: String, range: String = "6mo") async throws -> [Candle] {

        // ✅ Yahoo path encoding: XAUUSD=X gibi sembollerde "=" var, .urlPathAllowed bazen sorun çıkarır
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-=^"))
        let sym = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let encodedSymbol = sym.addingPercentEncoding(withAllowedCharacters: allowed) ?? sym

        var components = URLComponents(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encodedSymbol)")!
        components.queryItems = [
            .init(name: "range", value: range),
            .init(name: "interval", value: "1d"),
            .init(name: "includePrePost", value: "false"),
            .init(name: "events", value: "div|split")
        ]

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        // ✅ Header’larla daha stabil
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.setValue("BistScreener/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("tr-TR,tr;q=0.9,en-US;q=0.8,en;q=0.7", forHTTPHeaderField: "Accept-Language")
        req.setValue("https://finance.yahoo.com/", forHTTPHeaderField: "Referer")

        // ✅ Concurrency gate: aynı anda max 3 istek uçabilir
        await YahooFinanceService.concurrencyGate.wait()
        defer { YahooFinanceService.concurrencyGate.signalFromSync() }

        // ✅ 429/5xx gibi durumlar için retry + exponential backoff
        let policy = RetryPolicy.default

        for attempt in 0..<policy.maxAttempts {
            // Global rate limit (burst'leri azaltır)
            await YahooFinanceService.globalThrottle.wait()

            do {
                let (data, response) = try await URLSession.shared.data(for: req)

                guard let http = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }

                if !(200...299).contains(http.statusCode) {
                    let body = String(data: data.prefix(900), encoding: .utf8) ?? "<non-utf8>"
                    if shouldRetry(status: http.statusCode), attempt < (policy.maxAttempts - 1) {
                        let d = backoffDelay(attempt: attempt, policy: policy, status: http.statusCode)
                        print("Yahoo HTTP \(http.statusCode) retry in \(String(format: "%.2f", d))s sym=\(sym)")
                        try? await Task.sleep(nanoseconds: UInt64(d * 1_000_000_000))
                        continue
                    }

                    // Debug için
                    print("Yahoo HTTP \(http.statusCode) sym=\(sym) url=\(url)\n\(body)")
                    throw NSError(
                        domain: "YahooHTTP",
                        code: http.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: "Yahoo HTTP \(http.statusCode) (\(sym))"]
                    )
                }

                let decoded = try JSONDecoder().decode(YahooChartResponse.self, from: data)

                if let err = decoded.chart.error?.description {
                    throw NSError(domain: "YahooFinance", code: 1, userInfo: [NSLocalizedDescriptionKey: err])
                }

                guard
                    let result = decoded.chart.result?.first,
                    let timestamps = result.timestamp,
                    let quote = result.indicators.quote?.first
                else {
                    return []
                }

                var candles: [Candle] = []
                candles.reserveCapacity(timestamps.count)

                for (i, ts) in timestamps.enumerated() {
                    guard
                        let o = quote.open?.unwrapped(at: i),
                        let h = quote.high?.unwrapped(at: i),
                        let l = quote.low?.unwrapped(at: i),
                        let c = quote.close?.unwrapped(at: i)
                    else { continue }

                    // ✅ Volume çoğu enstrümanda nil gelebilir → 0 kabul
                    let v = quote.volume?.unwrapped(at: i) ?? 0

                    candles.append(
                        Candle(
                            date: Date(timeIntervalSince1970: TimeInterval(ts)),
                            open: o, high: h, low: l, close: c,
                            volume: v
                        )
                    )
                }

                return candles.sorted { $0.date < $1.date }

            } catch {
                // Network hatası vs: retryable ise backoff
                if attempt < (policy.maxAttempts - 1) {
                    let d = backoffDelay(attempt: attempt, policy: policy, status: nil)
                    try? await Task.sleep(nanoseconds: UInt64(d * 1_000_000_000))
                    continue
                }
                throw error
            }
        }

        // Teorik olarak buraya düşmemeli
        return []
    }

    // MARK: - Retry helpers

    private func shouldRetry(status: Int) -> Bool {
        // 429 (rate limit) + 5xx (geçici) + 408/409 gibi bazı geçici durumlar
        switch status {
        case 408, 409, 425, 429, 500, 502, 503, 504:
            return true
        default:
            return false
        }
    }

    private func backoffDelay(attempt: Int, policy: RetryPolicy, status: Int?) -> TimeInterval {
        // Exponential backoff + jitter
        // 429 için biraz daha agresif başla
        let base = (status == 429) ? max(policy.baseDelay, 1.0) : policy.baseDelay
        let exp = base * pow(2.0, Double(attempt))
        let capped = min(exp, policy.maxDelay)
        let jitter = Double.random(in: 0...(min(0.35, capped * 0.15)))
        return capped + jitter
    }
}

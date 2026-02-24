import Foundation

enum ScanSnapshotStore {
    // MARK: - Filenames

    static let baseFilename = "scan_snapshot_v1"

    // MARK: - Legacy (single file)

    static func save(_ snapshot: PersistedScanSnapshot) throws {
        let url = try fileURL(indexRaw: nil)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url, options: [.atomic])
        NotificationCenter.default.post(
            name: .scanSnapshotSaved,
            object: nil,
            userInfo: [
                "indexRaw": snapshot.indexRaw,
                "savedAt": snapshot.savedAt
            ]
        )
    }

    static func load() throws -> PersistedScanSnapshot {
        let url = try fileURL(indexRaw: nil)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(PersistedScanSnapshot.self, from: data)
    }

    static func delete() throws {
        let url = try fileURL(indexRaw: nil)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Indexed (per index)

    static func save(_ snapshot: PersistedScanSnapshot, forIndexRaw indexRaw: String) throws {
        let url = try fileURL(indexRaw: indexRaw)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url, options: [.atomic])
        NotificationCenter.default.post(
            name: .scanSnapshotSaved,
            object: nil,
            userInfo: [
                "indexRaw": indexRaw,
                "savedAt": snapshot.savedAt
            ]
        )
    }

    static func load(forIndexRaw indexRaw: String) throws -> PersistedScanSnapshot {
        let url = try fileURL(indexRaw: indexRaw)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(PersistedScanSnapshot.self, from: data)
    }

    static func delete(forIndexRaw indexRaw: String) throws {
        let url = try fileURL(indexRaw: indexRaw)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    static func deleteAll() throws {
        try? delete()
        for opt in IndexOption.allCases {
            try? delete(forIndexRaw: opt.rawValue)
        }
    }

    // MARK: - Helpers

    private static func fileURL(indexRaw: String?) throws -> URL {
        let dir = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let suffix: String
        if let indexRaw, !indexRaw.isEmpty {
            let safe = indexRaw
                .replacingOccurrences(of: " ", with: "_")
                .replacingOccurrences(of: "/", with: "_")
            suffix = "_\(safe.lowercased())"
        } else {
            suffix = ""
        }

        return dir.appendingPathComponent("\(baseFilename)\(suffix).json")
    }
}

// MARK: - Models

struct PersistedScanSnapshot: Codable {
    let savedAt: Date
    let indexRaw: String
    let universeCount: Int
    let results: [PersistedScanResult]
}

struct PersistedScanResult: Codable {
    let symbol: String
    let lastDate: Date
    let lastClose: Double
    let changePct: Double
    let patterns: [PersistedPatternScore]

    // legacy birleşik sinyal (optional - geriye uyum)
    let signalTotal: Int?
    let signalDirection: Int?
    let signalQuality: Int?
    let signalConfidence: Int?
    let signal: TradeSignal?

    // ✅ tomorrow BUY-only snapshot (optional - geriye uyum)
    let tomorrowTotal: Int?
    let tomorrowQuality: String?
    let tomorrowTier: LiquidityTier?
    let tomorrowReasons: [String]?
    let tomorrowBreakdown: TomorrowBreakdown?

    init(
        symbol: String,
        lastDate: Date,
        lastClose: Double,
        changePct: Double,
        patterns: [PersistedPatternScore],

        // legacy
        signalTotal: Int? = nil,
        signalDirection: Int? = nil,
        signalQuality: Int? = nil,
        signalConfidence: Int? = nil,
        signal: TradeSignal? = nil,

        // tomorrow
        tomorrowTotal: Int? = nil,
        tomorrowQuality: String? = nil,
        tomorrowTier: LiquidityTier? = nil,
        tomorrowReasons: [String]? = nil,
        tomorrowBreakdown: TomorrowBreakdown? = nil
    ) {
        self.symbol = symbol
        self.lastDate = lastDate
        self.lastClose = lastClose
        self.changePct = changePct
        self.patterns = patterns

        self.signalTotal = signalTotal
        self.signalDirection = signalDirection
        self.signalQuality = signalQuality
        self.signalConfidence = signalConfidence
        self.signal = signal

        self.tomorrowTotal = tomorrowTotal
        self.tomorrowQuality = tomorrowQuality
        self.tomorrowTier = tomorrowTier
        self.tomorrowReasons = tomorrowReasons
        self.tomorrowBreakdown = tomorrowBreakdown
    }
}

/// Snapshot formatı eskiden `Double score` ile kaydedilmiş olabilir.
/// Bu model hem `Int` hem `Double` score'u decode eder (migrasyon amaçlı).
struct PersistedPatternScore: Codable {
    let name: String
    let score: Int
    let direction: String?

    enum CodingKeys: String, CodingKey {
        case name, score, direction
    }

    init(name: String, score: Int, direction: String?) {
        self.name = name
        self.score = score
        self.direction = direction
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        direction = try c.decodeIfPresent(String.self, forKey: .direction)

        if let i = try? c.decode(Int.self, forKey: .score) {
            score = i
        } else if let d = try? c.decode(Double.self, forKey: .score) {
            score = Int(d.rounded())
        } else {
            score = 0
        }
    }
}

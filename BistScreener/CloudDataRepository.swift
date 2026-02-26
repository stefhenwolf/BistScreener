import Foundation

protocol CloudDataRepository {
    func fetchStrategySnapshot(userID: String) async throws -> StrategyCloudSnapshot?
    func upsertStrategySnapshot(userID: String, snapshot: StrategyCloudSnapshot) async throws

    func appendStrategyEvents(userID: String, events: [LiveStrategyEvent]) async throws
    func fetchRecentStrategyEvents(userID: String, limit: Int) async throws -> [LiveStrategyEvent]

    func replacePortfolioPositions(userID: String, assets: [Asset]) async throws
    func fetchPortfolioPositions(userID: String) async throws -> [Asset]

    func upsertWatchlist(userID: String, symbols: [String]) async throws
    func fetchWatchlist(userID: String) async throws -> [String]?

    func upsertScanSnapshot(userID: String, snapshot: PersistedScanSnapshot, indexRaw: String) async throws
    func fetchScanSnapshot(userID: String, indexRaw: String) async throws -> PersistedScanSnapshot?

    func upsertScanStats(userID: String, stats: ScanCloudStats) async throws
    func fetchScanStats(userID: String) async throws -> ScanCloudStats?
}

struct ScanCloudStats: Codable {
    let lastScanDate: Date?
    let lastUniverseCount: Int
    let lastMatchesCount: Int
    let updatedAt: Date

    init(lastScanDate: Date?, lastUniverseCount: Int, lastMatchesCount: Int, updatedAt: Date = Date()) {
        self.lastScanDate = lastScanDate
        self.lastUniverseCount = lastUniverseCount
        self.lastMatchesCount = lastMatchesCount
        self.updatedAt = updatedAt
    }
}

struct StrategyCloudSnapshot: Codable {
    let schemaVersion: Int
    let updatedAt: Date
    let isRunning: Bool
    let startedAt: Date?
    let lastUpdated: Date?
    let sourceSnapshotDate: Date?
    let initialCapitalTL: Double
    let cashTL: Double
    let settings: LiveStrategySettings
    let holdings: [LiveStrategyHolding]
    let pendingActions: [LiveStrategyPendingAction]
    let skipBuyUntil: Date?
    let lastBuyWindowRunAt: Date?

    init(
        schemaVersion: Int = 1,
        updatedAt: Date = Date(),
        isRunning: Bool,
        startedAt: Date?,
        lastUpdated: Date?,
        sourceSnapshotDate: Date?,
        initialCapitalTL: Double,
        cashTL: Double,
        settings: LiveStrategySettings,
        holdings: [LiveStrategyHolding],
        pendingActions: [LiveStrategyPendingAction],
        skipBuyUntil: Date?,
        lastBuyWindowRunAt: Date?
    ) {
        self.schemaVersion = schemaVersion
        self.updatedAt = updatedAt
        self.isRunning = isRunning
        self.startedAt = startedAt
        self.lastUpdated = lastUpdated
        self.sourceSnapshotDate = sourceSnapshotDate
        self.initialCapitalTL = initialCapitalTL
        self.cashTL = cashTL
        self.settings = settings
        self.holdings = holdings
        self.pendingActions = pendingActions
        self.skipBuyUntil = skipBuyUntil
        self.lastBuyWindowRunAt = lastBuyWindowRunAt
    }
}

actor NoopCloudDataRepository: CloudDataRepository {
    func fetchStrategySnapshot(userID: String) async throws -> StrategyCloudSnapshot? { nil }
    func upsertStrategySnapshot(userID: String, snapshot: StrategyCloudSnapshot) async throws { }
    func appendStrategyEvents(userID: String, events: [LiveStrategyEvent]) async throws { }
    func fetchRecentStrategyEvents(userID: String, limit: Int) async throws -> [LiveStrategyEvent] { [] }
    func replacePortfolioPositions(userID: String, assets: [Asset]) async throws { }
    func fetchPortfolioPositions(userID: String) async throws -> [Asset] { [] }
    func upsertWatchlist(userID: String, symbols: [String]) async throws { }
    func fetchWatchlist(userID: String) async throws -> [String]? { nil }
    func upsertScanSnapshot(userID: String, snapshot: PersistedScanSnapshot, indexRaw: String) async throws { }
    func fetchScanSnapshot(userID: String, indexRaw: String) async throws -> PersistedScanSnapshot? { nil }
    func upsertScanStats(userID: String, stats: ScanCloudStats) async throws { }
    func fetchScanStats(userID: String) async throws -> ScanCloudStats? { nil }
}

#if canImport(FirebaseFirestore)
import FirebaseFirestore

actor FirestoreCloudDataRepository: CloudDataRepository {
    private let db: Firestore

    init(db: Firestore? = nil) {
        self.db = db ?? Firestore.firestore()
    }

    func fetchStrategySnapshot(userID: String) async throws -> StrategyCloudSnapshot? {
        let ref = strategyStateRef(userID: userID)
        let snap = try await ref.getDocument()
        guard let data = snap.data() else { return nil }
        return try decode(data, as: StrategyCloudSnapshot.self)
    }

    func upsertStrategySnapshot(userID: String, snapshot: StrategyCloudSnapshot) async throws {
        let ref = strategyStateRef(userID: userID)
        var data = try encode(snapshot)
        data["updatedAtEpoch"] = snapshot.updatedAt.timeIntervalSince1970
        try await ref.setData(data, merge: true)
    }

    func appendStrategyEvents(userID: String, events: [LiveStrategyEvent]) async throws {
        guard !events.isEmpty else { return }
        let batch = db.batch()
        for event in events {
            let ref = strategyEventsCol(userID: userID).document(event.id.uuidString)
            var data = try encode(event)
            data["dateEpoch"] = event.date.timeIntervalSince1970
            batch.setData(data, forDocument: ref, merge: true)
        }
        try await batch.commit()
    }

    func fetchRecentStrategyEvents(userID: String, limit: Int) async throws -> [LiveStrategyEvent] {
        let safeLimit = min(max(limit, 1), 1000)
        let query = strategyEventsCol(userID: userID)
            .order(by: "dateEpoch", descending: true)
            .limit(to: safeLimit)
        let snap = try await query.getDocuments()
        var out: [LiveStrategyEvent] = []
        for doc in snap.documents {
            out.append(try decode(doc.data(), as: LiveStrategyEvent.self))
        }
        return out.sorted { $0.date > $1.date }
    }

    func replacePortfolioPositions(userID: String, assets: [Asset]) async throws {
        let col = portfolioPositionsCol(userID: userID)
        let existing = try await col.getDocuments()
        let batch = db.batch()

        for doc in existing.documents {
            batch.deleteDocument(doc.reference)
        }

        for asset in assets {
            let id = asset.id.uuidString
            let ref = col.document(id)
            var data = try encode(asset)
            data["updatedAtEpoch"] = Date().timeIntervalSince1970
            batch.setData(data, forDocument: ref, merge: true)
        }

        try await batch.commit()
    }

    func fetchPortfolioPositions(userID: String) async throws -> [Asset] {
        let snap = try await portfolioPositionsCol(userID: userID).getDocuments()
        return try snap.documents.map { try decode($0.data(), as: Asset.self) }
    }

    func upsertWatchlist(userID: String, symbols: [String]) async throws {
        var data: [String: Any] = [:]
        data["symbols"] = symbols
        data["updatedAtEpoch"] = Date().timeIntervalSince1970
        try await watchlistRef(userID: userID).setData(data, merge: true)
    }

    func fetchWatchlist(userID: String) async throws -> [String]? {
        let snap = try await watchlistRef(userID: userID).getDocument()
        guard let data = snap.data() else { return nil }
        return data["symbols"] as? [String]
    }

    func upsertScanSnapshot(userID: String, snapshot: PersistedScanSnapshot, indexRaw: String) async throws {
        var data = try encode(snapshot)
        data["savedAtEpoch"] = snapshot.savedAt.timeIntervalSince1970
        data["updatedAtEpoch"] = Date().timeIntervalSince1970
        try await scanSnapshotsCol(userID: userID).document(indexRaw).setData(data, merge: true)
    }

    func fetchScanSnapshot(userID: String, indexRaw: String) async throws -> PersistedScanSnapshot? {
        let snap = try await scanSnapshotsCol(userID: userID).document(indexRaw).getDocument()
        guard let data = snap.data() else { return nil }
        return try decode(data, as: PersistedScanSnapshot.self)
    }

    func upsertScanStats(userID: String, stats: ScanCloudStats) async throws {
        var data = try encode(stats)
        data["updatedAtEpoch"] = stats.updatedAt.timeIntervalSince1970
        try await scanStatsRef(userID: userID).setData(data, merge: true)
    }

    func fetchScanStats(userID: String) async throws -> ScanCloudStats? {
        let snap = try await scanStatsRef(userID: userID).getDocument()
        guard let data = snap.data() else { return nil }
        return try decode(data, as: ScanCloudStats.self)
    }

    private func strategyStateRef(userID: String) -> DocumentReference {
        db.collection("users").document(userID).collection("strategyState").document("live")
    }

    private func strategyEventsCol(userID: String) -> CollectionReference {
        db.collection("users").document(userID).collection("strategyEvents")
    }

    private func portfolioPositionsCol(userID: String) -> CollectionReference {
        db.collection("users").document(userID).collection("portfolioPositions")
    }

    private func watchlistRef(userID: String) -> DocumentReference {
        db.collection("users").document(userID).collection("watchlist").document("state")
    }

    private func scanSnapshotsCol(userID: String) -> CollectionReference {
        db.collection("users").document(userID).collection("scanSnapshots")
    }

    private func scanStatsRef(userID: String) -> DocumentReference {
        db.collection("users").document(userID).collection("scanState").document("stats")
    }

    private func encode<T: Encodable>(_ value: T) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        let json = try JSONSerialization.jsonObject(with: data)
        guard let dict = json as? [String: Any] else {
            throw NSError(domain: "FirestoreCloudDataRepository", code: 1001)
        }
        return dict
    }

    private func decode<T: Decodable>(_ dict: [String: Any], as type: T.Type) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: dict)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }
}
#endif

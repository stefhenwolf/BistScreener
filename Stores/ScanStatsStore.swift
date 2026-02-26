import Foundation
import SwiftUI

@MainActor
final class ScanStatsStore: ObservableObject {
    static let shared = ScanStatsStore()

    @Published private(set) var lastScanDate: Date?
    @Published private(set) var lastUniverseCount: Int = 0
    @Published private(set) var lastMatchesCount: Int = 0

    private let ud = UserDefaults.standard
    private let keyPrefix = "scanStats"
    private var activeUserKey: String = "guest"

    private init() {
        reloadFromStorage()
    }

    func setActiveUserKey(_ userKey: String?) {
        let cleaned = sanitize(userKey)
        guard cleaned != activeUserKey else { return }
        activeUserKey = cleaned
        reloadFromStorage()
    }

    func update(date: Date, universeCount: Int, matchesCount: Int) {
        lastScanDate = date
        lastUniverseCount = universeCount
        lastMatchesCount = matchesCount

        // persist
        ud.set(date.timeIntervalSince1970, forKey: "\(keyPrefix).\(activeUserKey).lastScanDate")
        ud.set(universeCount, forKey: "\(keyPrefix).\(activeUserKey).lastUniverseCount")
        ud.set(matchesCount, forKey: "\(keyPrefix).\(activeUserKey).lastMatchesCount")
    }

    func applyCloud(lastScanDate: Date?, universeCount: Int, matchesCount: Int) {
        self.lastScanDate = lastScanDate
        self.lastUniverseCount = universeCount
        self.lastMatchesCount = matchesCount
        ud.set(lastScanDate?.timeIntervalSince1970, forKey: "\(keyPrefix).\(activeUserKey).lastScanDate")
        ud.set(universeCount, forKey: "\(keyPrefix).\(activeUserKey).lastUniverseCount")
        ud.set(matchesCount, forKey: "\(keyPrefix).\(activeUserKey).lastMatchesCount")
    }

    private func reloadFromStorage() {
        let kDate = "\(keyPrefix).\(activeUserKey).lastScanDate"
        let kUniverse = "\(keyPrefix).\(activeUserKey).lastUniverseCount"
        let kMatches = "\(keyPrefix).\(activeUserKey).lastMatchesCount"
        if let t = ud.object(forKey: kDate) as? TimeInterval {
            lastScanDate = Date(timeIntervalSince1970: t)
        } else {
            lastScanDate = nil
        }
        lastUniverseCount = ud.integer(forKey: kUniverse)
        lastMatchesCount = ud.integer(forKey: kMatches)
    }

    private func sanitize(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "guest" }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        let chars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let out = String(chars)
        return out.isEmpty ? "guest" : out
    }
}

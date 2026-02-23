import Foundation
import SwiftUI

@MainActor
final class ScanStatsStore: ObservableObject {
    static let shared = ScanStatsStore()

    @Published private(set) var lastScanDate: Date?
    @Published private(set) var lastUniverseCount: Int = 0
    @Published private(set) var lastMatchesCount: Int = 0

    private let ud = UserDefaults.standard
    private let kDate = "scanStats.lastScanDate"
    private let kUniverse = "scanStats.lastUniverseCount"
    private let kMatches = "scanStats.lastMatchesCount"

    private init() {
        // app açılışında oku
        if let t = ud.object(forKey: kDate) as? TimeInterval {
            lastScanDate = Date(timeIntervalSince1970: t)
        }
        lastUniverseCount = ud.integer(forKey: kUniverse)
        lastMatchesCount = ud.integer(forKey: kMatches)
    }

    func update(date: Date, universeCount: Int, matchesCount: Int) {
        lastScanDate = date
        lastUniverseCount = universeCount
        lastMatchesCount = matchesCount

        // persist
        ud.set(date.timeIntervalSince1970, forKey: kDate)
        ud.set(universeCount, forKey: kUniverse)
        ud.set(matchesCount, forKey: kMatches)
    }
}

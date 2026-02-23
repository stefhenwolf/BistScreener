import SwiftUI

@main
struct BistScreenerApp: App {
    @StateObject private var watchlist = WatchlistStore()
    @StateObject private var services = AppServices()
    @StateObject private var settings = SettingsStore()

    init() {
        TVAppearance.apply()   // ✅ TabBar + NavBar TV görünümü
    }

    var body: some Scene {
        WindowGroup {
            ContentView(services: services, settings: settings)
                .environmentObject(watchlist)
                .environmentObject(services)
                .environmentObject(settings)
        }
    }
}

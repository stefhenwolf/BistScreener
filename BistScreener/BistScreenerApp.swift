import SwiftUI
import UIKit
import UserNotifications
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif
#if canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(FirebaseAppCheck)
import FirebaseAppCheck
#endif

#if canImport(FirebaseCore) && canImport(FirebaseAppCheck)
final class BistScreenerAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> (any AppCheckProvider)? {
#if DEBUG
        return AppCheckDebugProvider(app: app)
#else
        if #available(iOS 14.0, *) {
            return AppAttestProvider(app: app)
        }
        return DeviceCheckProvider(app: app)
#endif
    }
}
#endif

final class BistScreenerAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        StrategyNotificationManager.shared.configureCenter(delegate: self)
        StrategyNotificationManager.shared.requestAuthorizationIfNeeded()
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        StrategyNotificationManager.shared.handleNotificationResponse(response)
        completionHandler()
    }
}

@main
struct BistScreenerApp: App {
    @UIApplicationDelegateAdaptor(BistScreenerAppDelegate.self) private var appDelegate
    @StateObject private var watchlist: WatchlistStore
    @StateObject private var services: AppServices
    @StateObject private var settings: SettingsStore
    @StateObject private var auth: AuthSessionStore

    init() {
#if canImport(FirebaseCore)
#if canImport(FirebaseAppCheck)
        AppCheck.setAppCheckProviderFactory(BistScreenerAppCheckProviderFactory())
#endif
        FirebaseApp.configure()
#endif
        let appServices = AppServices()
        _watchlist = StateObject(wrappedValue: WatchlistStore(cloudRepository: appServices.cloudRepository))
        _settings = StateObject(wrappedValue: SettingsStore())
        _auth = StateObject(wrappedValue: AuthSessionStore())
        _services = StateObject(wrappedValue: appServices)
        TVAppearance.apply()   // ✅ TabBar + NavBar TV görünümü
    }

    var body: some Scene {
        WindowGroup {
            ContentView(services: services, settings: settings)
                .environmentObject(watchlist)
                .environmentObject(services)
                .environmentObject(settings)
                .environmentObject(services.portfolio)
                .environmentObject(services.strategy)
                .environmentObject(auth)
#if canImport(GoogleSignIn)
                .onOpenURL { url in
                    if GIDSignIn.sharedInstance.handle(url) { return }
                    NotificationCenter.default.post(name: .appOpenDeepLink, object: url)
                }
#endif
        }
    }
}

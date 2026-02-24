import SwiftUI
import UIKit

struct ContentView: View {

    private let services: AppServices

    @State private var selectedTab: AppTab = .home

    @StateObject private var scannerHolder: ScannerVMHolder
    @State private var appliedConfig: ScannerConfig
    @State private var showSettingsSheet = false
    @StateObject private var tickerVM = MarketTickerViewModel()
    @State private var homePath = NavigationPath()
    @State private var scanPath = NavigationPath()
    @State private var formationsPath = NavigationPath()
    @State private var favoritesPath = NavigationPath()
    @State private var profilePath = NavigationPath()

    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var backtestEngine: BacktestEngine

    @MainActor
    init(services: AppServices, settings: SettingsStore) {
        self.services = services
        _backtestEngine = StateObject(wrappedValue: BacktestEngine(services: services))

        let initialConfig = ScannerConfig(from: settings)
        _appliedConfig = State(initialValue: initialConfig)

        let initialVM = ScannerViewModel(
            services: services,
            defaultIndex: initialConfig.defaultIndex,
            concurrencyLimit: initialConfig.concurrencyLimit,
            preset: initialConfig.preset,
            maxResults: initialConfig.maxResults
        )
        _scannerHolder = StateObject(wrappedValue: ScannerVMHolder(vm: initialVM))
    }

    private var currentSettingsConfig: ScannerConfig {
        ScannerConfig(from: settings)
    }

    private var hasPendingChanges: Bool {
        currentSettingsConfig != appliedConfig
    }

    private func applySettings() {
        let newConfig = currentSettingsConfig
        guard newConfig != appliedConfig else { return }

        scannerHolder.vm.cancelScan(silent: true)

        let newVM = ScannerViewModel(
            services: services,
            defaultIndex: newConfig.defaultIndex,
            concurrencyLimit: newConfig.concurrencyLimit,
            preset: newConfig.preset,
            maxResults: newConfig.maxResults
        )

        scannerHolder.vm = newVM
        appliedConfig = newConfig
        scannerHolder.vm.loadLastSnapshotFromDisk()
    }

    private var tabSelectionBinding: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                if newValue == selectedTab {
                    resetNavigation(for: newValue)
                }
                selectedTab = newValue
            }
        )
    }

    var body: some View {
        TabView(selection: tabSelectionBinding) {


            NavigationStack(path: $homePath) {
                HomeView(
                    selectedTab: $selectedTab,
                    openStrategyPage: openStrategyFromHome,
                    scannerVM: scannerHolder.vm,
                    tickerVM: tickerVM
                )
                .settingsButton(show: $showSettingsSheet)
            }
            .tabItem { Label("Anasayfa", systemImage: "house.fill") }
            .tag(AppTab.home)
            .tvNavStyle()

            NavigationStack(path: $scanPath) {
                ScanView(vm: scannerHolder.vm, engine: backtestEngine)
                    .settingsButton(show: $showSettingsSheet)
            }
            .tabItem { Label("Tarama", systemImage: "magnifyingglass") }
            .tag(AppTab.scan)
            .tvNavStyle()

            NavigationStack(path: $formationsPath) {
                FormationsView(vm: scannerHolder.vm)
                    .settingsButton(show: $showSettingsSheet)
            }
            .tabItem { Label("Formasyonlar", systemImage: "waveform.path.ecg") }
            .tag(AppTab.formations)
            .tvNavStyle()

            NavigationStack(path: $favoritesPath) {
                FavoritesView()
                    .settingsButton(show: $showSettingsSheet)
            }
            .tabItem { Label("Favoriler", systemImage: "star.fill") }
            .tag(AppTab.favorites)
            .tvNavStyle()
            
            NavigationStack(path: $profilePath) {
                ProfileView(selectedTab: $selectedTab)
                    .settingsButton(show: $showSettingsSheet)
            }
            .tabItem { Label("Profil", systemImage: "person.crop.circle") }
            .tag(AppTab.profile)
            .tvNavStyle() 


            

        }
        .toolbarBackground(TVTheme.bg, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .tint(TVTheme.up)
        .background(
            TabBarReselectObserver { reselectedIndex in
                guard let tab = tabForIndex(reselectedIndex) else { return }
                resetNavigation(for: tab)
            }
        )
        .sheet(isPresented: $showSettingsSheet) {
            // Ayarlar her yerden aynı sheet
            SettingsView(
                hasPendingChanges: hasPendingChanges,
                onApply: applySettings
            )
            .environmentObject(settings)
            .presentationBackground(TVTheme.bg)
        }
        .task {
            scannerHolder.vm.loadLastSnapshotFromDisk()
            tickerVM.start()
            tickerVM.refreshNow()
        }
        .onChangeCompat(of: scenePhase) { phase in
            if phase == .active {
                tickerVM.start()
                tickerVM.refreshNow()
            } else {
                tickerVM.stop()
            }
        }
    }

    private func tabForIndex(_ index: Int) -> AppTab? {
        switch index {
        case 0: return .home
        case 1: return .scan
        case 2: return .formations
        case 3: return .favorites
        case 4: return .profile
        default: return nil
        }
    }

    private func resetNavigation(for tab: AppTab) {
        switch tab {
        case .home:
            homePath = NavigationPath()
        case .scan:
            scanPath = NavigationPath()
        case .formations:
            formationsPath = NavigationPath()
        case .favorites:
            favoritesPath = NavigationPath()
        case .profile:
            profilePath = NavigationPath()
        }
    }

    private func openStrategyFromHome() {
        profilePath = NavigationPath()
        selectedTab = .profile
        profilePath.append(ProfileNavRoute.strategy)
    }
}

private struct TabBarReselectObserver: UIViewControllerRepresentable {
    let onReselect: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onReselect: onReselect)
    }

    func makeUIViewController(context: Context) -> ObserverViewController {
        let vc = ObserverViewController()
        vc.view.isUserInteractionEnabled = false
        vc.onResolve = { host in
            context.coordinator.attach(from: host)
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: ObserverViewController, context: Context) {
        context.coordinator.onReselect = onReselect
        uiViewController.onResolve = { host in
            context.coordinator.attach(from: host)
        }
    }

    final class ObserverViewController: UIViewController {
        var onResolve: ((UIViewController) -> Void)?

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            onResolve?(self)
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            onResolve?(self)
        }
    }

    final class Coordinator: NSObject, UITabBarControllerDelegate {
        var onReselect: (Int) -> Void
        weak var tabBarController: UITabBarController?
        weak var previousDelegate: UITabBarControllerDelegate?
        private var lastSelectedIndex: Int?

        init(onReselect: @escaping (Int) -> Void) {
            self.onReselect = onReselect
        }

        func attach(from host: UIViewController) {
            let resolved: UITabBarController? =
                host.tabBarController ??
                findTabBarController(startingAt: host.parent) ??
                findTabBarControllerFromKeyWindow()

            guard let tbc = resolved else { return }

            if tabBarController !== tbc {
                tabBarController = tbc
                if tbc.delegate !== self {
                    previousDelegate = tbc.delegate
                    tbc.delegate = self
                }
                lastSelectedIndex = tbc.selectedIndex
                return
            }

            if tbc.delegate !== self {
                previousDelegate = tbc.delegate
                tbc.delegate = self
            }
        }

        private func findTabBarController(startingAt root: UIViewController?) -> UITabBarController? {
            guard let root else { return nil }
            if let tbc = root as? UITabBarController { return tbc }

            for child in root.children {
                if let found = findTabBarController(startingAt: child) {
                    return found
                }
            }
            if let presented = root.presentedViewController {
                return findTabBarController(startingAt: presented)
            }
            return nil
        }

        private func findTabBarControllerFromKeyWindow() -> UITabBarController? {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            for scene in scenes {
                if let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController,
                   let found = findTabBarController(startingAt: root) {
                    return found
                }
            }
            return nil
        }

        func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
            previousDelegate?.tabBarController?(tabBarController, shouldSelect: viewController) ?? true
        }

        func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
            let selectedIndex = tabBarController.selectedIndex
            if let last = lastSelectedIndex, last == selectedIndex {
                onReselect(selectedIndex)
            }
            lastSelectedIndex = selectedIndex
            previousDelegate?.tabBarController?(tabBarController, didSelect: viewController)
        }
    }
}

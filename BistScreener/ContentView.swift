import SwiftUI

struct ContentView: View {

    private let services: AppServices

    @State private var selectedTab: AppTab = .home

    @StateObject private var scannerHolder: ScannerVMHolder
    @State private var appliedConfig: ScannerConfig
    @State private var showSettingsSheet = false
    @StateObject private var tickerVM = MarketTickerViewModel()

    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var settings: SettingsStore

    @MainActor
    init(services: AppServices, settings: SettingsStore) {
        self.services = services

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

    var body: some View {
        TabView(selection: $selectedTab) {


            NavigationStack {
                HomeView(
                    selectedTab: $selectedTab,
                    scannerVM: scannerHolder.vm,
                    tickerVM: tickerVM
                )
                .settingsButton(show: $showSettingsSheet)
            }
            .tabItem { Label("Anasayfa", systemImage: "house.fill") }
            .tag(AppTab.home)
            .tvNavStyle()

            NavigationStack {
                ScanView(vm: scannerHolder.vm)
                    .settingsButton(show: $showSettingsSheet)
            }
            .tabItem { Label("Tarama", systemImage: "magnifyingglass") }
            .tag(AppTab.scan)
            .tvNavStyle()

            NavigationStack {
                FormationsView(vm: scannerHolder.vm)
                    .settingsButton(show: $showSettingsSheet)
            }
            .tabItem { Label("Formasyonlar", systemImage: "waveform.path.ecg") }
            .tag(AppTab.formations)
            .tvNavStyle()

            NavigationStack {
                FavoritesView()
                    .settingsButton(show: $showSettingsSheet)
            }
            .tabItem { Label("Favoriler", systemImage: "star.fill") }
            .tag(AppTab.favorites)
            .tvNavStyle()
            
            NavigationStack {
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
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                tickerVM.start()
                tickerVM.refreshNow()
            } else {
                tickerVM.stop()
            }
        }
    }
}

import SwiftUI
import UIKit
import AuthenticationServices
import Security
import CryptoKit
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

struct ContentView: View {

    private let services: AppServices

    @State private var selectedTab: AppTab = .home

    @StateObject private var scannerHolder: ScannerVMHolder
    @State private var appliedConfig: ScannerConfig
    @State private var showSettingsSheet = false
    @State private var showProfileSettingsSheet = false
    @StateObject private var tickerVM = MarketTickerViewModel()
    @State private var homePath = NavigationPath()
    @State private var scanPath = NavigationPath()
    @State private var formationsPath = NavigationPath()
    @State private var favoritesPath = NavigationPath()
    @State private var profilePath = NavigationPath()

    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var watchlist: WatchlistStore
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
        Group {
            if auth.isAuthenticated {
                mainTabsView
            } else {
                AuthEntryView()
            }
        }
        .onAppear {
            applyUserScope()
            services.portfolio.setCloudUserID(auth.cloudUserID)
            services.strategy.setCloudUserID(auth.cloudUserID)
            if auth.isAuthenticated {
                applyQueuedStrategyApprovalCommands()
            }
        }
        .onChange(of: auth.currentUser?.providerUserID) { _ in
            applyUserScope()
            services.portfolio.setCloudUserID(auth.cloudUserID)
            services.strategy.setCloudUserID(auth.cloudUserID)
            if auth.isAuthenticated {
                applyQueuedStrategyApprovalCommands()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .strategyApprovalCommandQueued)) { _ in
            guard auth.isAuthenticated else { return }
            applyQueuedStrategyApprovalCommands()
        }
        .onReceive(NotificationCenter.default.publisher(for: .appOpenDeepLink)) { payload in
            guard let url = payload.object as? URL else { return }
            handleDeepLink(url)
        }
    }

    private func applyUserScope() {
        let localScope = auth.cloudUserID ?? auth.currentUser?.providerUserID
        let cloudScope = auth.cloudUserID
        watchlist.setUserContext(localUserKey: localScope, cloudUserID: cloudScope)
        ScanStatsStore.shared.setActiveUserKey(localScope)
        ScanSnapshotStore.setActiveUserKey(localScope)
        scannerHolder.vm.setUserContext(localUserKey: localScope, cloudUserID: cloudScope)
    }

    private var mainTabsView: some View {
        TabView(selection: tabSelectionBinding) {


            NavigationStack(path: $homePath) {
                HomeView(
                    selectedTab: $selectedTab,
                    openStrategyPage: openStrategyFromHome,
                    scannerVM: scannerHolder.vm,
                    tickerVM: tickerVM
                )
                .settingsButton(show: $showSettingsSheet)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            selectedTab = .profile
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "person.crop.circle.fill")
                                Text(auth.displayNameShort)
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(TVTheme.text)
                        }
                    }
                }
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
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                showProfileSettingsSheet = true
                            } label: {
                                Image(systemName: "gearshape.fill")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(TVTheme.text)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Profil Ayarları")
                        }
                    }
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
            SettingsView(
                hasPendingChanges: hasPendingChanges,
                onApply: applySettings
            )
            .environmentObject(settings)
            .presentationBackground(TVTheme.bg)
        }
        .sheet(isPresented: $showProfileSettingsSheet) {
            ProfileSettingsView()
                .environmentObject(auth)
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

    private func openStrategyFromNotification() {
        profilePath = NavigationPath()
        selectedTab = .profile
        profilePath.append(ProfileNavRoute.strategy)
    }

    private func applyQueuedStrategyApprovalCommands() {
        let commands = StrategyNotificationManager.shared.drainQueuedCommands()
        guard !commands.isEmpty else { return }

        for command in commands {
            switch command.kind {
            case .approve:
                guard let actionID = command.actionID else { continue }
                services.strategy.approvePendingAction(actionID)
                openStrategyFromNotification()
            case .reject:
                guard let actionID = command.actionID else { continue }
                services.strategy.rejectPendingAction(actionID)
                openStrategyFromNotification()
            case .approveAll:
                services.strategy.approveAllPendingActions()
                openStrategyFromNotification()
            case .rejectAll:
                services.strategy.rejectAllPendingActions()
                openStrategyFromNotification()
            case .openStrategy:
                openStrategyFromNotification()
            }
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme?.lowercased() == "bistscreener" else { return }
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()

        if host == "profile", path.contains("strategy") {
            openStrategyFromNotification()
            return
        }

        if host == "profile", path.contains("assets") {
            profilePath = NavigationPath()
            selectedTab = .profile
            profilePath.append(ProfileNavRoute.assets)
        }
    }
}

struct AuthUser: Codable, Equatable {
    let fullName: String
    let email: String
    let provider: String
    let providerUserID: String
    let signedInAt: Date
}

private struct ManualAccount: Codable, Equatable {
    let email: String
    let passwordHash: String
    let createdAt: Date
}

@MainActor
final class AuthSessionStore: ObservableObject {
    @Published private(set) var currentUser: AuthUser?
    @Published var authErrorText: String?
    @Published var authInfoText: String?
    @Published var rememberMe: Bool = true {
        didSet {
            UserDefaults.standard.set(rememberMe, forKey: rememberMeKey)
            if !rememberMe {
                KeychainStore.delete(service: keychainService, account: storageKey)
            } else if oldValue != rememberMe {
                persist()
            }
        }
    }

    private let storageKey = "auth_session_user_v1"
    private let rememberMeKey = "auth_session_remember_me_v1"
    private let manualAccountsKey = "manual_accounts_v1"
    private let keychainService = "com.sedat.BistScreener.auth"
    private let passwordPepper = "bistscreener_auth_pepper_v1"
    private var currentAppleNonce: String?

    init() {
        rememberMe = UserDefaults.standard.object(forKey: rememberMeKey) as? Bool ?? true
        restore()
    }

    var isAuthenticated: Bool { currentUser != nil }
    var cloudUserID: String? {
#if canImport(FirebaseAuth)
        return Auth.auth().currentUser?.uid
#endif
        return nil
    }
    var displayNameShort: String {
        let name = currentUser?.fullName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if name.isEmpty { return "Profil" }
        return name.components(separatedBy: " ").first ?? "Profil"
    }

    func signInManual(email: String, password: String) async {
        let trimmedEmail = normalizedEmail(email)
        authInfoText = nil
        authErrorText = nil
        guard trimmedEmail.contains("@"), trimmedEmail.contains(".") else {
            authErrorText = "Geçerli bir e-posta gir."
            return
        }
        guard password.count >= 6 else {
            authErrorText = "Şifre en az 6 karakter olmalı."
            return
        }
#if canImport(FirebaseAuth)
        do {
            let result = try await firebaseSignIn(email: trimmedEmail, password: password)
            let display = result.user.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackName = trimmedEmail
                .components(separatedBy: "@")
                .first?
                .replacingOccurrences(of: ".", with: " ")
                .capitalized ?? "Kullanıcı"
            currentUser = AuthUser(
                fullName: (display?.isEmpty == false) ? display! : fallbackName,
                email: result.user.email ?? trimmedEmail,
                provider: "manual",
                providerUserID: result.user.uid,
                signedInAt: Date()
            )
            persist()
            return
        } catch {
            authErrorText = "Giriş başarısız: \(error.localizedDescription)"
            return
        }
#else
        let accounts = loadManualAccounts()
        guard let account = accounts.first(where: { $0.email == trimmedEmail }) else {
            authErrorText = "Bu e-posta için üyelik bulunamadı. Önce Üye Ol."
            return
        }
        guard account.passwordHash == hashPassword(password) else {
            authErrorText = "E-posta veya şifre hatalı."
            return
        }

        let fallbackName = trimmedEmail
            .components(separatedBy: "@")
            .first?
            .replacingOccurrences(of: ".", with: " ")
            .capitalized ?? "Kullanıcı"
        currentUser = AuthUser(
            fullName: fallbackName,
            email: trimmedEmail,
            provider: "manual",
            providerUserID: "manual:\(trimmedEmail.lowercased())",
            signedInAt: Date()
        )
        persist()
#endif
    }

    func signUpManual(email: String, password: String, confirmPassword: String) async {
        let trimmedEmail = normalizedEmail(email)
        authInfoText = nil
        authErrorText = nil
        guard trimmedEmail.contains("@"), trimmedEmail.contains(".") else {
            authErrorText = "Geçerli bir e-posta gir."
            return
        }
        guard password.count >= 6 else {
            authErrorText = "Şifre en az 6 karakter olmalı."
            return
        }
        guard password == confirmPassword else {
            authErrorText = "Şifreler eşleşmiyor."
            return
        }

#if canImport(FirebaseAuth)
        do {
            let result = try await firebaseCreateUser(email: trimmedEmail, password: password)
            let fallbackName = trimmedEmail
                .components(separatedBy: "@")
                .first?
                .replacingOccurrences(of: ".", with: " ")
                .capitalized ?? "Kullanıcı"
            currentUser = AuthUser(
                fullName: fallbackName,
                email: result.user.email ?? trimmedEmail,
                provider: "manual",
                providerUserID: result.user.uid,
                signedInAt: Date()
            )
            authInfoText = "Üyelik oluşturuldu. Oturum açıldı."
            persist()
            return
        } catch {
            authErrorText = "Üyelik oluşturulamadı: \(error.localizedDescription)"
            return
        }
#else
        var accounts = loadManualAccounts()
        if accounts.contains(where: { $0.email == trimmedEmail }) {
            authErrorText = "Bu e-posta zaten kayıtlı. Giriş Yap sekmesini kullan."
            return
        }

        accounts.append(
            ManualAccount(
                email: trimmedEmail,
                passwordHash: hashPassword(password),
                createdAt: Date()
            )
        )
        saveManualAccounts(accounts)
        authInfoText = "Üyelik oluşturuldu. Oturum açıldı."
        await signInManual(email: trimmedEmail, password: password)
#endif
    }

    func requestPasswordReset(email: String) async {
        let trimmedEmail = normalizedEmail(email)
        guard trimmedEmail.contains("@"), trimmedEmail.contains(".") else {
            authInfoText = nil
            authErrorText = "Şifre sıfırlama için geçerli bir e-posta gir."
            return
        }
#if canImport(FirebaseAuth)
        do {
            try await firebaseSendPasswordReset(email: trimmedEmail)
            authErrorText = nil
            authInfoText = "Şifre sıfırlama bağlantısı gönderildi: \(trimmedEmail)"
            return
        } catch {
            authInfoText = nil
            authErrorText = "Şifre sıfırlama gönderilemedi: \(error.localizedDescription)"
            return
        }
#else
        guard loadManualAccounts().contains(where: { $0.email == trimmedEmail }) else {
            authInfoText = nil
            authErrorText = "Bu e-posta için üyelik bulunamadı."
            return
        }
        authErrorText = nil
        authInfoText = "Şifre sıfırlama bağlantısı gönderildi: \(trimmedEmail)"
#endif
    }

    func deleteCurrentAccount() async {
        authErrorText = nil
        authInfoText = nil
        guard let user = currentUser else {
            authErrorText = "Silinecek aktif hesap bulunamadı."
            return
        }
#if canImport(FirebaseAuth)
        if let firebaseUser = Auth.auth().currentUser {
            do {
                try await firebaseDeleteCurrentUser(firebaseUser)
            } catch {
                authErrorText = "Hesap silinemedi (yeniden giriş gerekebilir): \(error.localizedDescription)"
                return
            }
        }
#endif
        if user.provider == "manual" {
            let email = normalizedEmail(user.email)
            var accounts = loadManualAccounts()
            let originalCount = accounts.count
            accounts.removeAll { $0.email == email }
            saveManualAccounts(accounts)
            if accounts.count == originalCount {
                authErrorText = "Hesap bulunamadı veya daha önce silinmiş."
                return
            }
            authInfoText = "Hesap kalıcı olarak silindi."
        } else {
            authInfoText = "Sosyal hesap oturumu kapatıldı ve cihaz verisi temizlendi."
        }
        signOut()
    }

    func clearAllLocalUserData() {
        signOut()
        KeychainStore.delete(service: keychainService, account: manualAccountsKey)
        clearProfileMirror()
    }

    func signInWithAppleCredential(_ credential: ASAuthorizationAppleIDCredential) {
        Task {
            await signInWithAppleCredentialAsync(credential)
        }
    }

    private func signInWithAppleCredentialAsync(_ credential: ASAuthorizationAppleIDCredential) async {
        let previous = currentUser
        let incomingName = [credential.fullName?.givenName, credential.fullName?.familyName]
            .compactMap { $0 }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fullName = incomingName.isEmpty ? (previous?.fullName ?? "Apple Kullanıcısı") : incomingName
        let email = (credential.email?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? credential.email!.trimmingCharacters(in: .whitespacesAndNewlines)
            : (previous?.email ?? "")

        authErrorText = nil
#if canImport(FirebaseAuth)
        do {
            guard
                let tokenData = credential.identityToken,
                let idTokenString = String(data: tokenData, encoding: .utf8),
                let rawNonce = currentAppleNonce
            else {
                authErrorText = "Apple kimlik doğrulaması eksik (nonce/token)."
                return
            }
            let firebaseCredential = OAuthProvider.appleCredential(
                withIDToken: idTokenString,
                rawNonce: rawNonce,
                fullName: credential.fullName
            )
            let result = try await firebaseSignIn(with: firebaseCredential)
            let finalEmail = result.user.email ?? email
            let finalName = result.user.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            currentUser = AuthUser(
                fullName: (finalName?.isEmpty == false) ? finalName! : fullName,
                email: finalEmail,
                provider: "apple",
                providerUserID: result.user.uid,
                signedInAt: Date()
            )
            persist()
            currentAppleNonce = nil
            return
        } catch {
            authErrorText = "Apple giriş başarısız: \(error.localizedDescription)"
            currentAppleNonce = nil
            return
        }
#else
        currentUser = AuthUser(
            fullName: fullName,
            email: email,
            provider: "apple",
            providerUserID: credential.user,
            signedInAt: Date()
        )
        persist()
#endif
    }

    func signInWithGoogle() async {
#if canImport(GoogleSignIn)
        guard let topVC = UIApplication.shared.topMostViewController() else {
            authErrorText = "Google oturumu açılamadı (UI bulunamadı)."
            return
        }
        guard
            let clientID = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_ID") as? String,
            !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            authErrorText = "GOOGLE_CLIENT_ID eksik. Info.plist'e ekle."
            return
        }

        authErrorText = nil
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: topVC)
            let profile = result.user.profile
            let fullName = profile?.name ?? "Google Kullanıcısı"
            let email = profile?.email ?? ""
#if canImport(FirebaseAuth)
            guard
                let idToken = result.user.idToken?.tokenString,
                !idToken.isEmpty
            else {
                authErrorText = "Google kimlik doğrulaması alınamadı (idToken)."
                return
            }
            let accessToken = result.user.accessToken.tokenString
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)
            let authResult = try await firebaseSignIn(with: credential)
            currentUser = AuthUser(
                fullName: authResult.user.displayName ?? fullName,
                email: authResult.user.email ?? email,
                provider: "google",
                providerUserID: authResult.user.uid,
                signedInAt: Date()
            )
#else
            currentUser = AuthUser(
                fullName: fullName,
                email: email,
                provider: "google",
                providerUserID: result.user.userID ?? ("google:\(email.lowercased())"),
                signedInAt: Date()
            )
#endif
            persist()
        } catch {
            authErrorText = "Google giriş başarısız: \(error.localizedDescription)"
        }
#else
        authErrorText = "Google giriş için GoogleSignIn SDK eklenmeli."
#endif
    }

    func signOut() {
        authErrorText = nil
        authInfoText = nil
        currentUser = nil
#if canImport(GoogleSignIn)
        GIDSignIn.sharedInstance.signOut()
#endif
#if canImport(FirebaseAuth)
        do { try Auth.auth().signOut() } catch { }
#endif
        KeychainStore.delete(service: keychainService, account: storageKey)
        clearProfileMirror()
    }

    func updateDisplayName(_ rawName: String) {
        guard var user = currentUser else { return }
        let cleaned = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            authErrorText = "Ad soyad boş olamaz."
            return
        }
        user = AuthUser(
            fullName: cleaned,
            email: user.email,
            provider: user.provider,
            providerUserID: user.providerUserID,
            signedInAt: user.signedInAt
        )
        currentUser = user
        authErrorText = nil
        authInfoText = "Profil adı güncellendi."
        persist()
    }

    func configureAppleSignInRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = randomNonceString()
        currentAppleNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
    }

    private func restore() {
        guard rememberMe else { return }
        guard
            let data = KeychainStore.read(service: keychainService, account: storageKey),
            let user = try? JSONDecoder().decode(AuthUser.self, from: data)
        else { return }
        currentUser = user
        applyProfileMirror(user)
    }

    private func persist() {
        guard let currentUser else { return }
        if rememberMe, let data = try? JSONEncoder().encode(currentUser) {
            _ = KeychainStore.save(service: keychainService, account: storageKey, data: data)
        } else {
            KeychainStore.delete(service: keychainService, account: storageKey)
        }
        applyProfileMirror(currentUser)
    }

    private func applyProfileMirror(_ user: AuthUser) {
        UserDefaults.standard.set(user.fullName, forKey: "profile_name")
        if !user.email.isEmpty {
            UserDefaults.standard.set(user.email, forKey: "profile_note")
        }
        let role: String = {
            switch user.provider {
            case "apple": return "Apple ID"
            case "google": return "Google"
            default: return "Üye"
            }
        }()
        UserDefaults.standard.set(role, forKey: "profile_role")
    }

    private func normalizedEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func hashPassword(_ password: String) -> String {
        let digest = SHA256.hash(data: Data("\(passwordPepper)::\(password)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func clearProfileMirror() {
        UserDefaults.standard.removeObject(forKey: "profile_name")
        UserDefaults.standard.removeObject(forKey: "profile_note")
        UserDefaults.standard.removeObject(forKey: "profile_role")
    }

    private func loadManualAccounts() -> [ManualAccount] {
        guard
            let data = KeychainStore.read(service: keychainService, account: manualAccountsKey),
            let accounts = try? JSONDecoder().decode([ManualAccount].self, from: data)
        else { return [] }
        return accounts
    }

    private func saveManualAccounts(_ accounts: [ManualAccount]) {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        _ = KeychainStore.save(service: keychainService, account: manualAccountsKey, data: data)
    }

    private func sha256(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        result.reserveCapacity(length)
        var remaining = length
        while remaining > 0 {
            var randomBytes: [UInt8] = Array(repeating: 0, count: 16)
            let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
            if errorCode != errSecSuccess {
                return UUID().uuidString.replacingOccurrences(of: "-", with: "")
            }
            randomBytes.forEach { byte in
                if remaining == 0 { return }
                if byte < charset.count {
                    result.append(charset[Int(byte)])
                    remaining -= 1
                }
            }
        }
        return result
    }

#if canImport(FirebaseAuth)
    private func firebaseSignIn(email: String, password: String) async throws -> AuthDataResult {
        try await withCheckedThrowingContinuation { continuation in
            Auth.auth().signIn(withEmail: email, password: password) { result, error in
                if let result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: error ?? NSError(domain: "Auth", code: -1))
                }
            }
        }
    }

    private func firebaseCreateUser(email: String, password: String) async throws -> AuthDataResult {
        try await withCheckedThrowingContinuation { continuation in
            Auth.auth().createUser(withEmail: email, password: password) { result, error in
                if let result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: error ?? NSError(domain: "Auth", code: -1))
                }
            }
        }
    }

    private func firebaseSendPasswordReset(email: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Auth.auth().sendPasswordReset(withEmail: email) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func firebaseSignIn(with credential: AuthCredential) async throws -> AuthDataResult {
        try await withCheckedThrowingContinuation { continuation in
            Auth.auth().signIn(with: credential) { result, error in
                if let result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: error ?? NSError(domain: "Auth", code: -1))
                }
            }
        }
    }

    private func firebaseDeleteCurrentUser(_ user: User) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            user.delete { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
#endif
}

private enum KeychainStore {
    @discardableResult
    static func save(service: String, account: String, data: Data) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(insert as CFDictionary, nil)
        return status == errSecSuccess
    }

    static func read(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess else { return nil }
        return out as? Data
    }

    static func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

private struct AuthEntryView: View {
    private enum ManualAuthMode: String, CaseIterable, Identifiable {
        case signIn = "Giriş Yap"
        case signUp = "Üye Ol"
        var id: String { rawValue }
    }

    @EnvironmentObject private var auth: AuthSessionStore
    @State private var mode: ManualAuthMode = .signIn
    @State private var manualEmail: String = ""
    @State private var manualPassword: String = ""
    @State private var manualConfirmPassword: String = ""
    @State private var showPassword: Bool = false
    @State private var showConfirmPassword: Bool = false
    @State private var acceptedPrivacyPolicy: Bool = false
    @State private var acceptedTerms: Bool = false

    private var privacyPolicyURL: URL? {
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: "PRIVACY_POLICY_URL") as? String,
            let url = URL(string: value),
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return url
    }

    private var termsOfUseURL: URL? {
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: "TERMS_OF_USE_URL") as? String,
            let url = URL(string: value),
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return url
    }

    var body: some View {
        ZStack {
            TVTheme.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: DS.s16) {
                    TVCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(TVTheme.surface2)
                                        .frame(width: 36, height: 36)
                                    Image(systemName: "chart.line.uptrend.xyaxis")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(TVTheme.up)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("BistScreener")
                                        .font(.system(size: 28, weight: .bold))
                                        .foregroundStyle(TVTheme.text)
                                    Text("Devam etmek için giriş yap")
                                        .font(.subheadline)
                                        .foregroundStyle(TVTheme.subtext)
                                }
                            }

                            HStack(spacing: 8) {
                                ForEach(ManualAuthMode.allCases) { option in
                                    Button {
                                        withAnimation(.snappy) { mode = option }
                                    } label: {
                                        Text(option.rawValue)
                                            .font(.system(size: 16, weight: .semibold))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 10)
                                            .background(
                                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                    .fill(mode == option ? TVTheme.up.opacity(0.22) : TVTheme.surface2)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                    .stroke(mode == option ? TVTheme.up.opacity(0.7) : TVTheme.stroke, lineWidth: 1)
                                            )
                                            .foregroundStyle(mode == option ? TVTheme.up : TVTheme.text)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(4)
                            .background(TVTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                            TextField(
                                "",
                                text: $manualEmail,
                                prompt: Text("E-posta").foregroundColor(Color.white.opacity(0.45))
                            )
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(10)
                                .background(TVTheme.surface2)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .foregroundStyle(TVTheme.text)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(TVTheme.stroke, lineWidth: 1)
                                )

                            HStack(spacing: 8) {
                                Group {
                                    if showPassword {
                                        TextField(
                                            "",
                                            text: $manualPassword,
                                            prompt: Text("Şifre").foregroundColor(Color.white.opacity(0.45))
                                        )
                                            .textInputAutocapitalization(.never)
                                            .autocorrectionDisabled()
                                    } else {
                                        ZStack(alignment: .leading) {
                                            if manualPassword.isEmpty {
                                                Text("Şifre")
                                                    .foregroundStyle(Color.white.opacity(0.45))
                                            }
                                            SecureField("", text: $manualPassword)
                                                .textInputAutocapitalization(.never)
                                                .autocorrectionDisabled()
                                        }
                                    }
                                }
                                .foregroundStyle(TVTheme.text)

                                Button {
                                    showPassword.toggle()
                                } label: {
                                    Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                        .foregroundStyle(TVTheme.subtext)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(10)
                            .background(TVTheme.surface2)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(TVTheme.stroke, lineWidth: 1)
                            )

                            if mode == .signUp {
                                HStack(spacing: 8) {
                                    Group {
                                        if showConfirmPassword {
                                            TextField(
                                                "",
                                                text: $manualConfirmPassword,
                                                prompt: Text("Şifre (Tekrar)").foregroundColor(Color.white.opacity(0.45))
                                            )
                                                .textInputAutocapitalization(.never)
                                                .autocorrectionDisabled()
                                        } else {
                                            ZStack(alignment: .leading) {
                                                if manualConfirmPassword.isEmpty {
                                                    Text("Şifre (Tekrar)")
                                                        .foregroundStyle(Color.white.opacity(0.45))
                                                }
                                                SecureField("", text: $manualConfirmPassword)
                                                    .textInputAutocapitalization(.never)
                                                    .autocorrectionDisabled()
                                            }
                                        }
                                    }
                                    .foregroundStyle(TVTheme.text)

                                    Button {
                                        showConfirmPassword.toggle()
                                    } label: {
                                        Image(systemName: showConfirmPassword ? "eye.slash.fill" : "eye.fill")
                                            .foregroundStyle(TVTheme.subtext)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(10)
                                .background(TVTheme.surface2)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(TVTheme.stroke, lineWidth: 1)
                                )
                            }

                            consentToggleRow(title: "Beni Hatırla", isOn: $auth.rememberMe, link: nil)

                            consentToggleRow(
                                title: "Gizlilik Politikasını onaylıyorum",
                                isOn: $acceptedPrivacyPolicy,
                                link: privacyPolicyURL
                            )

                            consentToggleRow(
                                title: "Kullanım Koşullarını kabul ediyorum",
                                isOn: $acceptedTerms,
                                link: termsOfUseURL
                            )

                            if mode == .signIn {
                                Button {
                                    Task { await auth.requestPasswordReset(email: manualEmail) }
                                } label: {
                                    Text("Şifremi Unuttum")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(TVTheme.up)
                                }
                                .buttonStyle(.plain)
                            }

                            Button {
                                guard acceptedPrivacyPolicy && acceptedTerms else {
                                    auth.authInfoText = nil
                                    auth.authErrorText = "Devam etmek için Gizlilik Politikası ve Kullanım Koşullarını onayla."
                                    return
                                }
                                Task {
                                    if mode == .signIn {
                                        await auth.signInManual(email: manualEmail, password: manualPassword)
                                    } else {
                                        await auth.signUpManual(
                                            email: manualEmail,
                                            password: manualPassword,
                                            confirmPassword: manualConfirmPassword
                                        )
                                    }
                                }
                            } label: {
                                Text(mode == .signIn ? "Manuel Giriş" : "Üyelik Oluştur")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    LinearGradient(
                                        colors: [TVTheme.up, TVTheme.up.opacity(0.85)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .foregroundStyle(TVTheme.text)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)

                            Button {
                                auth.authInfoText = "Apple ile giriş yakında aktif edilecek."
                                auth.authErrorText = nil
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "applelogo")
                                    Text("Apple ile Giriş (Yakında)")
                                }
                                .font(.system(size: 15, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(TVTheme.surface2)
                                .foregroundStyle(TVTheme.subtext)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(TVTheme.stroke, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)

                            Button {
                                guard acceptedPrivacyPolicy && acceptedTerms else {
                                    auth.authInfoText = nil
                                    auth.authErrorText = "Google ile giriş için önce Gizlilik ve Koşulları onayla."
                                    return
                                }
                                Task { await auth.signInWithGoogle() }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "globe")
                                    Text("Google ile Giriş")
                                }
                                .font(.system(size: 15, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(TVTheme.surface2)
                                .foregroundStyle(TVTheme.text)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(TVTheme.stroke, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)

                            if let error = auth.authErrorText, !error.isEmpty {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                            if let info = auth.authInfoText, !info.isEmpty {
                                Text(info)
                                    .font(.caption)
                                    .foregroundStyle(TVTheme.up)
                            }
                        }
                    }
                }
                .padding(.horizontal, DS.s16)
                .padding(.top, 44)
            }
        }
    }

    @ViewBuilder
    private func consentToggleRow(title: String, isOn: Binding<Bool>, link: URL?) -> some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.snappy) { isOn.wrappedValue.toggle() }
            } label: {
                Image(systemName: isOn.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isOn.wrappedValue ? TVTheme.up : TVTheme.subtext)
            }
            .buttonStyle(.plain)

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(TVTheme.text)

            Spacer(minLength: 6)

            if let link {
                Link("Aç", destination: link)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(TVTheme.up)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(TVTheme.surface2.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(TVTheme.stroke, lineWidth: 1)
        )
    }
}

private enum MembershipPlan: String, CaseIterable, Identifiable {
    case monthly = "Aylık"
    case yearly = "Yıllık"
    var id: String { rawValue }
}

private struct ProfileSettingsView: View {
    @EnvironmentObject private var auth: AuthSessionStore
    @Environment(\.dismiss) private var dismiss

    @AppStorage("profile_settings_notifications_enabled") private var notificationsEnabled = true
    @AppStorage("profile_settings_trade_notifications_enabled") private var tradeNotificationsEnabled = true
    @AppStorage("profile_settings_membership_plan") private var membershipPlanRaw = MembershipPlan.monthly.rawValue

    @State private var fullName: String = ""
    @State private var showDeleteAccountConfirm = false
    @State private var isDeletingAccount = false

    private var membershipPlan: MembershipPlan {
        get { MembershipPlan(rawValue: membershipPlanRaw) ?? .monthly }
        nonmutating set { membershipPlanRaw = newValue.rawValue }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                TVTheme.bg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: DS.s12) {
                        accountCard
                        appSettingsCard
                        membershipCard
                        securityCard
                    }
                    .padding(.horizontal, DS.s16)
                    .padding(.top, DS.s12)
                    .padding(.bottom, 16)
                }
            }
            .navigationTitle("Profil Ayarları")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kapat") { dismiss() }
                        .foregroundStyle(TVTheme.up)
                }
            }
            .onAppear {
                fullName = auth.currentUser?.fullName ?? ""
            }
            .confirmationDialog(
                "Hesabı kalıcı olarak silmek istediğine emin misin?",
                isPresented: $showDeleteAccountConfirm,
                titleVisibility: .visible
            ) {
                Button("Kalıcı Olarak Sil", role: .destructive) {
                    isDeletingAccount = true
                    Task {
                        await auth.deleteCurrentAccount()
                        isDeletingAccount = false
                        dismiss()
                    }
                }
                Button("Vazgeç", role: .cancel) { }
            } message: {
                Text("Bu işlem geri alınamaz.")
            }
            .tvNavStyle()
        }
    }

    private var accountCard: some View {
        TVCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Profil Ayarı")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(TVTheme.text)
                    Spacer()
                    TVChip("Hesap", systemImage: "person.crop.circle")
                }

                TextField("Ad Soyad", text: $fullName)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(TVTheme.surface2)
                    .foregroundStyle(TVTheme.text)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(TVTheme.stroke, lineWidth: 1)
                    )

                if let email = auth.currentUser?.email, !email.isEmpty {
                    Text(email)
                        .font(.footnote)
                        .foregroundStyle(TVTheme.subtext)
                }

                Button {
                    auth.updateDisplayName(fullName)
                } label: {
                    Text("Profili Güncelle")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(TVTheme.text)
                        .background(TVTheme.surface2)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(TVTheme.stroke, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var appSettingsCard: some View {
        TVCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Uygulama Ayarları")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(TVTheme.text)
                    Spacer()
                    TVChip("Uygulama", systemImage: "gearshape")
                }

                Toggle("Uygulama Bildirimleri", isOn: $notificationsEnabled)
                    .tint(TVTheme.up)
                    .onChangeCompat(of: notificationsEnabled) { enabled in
                        guard enabled else { return }
                        StrategyNotificationManager.shared.requestAuthorizationIfNeeded()
                    }

                Toggle("Alım/Satım Onay Bildirimleri", isOn: $tradeNotificationsEnabled)
                    .tint(TVTheme.up)
                    .disabled(!notificationsEnabled)

                Text("Bildirimler sistem ayarlarına bağlıdır. İzin kapalıysa iOS Ayarlar'dan açman gerekir.")
                    .font(.footnote)
                    .foregroundStyle(TVTheme.subtext)
            }
        }
    }

    private var membershipCard: some View {
        TVCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Üyelik")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(TVTheme.text)
                    Spacer()
                    TVChip(membershipPlan.rawValue, systemImage: "creditcard")
                }

                HStack(spacing: 8) {
                    ForEach(MembershipPlan.allCases) { plan in
                        Button {
                            withAnimation(.snappy) { membershipPlan = plan }
                        } label: {
                            Text(plan.rawValue)
                                .font(.system(size: 14, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(membershipPlan == plan ? TVTheme.up.opacity(0.22) : TVTheme.surface2)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(membershipPlan == plan ? TVTheme.up.opacity(0.75) : TVTheme.stroke, lineWidth: 1)
                                )
                                .foregroundStyle(membershipPlan == plan ? TVTheme.up : TVTheme.text)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("Aylık/Yıllık paket seçimi kaydedildi. Satın alma akışı bir sonraki güncellemede açılacak.")
                    .font(.footnote)
                    .foregroundStyle(TVTheme.subtext)
            }
        }
    }

    private var securityCard: some View {
        TVCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Hesabı Yönet")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(TVTheme.text)
                    Spacer()
                    TVChip("Güvenlik", systemImage: "lock.shield")
                }

                Button {
                    guard let email = auth.currentUser?.email, !email.isEmpty else {
                        auth.authErrorText = "Şifre sıfırlamak için giriş e-postası bulunamadı."
                        return
                    }
                    Task { await auth.requestPasswordReset(email: email) }
                } label: {
                    actionRow(title: "Şifre Sıfırla", icon: "envelope.badge")
                }
                .buttonStyle(.plain)

                Button {
                    auth.signOut()
                    dismiss()
                } label: {
                    actionRow(title: "Çıkış Yap", icon: "rectangle.portrait.and.arrow.right")
                }
                .buttonStyle(.plain)

                Button(role: .destructive) {
                    showDeleteAccountConfirm = true
                } label: {
                    actionRow(title: "Hesabı Sil", icon: "trash", danger: true)
                }
                .buttonStyle(.plain)
                .disabled(isDeletingAccount || auth.currentUser == nil)

                if isDeletingAccount {
                    ProgressView().tint(.white)
                }
            }
        }
    }

    private func actionRow(title: String, icon: String, danger: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(TVTheme.subtext)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(TVTheme.surface2)
        .foregroundStyle(danger ? Color.orange : TVTheme.text)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(TVTheme.stroke, lineWidth: 1)
        )
    }
}

private extension UIApplication {
    func topMostViewController(
        base: UIViewController? = nil
    ) -> UIViewController? {
        let start: UIViewController? = {
            if let base { return base }
            let scenes = connectedScenes.compactMap { $0 as? UIWindowScene }
            return scenes
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)?
                .rootViewController
        }()

        if let nav = start as? UINavigationController {
            return topMostViewController(base: nav.visibleViewController)
        }
        if let tab = start as? UITabBarController {
            return topMostViewController(base: tab.selectedViewController)
        }
        if let presented = start?.presentedViewController {
            return topMostViewController(base: presented)
        }
        return start
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

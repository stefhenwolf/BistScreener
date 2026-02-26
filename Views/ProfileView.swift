import SwiftUI

enum ProfileNavRoute: Hashable {
    case assets
    case strategy
}

struct ProfileView: View {
    @Binding var selectedTab: AppTab

    @EnvironmentObject private var portfolioVM: PortfolioViewModel
    @EnvironmentObject private var strategyStore: LiveStrategyStore
    @EnvironmentObject private var auth: AuthSessionStore
    @State private var showDeleteAccountConfirm = false
    @State private var showClearDeviceDataConfirm = false
    @State private var isDeletingAccount = false

    var body: some View {
        ZStack {
            TVTheme.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: DS.s16) {

                    profileCard
                    authCard
                    portfolioSummaryCard
                    strategySummaryCard

                    Spacer(minLength: 12)
                }
                .padding(.horizontal, DS.s16)
                .padding(.top, DS.s12)
                .padding(.bottom, 16)
            }
        }
        .navigationTitle("Profil")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { portfolioVM.loadFromDiskAndRefresh() }
        // ✅ Pull-to-refresh kapalı
        .tvNavStyle()

        // ✅ En stabil push
        .navigationDestination(for: ProfileNavRoute.self) { route in
            switch route {
            case .assets:
                AssetsTabRoot()
            case .strategy:
                StrategyView(selectedTab: $selectedTab)
            }
        }
    }

    // MARK: - Cards

    private var profileCard: some View {
        TVCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Profil")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(TVTheme.text)
                    Spacer()
                    TVChip(role, systemImage: "stethoscope")
                }

                Text(name)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(TVTheme.text)

                Text(note)
                    .font(.footnote)
                    .foregroundStyle(TVTheme.subtext)
            }
        }
    }

    private var authCard: some View {
        TVCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Giriş Bilgileri")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(TVTheme.text)
                    Spacer()
                    TVChip(providerText, systemImage: "lock.shield")
                }

                if let user = auth.currentUser {
                    if !user.email.isEmpty {
                        Text(user.email)
                            .font(.subheadline)
                            .foregroundStyle(TVTheme.subtext)
                    }
                    Text("Giriş zamanı: \(user.signedInAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(TVTheme.subtext)
                } else {
                    Text("Aktif oturum yok.")
                        .font(.subheadline)
                        .foregroundStyle(TVTheme.subtext)
                }

                Button {
                    auth.signOut()
                    selectedTab = .home
                } label: {
                    Text("Çıkış Yap")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(TVTheme.surface2)
                        .foregroundStyle(TVTheme.text)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                HStack(spacing: 8) {
                    Button {
                        showDeleteAccountConfirm = true
                    } label: {
                        Text("Hesabı Sil")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(TVTheme.surface2)
                            .foregroundStyle(.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .disabled(isDeletingAccount || auth.currentUser == nil)

                    Button {
                        showClearDeviceDataConfirm = true
                    } label: {
                        Text("Cihaz Verisini Temizle")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(TVTheme.surface2)
                            .foregroundStyle(TVTheme.text)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .disabled(isDeletingAccount)
                }

                if isDeletingAccount {
                    ProgressView()
                        .tint(.white)
                }
            }
        }
        .confirmationDialog("Hesabı kalıcı olarak silmek istediğine emin misin?", isPresented: $showDeleteAccountConfirm, titleVisibility: .visible) {
            Button("Kalıcı Olarak Sil", role: .destructive) {
                isDeletingAccount = true
                Task {
                    await auth.deleteCurrentAccount()
                    isDeletingAccount = false
                    selectedTab = .home
                }
            }
            Button("Vazgeç", role: .cancel) { }
        } message: {
            Text("Bu işlem geri alınamaz. Strateji ve profil oturumu cihazda sonlandırılır.")
        }
        .confirmationDialog("Cihazdaki kimlik verileri temizlensin mi?", isPresented: $showClearDeviceDataConfirm, titleVisibility: .visible) {
            Button("Temizle", role: .destructive) {
                auth.clearAllLocalUserData()
                selectedTab = .home
            }
            Button("Vazgeç", role: .cancel) { }
        } message: {
            Text("Bu işlem bu cihazdaki oturum ve kayıtlı giriş verilerini siler.")
        }
    }

    private var providerText: String {
        guard let provider = auth.currentUser?.provider else { return "—" }
        switch provider {
        case "apple": return "Apple ID"
        case "google": return "Google"
        case "manual": return "Manuel"
        default: return provider
        }
    }

    private var name: String {
        let raw = auth.currentUser?.fullName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? "Profil" : raw
    }

    private var role: String {
        providerText == "—" ? "Misafir" : providerText
    }

    private var note: String {
        let email = auth.currentUser?.email.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return email.isEmpty ? "Kişisel not…" : email
    }

    private var portfolioSummaryCard: some View {
        TVCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Portföy Özeti")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(TVTheme.text)
                    Spacer()
                    NavigationLink(value: ProfileNavRoute.assets) {
                        TVChip("Detay", systemImage: "arrow.right")
                    }
                    .buttonStyle(.plain)
                }

                let total = portfolioVM.totalTRY
                let pnl = portfolioVM.rows.compactMap(\.pnlTRY).reduce(0, +)

                Text(total.formatted(.currency(code: "TRY")))
                    .font(.title2.bold())
                    .foregroundStyle(TVTheme.text)

                HStack(spacing: 8) {
                    Text("Toplam K/Z:")
                        .font(.subheadline)
                        .foregroundStyle(TVTheme.subtext)

                    Text(pnl.formatted(.currency(code: "TRY")))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(pnl >= 0 ? TVTheme.up : TVTheme.down)
                }

                HStack(spacing: 10) {
                    if portfolioVM.isLoading {
                        ProgressView().scaleEffect(0.9)
                        Text("Güncelleniyor…")
                            .font(.caption)
                            .foregroundStyle(TVTheme.subtext)
                    } else if let e = portfolioVM.errorText {
                        Text(e).font(.caption).foregroundStyle(.red)
                    } else if let d = portfolioVM.lastUpdated {
                        Text("Güncelleme: \(d.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(TVTheme.subtext)
                    } else {
                        Text("—")
                            .font(.caption)
                            .foregroundStyle(TVTheme.subtext)
                    }

                    Spacer()
                }
            }
        }
    }

    private var strategySummaryCard: some View {
        TVCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Strateji Özeti")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(TVTheme.text)
                    Spacer()
                    NavigationLink(value: ProfileNavRoute.strategy) {
                        TVChip("Detay", systemImage: "arrow.right")
                    }
                    .buttonStyle(.plain)
                }

                if strategyStore.isRunning {
                    let total = strategyStore.totalValueTL
                    let pnl = strategyStore.totalReturnTL

                    Text(total.formatted(.currency(code: "TRY")))
                        .font(.title2.bold())
                        .foregroundStyle(TVTheme.text)

                    HStack(spacing: 8) {
                        Text("Toplam K/Z:")
                            .font(.subheadline)
                            .foregroundStyle(TVTheme.subtext)

                        Text(pnl.formatted(.currency(code: "TRY")))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(pnl >= 0 ? TVTheme.up : TVTheme.down)
                    }
                } else {
                    Text("Strateji pasif")
                        .font(.title3.bold())
                        .foregroundStyle(TVTheme.subtext)
                    Text("Başlatmak için Detay'a dokun.")
                        .font(.subheadline)
                        .foregroundStyle(TVTheme.subtext)
                }

                HStack(spacing: 10) {
                    if strategyStore.isRefreshing {
                        ProgressView().scaleEffect(0.9).tint(.white)
                        Text("Güncelleniyor…")
                            .font(.caption)
                            .foregroundStyle(TVTheme.subtext)
                    } else if let d = strategyStore.lastUpdated {
                        Text("Güncelleme: \(d.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(TVTheme.subtext)
                    } else {
                        Text("—")
                            .font(.caption)
                            .foregroundStyle(TVTheme.subtext)
                    }

                    Spacer()
                }
            }
        }
    }
}

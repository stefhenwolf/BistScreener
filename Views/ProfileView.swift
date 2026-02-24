import SwiftUI

enum ProfileNavRoute: Hashable {
    case assets
    case strategy
}

struct ProfileView: View {
    @Binding var selectedTab: AppTab

    @AppStorage("profile_name") private var name: String = "Sedat"
    @AppStorage("profile_role") private var role: String = "Doktor"
    @AppStorage("profile_note") private var note: String = "Kişisel not…"

    @EnvironmentObject private var portfolioVM: PortfolioViewModel
    @EnvironmentObject private var strategyStore: LiveStrategyStore

    var body: some View {
        ZStack {
            TVTheme.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: DS.s16) {

                    profileCard
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

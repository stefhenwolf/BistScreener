import SwiftUI

struct ProfileView: View {
    @Binding var selectedTab: AppTab

    @AppStorage("profile_name") private var name: String = "Sedat"
    @AppStorage("profile_role") private var role: String = "Doktor"
    @AppStorage("profile_note") private var note: String = "Kişisel not…"

    @StateObject private var portfolioVM = PortfolioViewModel()
    @State private var goAssets: Bool = false

    var body: some View {
        ZStack {
            TVTheme.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: DS.s16) {

                    profileCard
                    portfolioCard
                    assetsEntryCard

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
        .navigationDestination(isPresented: $goAssets) {
            AssetsTabRoot()
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

    private var portfolioCard: some View {
        TVCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Portföy")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(TVTheme.text)
                    Spacer()
                    Button {
                        goAssets = true
                    } label: {
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

                    .disabled(portfolioVM.isLoading)
                }
            }
        }
    }

    private var assetsEntryCard: some View {
        Button {
            goAssets = true
        } label: {
            
        }
        .buttonStyle(.plain)
    }
}

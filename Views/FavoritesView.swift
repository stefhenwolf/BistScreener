//
//  FavoritesView.swift
//  BistScreener
//
//  Created by Sedat Pala on 18.02.2026.
//  Pro UI + Haptics update
//

import SwiftUI
import UIKit

struct FavoritesView: View {
    @EnvironmentObject private var watchlist: WatchlistStore
    @StateObject private var vm = FavoritesViewModel()

    @State private var showAddSheet = false

    // Kart kendi padding'ini taşıdığından yalnızca yatay boşluk + ince dikey aralık
    private let rowInsets = EdgeInsets(top: 5, leading: DS.s16, bottom: 5, trailing: DS.s16)

    var body: some View {
        VStack(spacing: DS.s12) {

            headerCard
                .padding(.horizontal, DS.s16)
                .padding(.top, DS.s12)

            if vm.isLoading {
                loadingCard
                    .padding(.horizontal, DS.s16)
            } else if let e = vm.errorText, !e.isEmpty {
                errorCard(e)
                    .padding(.horizontal, DS.s16)
            }

            // ✅ List tam geniş kalsın (padding yok)
            listBody
        }
        .navigationTitle("Favoriler")
        .navigationBarTitleDisplayMode(.inline)
        // ✅ Otomatik network güncellemesi yok.
        // Favoriler yalnızca "Güncelle" butonu veya pull-to-refresh ile yenilenir.
        .onAppear {
            vm.setSymbols(watchlist.symbols)
        }
        .onChangeCompat(of: watchlist.symbols) { new in
            withAnimation(.snappy) {
                vm.setSymbols(new)
            }
        }
        .refreshable {
            Haptics.light()
            vm.refresh(symbols: watchlist.symbols)
        }
        .sheet(isPresented: $showAddSheet) {
            AddFavoriteSheet {
                withAnimation(.snappy) {
                    // ✅ Ekleme sonrası da otomatik fetch yok; sadece listeyi senkronla.
                    vm.setSymbols(watchlist.symbols)
                }
            }
            .environmentObject(watchlist)
        }
        .navigationDestination(for: StockDetailRoute.self) { route in
            StockDetailView(route: route)
        }
        .animation(.snappy, value: vm.rows.count)
        
        .tvBackground()
        .tvNavStyle() 
    }

    // MARK: - Header

    private var headerCard: some View {
        TVCard {
            VStack(alignment: .leading, spacing: DS.s12) {
                HStack {
                    Text("Takip Listen")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(TVTheme.text)

                    Spacer()
                    TVChip("\(watchlist.symbols.count)/100", systemImage: "star.fill")
                }

                HStack(spacing: 10) {
                    Button {
                        Haptics.light()
                        withAnimation(.snappy) { vm.refresh(symbols: watchlist.symbols) }
                    } label: {
                        TVChip("Güncelle", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .disabled(vm.isLoading)

                    Button {
                        Haptics.light()
                        showAddSheet = true
                    } label: {
                        TVChip("Ekle", systemImage: "plus")
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    if vm.isLoading {
                        TVChip("Yükleniyor", systemImage: "hourglass")
                    } else {
                        TVChip("\(vm.rows.count) satır", systemImage: "list.bullet")
                    }
                }

                if watchlist.symbols.isEmpty {
                    Text("Favori ekleyerek hisseleri hızlı takip edebilirsin.")
                        .font(.subheadline)
                        .foregroundStyle(TVTheme.subtext)
                }
            }
        }
    }

    private var loadingCard: some View {
        TVCard {
            HStack(spacing: 10) {
                ProgressView().scaleEffect(0.95)
                    .tint(TVTheme.text)
                Text("Veriler çekiliyor…")
                    .font(.subheadline)
                    .foregroundStyle(TVTheme.subtext)
                Spacer()
            }
        }
    }

    private func errorCard(_ text: String) -> some View {
        TVCard {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(TVTheme.down)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(TVTheme.subtext)
                    .lineLimit(2)

                Spacer()

                Button {
                    Haptics.light()
                    withAnimation(.snappy) {
                        vm.refresh(symbols: watchlist.symbols)
                    }
                } label: {
                    TVChip("Tekrar", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - List

    private var listBody: some View {
        if watchlist.symbols.isEmpty {
            return AnyView(
                emptyState
                    .padding(.horizontal, DS.s16) // ✅ empty state kartı padding’li kalsın
            )
        }

        return AnyView(
            List {
                ForEach(vm.rows) { r in
                    NavigationLink(value: StockDetailRoute.live(symbol: r.symbol)) {
                        FavoriteRowPro(r: r)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .listRowInsets(rowInsets)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Haptics.warning()
                            withAnimation(.snappy) {
                                watchlist.remove(r.symbol)
                                vm.refresh(symbols: watchlist.symbols)
                            }
                        } label: {
                            Label("Sil", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.plain)                 // ✅ insetGrouped yerine
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        )
    }

    private var emptyState: some View {
        TVCard {
            VStack(spacing: 12) {
                Image(systemName: "star.slash")
                    .font(.system(size: 34))
                    .foregroundStyle(TVTheme.subtext)

                Text("Henüz favori yok")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(TVTheme.text)

                Text("Ekle butonuyla favori listeni olustur.")
                    .font(.footnote)
                    .foregroundStyle(TVTheme.subtext)
                    .multilineTextAlignment(.center)

                Button {
                    Haptics.light()
                    showAddSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                        Text("Favori Ekle")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(TVTheme.up)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Pro Row

private struct FavoriteRowPro: View {
    let r: FavoriteRow

    private var priceText: String {
        if let p = r.lastClose { return String(format: "%.2f ₺", p) }
        return "—"
    }

    private var changeText: String {
        if let ch = r.changePct { return String(format: "%+.2f%%", ch) }
        return "—"
    }

    private var dateText: String {
        if let d = r.lastDate { return d.formatted(date: .abbreviated, time: .omitted) }
        return "Veri yok"
    }

    private var changeColor: Color {
        guard let ch = r.changePct else { return TVTheme.subtext }
        return ch >= 0 ? TVTheme.up : TVTheme.down
    }

    private var changeIcon: String {
        guard let ch = r.changePct else { return "minus" }
        return ch >= 0 ? "arrow.up.right" : "arrow.down.right"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // ── Satır 1: Sembol + Fiyat
            HStack(alignment: .center) {
                Text(r.symbol)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(TVTheme.text)

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(priceText)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(TVTheme.text)

                    HStack(spacing: 4) {
                        Image(systemName: changeIcon)
                            .font(.system(size: 10, weight: .bold))
                        Text(changeText)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(changeColor)
                }
            }

            // ── Satır 2: Tarih + Durum
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11))
                    Text(dateText)
                        .font(.system(size: 12))
                }
                .foregroundStyle(TVTheme.subtext)

                Spacer()

                if r.lastDate == nil {
                    TVChip("Veri yok", systemImage: "wifi.exclamationmark")
                } else if let ch = r.changePct {
                    // Küçük değişim bar
                    let pct = min(max(ch, -10), 10) / 10.0   // -1 … 1
                    let w: CGFloat = 48
                    let fill = ch >= 0 ? TVTheme.up : TVTheme.down
                    ZStack(alignment: ch >= 0 ? .leading : .trailing) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(TVTheme.surface2)
                            .frame(width: w, height: 6)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(fill.opacity(0.7))
                            .frame(width: max(4, w * CGFloat(abs(pct))), height: 6)
                    }
                }
            }
        }
        .padding(14)
        .background(TVTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(TVTheme.stroke, lineWidth: 1)
        )
    }
}

// MARK: - Add Sheet (Validate + Add) + Haptics

struct AddFavoriteSheet: View {
    @EnvironmentObject private var watchlist: WatchlistStore
    @Environment(\.dismiss) private var dismiss

    @State private var symbol = ""
    @State private var alert: AlertInfo?
    @State private var isValidating = false
    @FocusState private var focused: Bool

    private let yahoo = YahooFinanceService()
    let onAdded: () -> Void

    struct AlertInfo: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: DS.s12) {

                AppCard {
                    VStack(alignment: .leading, spacing: DS.s12) {
                        HStack {
                            Text("Hisse Sembolü")
                                .font(.headline)
                            Spacer()
                            Chip(text: "\(watchlist.symbols.count)/100", systemImage: "star.fill")
                        }

                        TextField("Örn: THYAO veya THYAO.IS", text: $symbol)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.asciiCapable)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .focused($focused)

                        Text("THYAO yazarsan otomatik THYAO.IS olur. Yanlış sembol eklenmez.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, DS.s16)

                Spacer(minLength: 0)
            }
            .navigationTitle("Hisse Ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Kapat") { dismiss() }
                        .disabled(isValidating)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    focused = false
                    validateAndAdd()
                } label: {
                    if isValidating {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Kontrol ediliyor…")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .font(.headline)
                    } else {
                        Text("Ekle")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .font(.headline)
                    }
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, DS.s16)
                .padding(.bottom, 10)
                .disabled(isValidating || symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .alert(item: $alert) { a in
                Alert(title: Text(a.title), message: Text(a.message), dismissButton: .default(Text("Tamam")))
            }
            .onAppear { focused = true }
            .appScreenBackground()
        }
        .presentationDetents([.medium])
        .appScreenBackground()
    }

    private func validateAndAdd() {
        let sym = symbol.normalizedBISTSymbol()
        guard !sym.isEmpty else {
            Haptics.error()
            alert = .init(title: "Geçersiz sembol", message: "Boş/yanlış sembol girdin.")
            return
        }

        isValidating = true
        Haptics.light()

        Task {
            do {
                let candles = try await yahoo.fetchDailyCandles(symbol: sym, range: "1mo")

                guard !candles.isEmpty else {
                    await MainActor.run {
                        self.isValidating = false
                        Haptics.warning()
                        self.alert = .init(title: "Hatalı hisse", message: "\(sym) için veri bulunamadı. Sembol yanlış olabilir.")
                    }
                    return
                }

                let result = await MainActor.run { watchlist.add(sym) }

                await MainActor.run {
                    self.isValidating = false

                    switch result {
                    case .added:
                        Haptics.success()
                        withAnimation(.snappy) {
                            self.onAdded()
                        }
                        self.dismiss()

                    case .duplicate:
                        Haptics.warning()
                        self.alert = .init(title: "Zaten var", message: "Bu hisse zaten favorilerinde.")

                    case .full:
                        Haptics.error()
                        self.alert = .init(title: "Limit dolu", message: "Favoriler en fazla 100 hisse tutabilir.")

                    case .invalid:
                        Haptics.error()
                        self.alert = .init(title: "Geçersiz sembol", message: "Boş/yanlış sembol girdin.")
                    }
                }

            } catch {
                await MainActor.run {
                    self.isValidating = false
                    Haptics.error()
                    self.alert = .init(
                        title: "Hatalı hisse / veri çekilemedi",
                        message: "\(sym) doğrulanamadı. Sembol yanlış olabilir veya bağlantı sorunu var.\n\nDetay: \(error.localizedDescription)"
                    )
                }
            }
        }
    }
}

// MARK: - Haptics

@MainActor
private enum Haptics {
    static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}

import SwiftUI
import Charts

struct AssetsView: View {
    @EnvironmentObject private var vm: PortfolioViewModel

    @State private var showSheet = false
    @State private var editing: Asset? = nil
    @State private var pendingDelete: (offsets: IndexSet, sectionRows: [PortfolioRow])?
    @State private var pendingDeleteName: String = ""
    @State private var showDeleteConfirm = false
    @State private var isRefreshing = false

    // ✅ Donut seçimi
    @State private var selectedAngle: Double? = nil
    @State private var selectedType: AssetType? = nil

    private let rowInsets = EdgeInsets(top: 5, leading: DS.s16, bottom: 5, trailing: DS.s16)

    var body: some View {
        List {
            Section {
                summaryCardRow
                allocationPieRow
            }

            if vm.isLoading {
                HStack { Spacer(); ProgressView().tint(.white); Spacer() }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if let e = vm.errorText {
                Text(e)
                    .foregroundStyle(TVTheme.down)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if vm.rows.isEmpty && !vm.isLoading {
                emptyStateRow
            } else {
                ForEach(AssetType.allCases, id: \.self) { t in
                    let sectionRows = rows(for: t)
                    if !sectionRows.isEmpty {
                        Section {
                            sectionHeader(type: t, rows: sectionRows)
                                .listRowInsets(EdgeInsets(top: 8, leading: DS.s16, bottom: 4, trailing: DS.s16))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)

                            ForEach(Array(sectionRows.enumerated()), id: \.element.id) { idx, r in
                                rowCell(idx: idx, r: r, sectionRows: sectionRows)
                                    .listRowInsets(rowInsets)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                            }
                            // ✅ tvOS'ta .onDelete / swipe yok
                            #if !os(tvOS)
                            .onDelete { offsets in
                                requestDelete(offsets: offsets, within: sectionRows)
                            }
                            #endif
                        }
                    }
                }
            }
        }
        .confirmationDialog(
            pendingDeleteName.isEmpty
                ? "Varlığı portföyden kaldır?"
                : "\(pendingDeleteName) varlığını portföyden kaldır?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Sil", role: .destructive) {
                if let p = pendingDelete {
                    delete(offsets: p.offsets, within: p.sectionRows)
                    pendingDelete = nil
                    pendingDeleteName = ""
                }
            }
            Button("Vazgeç", role: .cancel) {
                pendingDelete = nil
                pendingDeleteName = ""
            }
        } message: {
            Text("Bu işlem geri alınamaz.")
        }
        .listStyle(.plain)
        .tint(.white)
        .navigationTitle("Varlıklarım")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editing = nil
                    showSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
#if !os(tvOS)
        .refreshable {
            await refreshAssetsData()
        }
#endif
        .task {
            vm.loadFromDiskAndRefresh()
        }
        .sheet(isPresented: $showSheet) {
            AddEditAssetSheet(asset: editing) { a in
                vm.upsert(a)
                vm.refreshPrices()
            } onDelete: { a in
                vm.deleteBySymbols([a.symbol])
                vm.refreshPrices()
            } onSell: { a, qty in
                vm.sellAsset(type: a.type, symbol: a.symbol, quantity: qty)
            }
            .scrollContentBackground(.hidden)
            .tvBackground()
        }
        .navigationDestination(for: StockDetailRoute.self) { route in
            StockDetailView(route: route)
        }
        #if !os(tvOS)
        .scrollContentBackground(.hidden)
        #endif
        .tvBackground()
        .tvNavStyle()
    }

    // MARK: - Row Cell (iOS vs tvOS)

    @ViewBuilder
    private func rowCell(idx: Int, r: PortfolioRow, sectionRows: [PortfolioRow]) -> some View {
        #if os(tvOS)
        // ✅ tvOS: Focus ile gezilebilir satır + sağda aksiyonlar
        HStack(alignment: .top, spacing: 12) {
            if let route = detailRoute(for: r.asset) {
                NavigationLink(value: route) {
                    rowView(r)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    editing = r.asset
                    showSheet = true
                } label: {
                    rowView(r)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 10) {
                Button {
                    requestDelete(offsets: IndexSet(integer: idx), within: sectionRows)
                } label: {
                    Label("Sil", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 4)

        #else
        // ✅ iOS: Kart tam genişlik + tüm aksiyonlar swipe içinde
        Group {
            if let route = detailRoute(for: r.asset) {
                NavigationLink(value: route) {
                    rowView(r)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    editing = r.asset
                    showSheet = true
                } label: {
                    rowView(r)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                editing = r.asset
                showSheet = true
            } label: {
                Label("Düzenle", systemImage: "pencil")
            }
            .tint(TVTheme.surface2)

            Button(role: .destructive) {
                requestDelete(offsets: IndexSet(integer: idx), within: sectionRows)
            } label: {
                Label("Sil", systemImage: "trash")
            }
            .tint(.red)
        }
        #endif
    }

    // MARK: - Summary Card Row

    private var summaryCardRow: some View {
        let totalPnL = vm.rows.compactMap(\.pnlTRY).reduce(0, +)
        let dayPnL = vm.rows.compactMap(\.dayPnlTRY).reduce(0, +)

        return VStack(alignment: .leading, spacing: 8) {
            Text("Toplam Portföy (TRY)")
                .font(.headline)
                .foregroundStyle(TVTheme.text)

            HStack(alignment: .firstTextBaseline) {
                Text("₺ " + fmtMoney(vm.totalTRY))
                    .font(.title2)
                    .bold()
                    .foregroundStyle(TVTheme.text)

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Günlük K/Z")
                            .font(.caption)
                            .foregroundStyle(TVTheme.subtext)

                        Text("₺ " + fmtMoney(dayPnL))
                            .font(.subheadline)
                            .bold()
                            .foregroundStyle(dayPnL >= 0 ? TVTheme.up : TVTheme.down)
                    }

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Toplam K/Z")
                            .font(.caption)
                            .foregroundStyle(TVTheme.subtext)

                        Text("₺ " + fmtMoney(totalPnL))
                            .font(.subheadline)
                            .bold()
                            .foregroundStyle(totalPnL >= 0 ? TVTheme.up : TVTheme.down)
                    }
                }
            }

            if let t = vm.lastUpdated {
                Text("Güncelleme: \(t.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(TVTheme.subtext)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TVTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(TVTheme.stroke, lineWidth: 1)
        )
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    // MARK: - Donut / Pie Row

    private var allocationPieRow: some View {
        let alloc = allocationByType()
        let total = vm.totalTRY

        let slices: [(type: AssetType, value: Double)] =
        AssetType.allCases
            .map { ($0, alloc[$0] ?? 0) }
            .filter { $0.1 > 0.0001 }

        let selectedValue: Double? = {
            guard let st = selectedType else { return nil }
            return slices.first(where: { $0.type == st })?.value
        }()

        let selectedPct: Double? = {
            guard let v = selectedValue, total > 0 else { return nil }
            return (v / total) * 100.0
        }()

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Dağılım")
                    .font(.headline)
                    .foregroundStyle(TVTheme.text)

                Spacer()

                if selectedType != nil {
                    Button("Seçimi temizle") {
                        selectedType = nil
                        selectedAngle = nil
                    }
                    .font(.caption)
                    .foregroundStyle(TVTheme.text)
                }
            }

            if slices.isEmpty || total <= 0 {
                Text("Henüz değer hesaplanacak varlık yok.")
                    .font(.caption)
                    .foregroundStyle(TVTheme.subtext)
            } else {
                if #available(iOS 17.0, tvOS 17.0, *) {
                    ZStack {
                        Chart {
                            ForEach(slices, id: \.type) { s in
                                SectorMark(
                                    angle: .value("Değer", s.value),
                                    innerRadius: .ratio(0.62),
                                    angularInset: 2
                                )
                                .foregroundStyle(colorForType(s.type))
                                .opacity(selectedType == nil || selectedType == s.type ? 1.0 : 0.25)
                            }
                        }
                        .frame(height: 260)

                        #if !os(tvOS)
                        .chartAngleSelection(value: $selectedAngle)
                        .onChangeCompat(of: selectedAngle) { newAngle in
                            selectedType = typeForAngle(newAngle, slices: slices)
                        }
                        #endif

                        VStack(spacing: 4) {
                            if let st = selectedType,
                               let v = selectedValue,
                               let p = selectedPct {
                                Text(st.title)
                                    .font(.caption)
                                    .foregroundStyle(TVTheme.subtext)

                                Text("₺ " + fmtMoney(v))
                                    .font(.title3)
                                    .bold()
                                    .foregroundStyle(TVTheme.text)

                                Text("%" + fmtPct(p))
                                    .font(.caption)
                                    .foregroundStyle(TVTheme.subtext)
                            } else {
                                Text("Toplam")
                                    .font(.caption)
                                    .foregroundStyle(TVTheme.subtext)

                                Text("₺ " + fmtMoney(total))
                                    .font(.title3)
                                    .bold()
                                    .foregroundStyle(TVTheme.text)

                                #if os(tvOS)
                                Text("Legend’den seç")
                                    .font(.caption)
                                    .foregroundStyle(TVTheme.subtext)
                                #else
                                Text("Pastaya dokun")
                                    .font(.caption)
                                    .foregroundStyle(TVTheme.subtext)
                                #endif
                            }
                        }
                        .padding(.horizontal, 10)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(slices, id: \.type) { s in
                            let pct = max(0, min(1, s.value / total))
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(s.type.title)
                                    Spacer()
                                    Text("%" + fmtPct(pct * 100))
                                        .font(.caption)
                                        .foregroundStyle(TVTheme.subtext)
                                }
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(TVTheme.surface2)
                                        Capsule()
                                            .fill(TVTheme.accent)
                                            .frame(width: max(4, geo.size.width * pct))
                                    }
                                }
                                .frame(height: 8)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }

                // ✅ Legend: iOS tap / tvOS focus-button
                VStack(spacing: 8) {
                    ForEach(slices, id: \.type) { s in
                        let pct = (s.value / total) * 100.0

                        #if os(tvOS)
                        Button {
                            if selectedType == s.type {
                                selectedType = nil
                                selectedAngle = nil
                            } else {
                                selectedType = s.type
                                selectedAngle = nil
                            }
                        } label: {
                                HStack {
                                    Circle()
                                        .fill(colorForType(s.type))
                                        .frame(width: 9, height: 9)

                                    Text(s.type.title)
                                        .foregroundStyle(TVTheme.text)
                                        .fontWeight(selectedType == s.type ? .bold : .regular)

                                    Spacer()

                                    Text("%" + fmtPct(pct))
                                        .font(.caption)
                                        .foregroundStyle(TVTheme.subtext)

                                    Text("₺ " + fmtMoney(s.value))
                                        .bold()
                                        .foregroundStyle(TVTheme.text)
                                }
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        #else
                        HStack {
                            Circle()
                                .fill(colorForType(s.type))
                                .frame(width: 9, height: 9)

                            Text(s.type.title)
                                .foregroundStyle(TVTheme.text)
                                .fontWeight(selectedType == s.type ? .bold : .regular)

                            Spacer()

                            Text("%" + fmtPct(pct))
                                .font(.caption)
                                .foregroundStyle(TVTheme.subtext)

                            Text("₺ " + fmtMoney(s.value))
                                .bold()
                                .foregroundStyle(TVTheme.text)
                        }
                        .font(.subheadline)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectedType == s.type {
                                selectedType = nil
                                selectedAngle = nil
                            } else {
                                selectedType = s.type
                                selectedAngle = nil
                            }
                        }
                        #endif
                    }
                }

                Text("Not: TRY hesaplanamayan satırlar dağılıma dahil edilmez.")
                    .font(.caption2)
                    .foregroundStyle(TVTheme.subtext)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TVTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(TVTheme.stroke, lineWidth: 1)
        )
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 10, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    // MARK: - Empty State Row

    private var emptyStateRow: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 34))
                .foregroundStyle(TVTheme.subtext)
            Text("Henüz varlık yok")
                .font(.headline)
                .foregroundStyle(TVTheme.text)
            Text("Sağ üstten + ile ekleyebilirsin.")
                .font(.footnote)
                .foregroundStyle(TVTheme.subtext)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // MARK: - Section helpers

    private func rows(for type: AssetType) -> [PortfolioRow] {
        vm.rows.filter { $0.asset.type == type }
    }

    private func sectionHeader(type: AssetType, rows: [PortfolioRow]) -> some View {
        let sum = rows.compactMap(\.valueTRY).reduce(0, +)
        return HStack {
            Text(type.title)
                .foregroundStyle(TVTheme.text)
            Spacer()
            Text("₺ " + fmtMoney(sum))
                .font(.caption)
                .foregroundStyle(TVTheme.subtext)
        }
        .textCase(nil)
    }

    // MARK: - Row view

    private func rowView(_ r: PortfolioRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(r.asset.name)
                    .bold()
                    .foregroundStyle(TVTheme.text)
                Spacer()

                if let pnl = r.pnlTRY {
                    Text("₺ " + fmtMoney(pnl))
                        .foregroundStyle(pnl >= 0 ? TVTheme.up : TVTheme.down)
                        .bold()
                } else {
                    Text("K/Z —")
                        .font(.caption)
                        .foregroundStyle(TVTheme.subtext)
                }
            }

            HStack {
                Text(r.asset.symbol)
                    .font(.caption)
                    .foregroundStyle(TVTheme.subtext)
                Spacer()
                Text("Miktar: \(fmtQty(r.asset.quantity))")
                    .font(.caption)
                    .foregroundStyle(TVTheme.subtext)
            }

            HStack {
                Text("Değer")
                    .font(.caption)
                    .foregroundStyle(TVTheme.subtext)
                Spacer()
                if let v = r.valueTRY {
                    Text("₺ " + fmtMoney(v))
                        .bold()
                        .foregroundStyle(TVTheme.text)
                } else {
                    Text("—")
                        .foregroundStyle(TVTheme.subtext)
                }
            }

            if let d = r.dayPnlTRY {
                HStack {
                    Text("Günlük")
                        .font(.caption)
                        .foregroundStyle(TVTheme.subtext)

                    Spacer()

                    Text("₺ " + fmtMoney(d))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(d >= 0 ? TVTheme.up : TVTheme.down)

                    if let pct = r.dayChangePct {
                        Text(String(format: "(%+.2f%%)", pct))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(pct >= 0 ? TVTheme.up : TVTheme.down)
                    }
                }
            }

            if r.asset.avgCostTRY != nil {
                Text("Maliyet girildi → K/Z hesaplanır.")
                    .font(.caption2)
                    .foregroundStyle(TVTheme.subtext)
            }

            if r.isUSDConverted {
                Text("USD→TRY çevrildi.")
                    .font(.caption2)
                    .foregroundStyle(TVTheme.subtext)
            }
        }
        .padding(12)
        .background(TVTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(TVTheme.stroke, lineWidth: 1)
        )
    }

    @MainActor
    private func refreshAssetsData() async {
        guard !isRefreshing else { return }
        isRefreshing = true

        vm.clearPriceCache()
        vm.loadFromDiskAndRefresh()

        try? await Task.sleep(nanoseconds: 180_000_000)
        let deadline = Date().addingTimeInterval(3.0)
        while vm.isLoading && Date() < deadline {
            try? await Task.sleep(nanoseconds: 120_000_000)
        }

        isRefreshing = false
    }

    private func colorForType(_ type: AssetType) -> Color {
        switch type {
        case .stock: return TVTheme.accent
        case .fx: return TVTheme.up
        case .metal: return TVTheme.warning
        case .crypto: return Color(hex: "#F7931A")
        case .fund: return Color(hex: "#7B61FF")
        case .cash: return Color(hex: "#00C853")
        }
    }

    private func detailRoute(for asset: Asset) -> StockDetailRoute? {
        let symbol: String
        switch asset.type {
        case .stock, .fund:
            symbol = asset.symbol.normalizedBISTSymbol()
        case .fx, .crypto:
            symbol = asset.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        case .metal:
            symbol = yahooSymbolForMetal(asset.symbol)
        case .cash:
            return nil
        }

        guard !symbol.isEmpty else { return nil }
        return .live(symbol: symbol)
    }

    private func yahooSymbolForMetal(_ original: String) -> String {
        let s = original.uppercased()
        if s.contains("XAU") || s.contains("GOLD") { return "GC=F" }
        if s.contains("XAG") || s.contains("SILVER") { return "SI=F" }
        return original.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    // MARK: - Delete mapping

    private func requestDelete(offsets: IndexSet, within sectionRows: [PortfolioRow]) {
        pendingDelete = (offsets, sectionRows)
        if let first = offsets.first, sectionRows.indices.contains(first) {
            let a = sectionRows[first].asset
            pendingDeleteName = a.name.isEmpty ? a.symbol : a.name
        } else {
            pendingDeleteName = ""
        }
        showDeleteConfirm = true
    }

    private func delete(offsets: IndexSet, within sectionRows: [PortfolioRow]) {
        let symbolsToDelete = offsets.compactMap { idx -> String? in
            guard sectionRows.indices.contains(idx) else { return nil }
            return sectionRows[idx].asset.symbol.uppercased()
        }
        guard !symbolsToDelete.isEmpty else { return }
        vm.deleteBySymbols(symbolsToDelete)
        vm.refreshPrices()
    }

    // MARK: - Allocation helper

    private func allocationByType() -> [AssetType: Double] {
        var dict: [AssetType: Double] = [:]
        for r in vm.rows {
            if let v = r.valueTRY {
                dict[r.asset.type, default: 0] += v
            }
        }
        return dict
    }

    // ✅ iOS angle → slice mapping (tvOS'ta angle seçimi yok ama fonksiyon kalsın)
    private func typeForAngle(_ angleValue: Double?, slices: [(type: AssetType, value: Double)]) -> AssetType? {
        guard let angleValue, !slices.isEmpty else { return nil }
        let target = angleValue
        var running = 0.0
        for s in slices {
            running += s.value
            if target <= running { return s.type }
        }
        return slices.last?.type
    }

    // MARK: - Formatters

    private func fmtMoney(_ x: Double) -> String {
        let nf = NumberFormatter()
        nf.locale = Locale(identifier: "tr_TR")
        nf.numberStyle = .decimal
        nf.minimumFractionDigits = 2
        nf.maximumFractionDigits = 2
        return nf.string(from: NSNumber(value: x)) ?? String(format: "%.2f", x)
    }

    private func fmtQty(_ x: Double) -> String {
        let nf = NumberFormatter()
        nf.locale = Locale(identifier: "tr_TR")
        nf.numberStyle = .decimal
        nf.minimumFractionDigits = 0
        nf.maximumFractionDigits = 6
        return nf.string(from: NSNumber(value: x)) ?? "\(x)"
    }

    private func fmtPct(_ x: Double) -> String {
        String(format: "%.1f", x)
    }
}

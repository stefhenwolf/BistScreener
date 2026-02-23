import SwiftUI
import Charts

struct AssetsView: View {
    @StateObject private var vm = PortfolioViewModel()

    @State private var showSheet = false
    @State private var editing: Asset? = nil
    @State private var pendingDelete: (offsets: IndexSet, sectionRows: [PortfolioRow])?
    @State private var showDeleteConfirm = false

    // ✅ Donut seçimi
    @State private var selectedAngle: Double? = nil
    @State private var selectedType: AssetType? = nil

    var body: some View {
        NavigationStack {
            List {
                Section {
                    summaryCardRow
                    allocationPieRow
                }

                if vm.isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                if let e = vm.errorText {
                    Text(e)
                        .foregroundStyle(.red)
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
                                ForEach(Array(sectionRows.enumerated()), id: \.element.id) { idx, r in
                                    rowCell(idx: idx, r: r, sectionRows: sectionRows)
                                }
                                // ✅ tvOS'ta .onDelete / swipe yok
                                #if !os(tvOS)
                                .onDelete { offsets in
                                    pendingDelete = (offsets, sectionRows)
                                    showDeleteConfirm = true
                                }
                                #endif
                            } header: {
                                sectionHeader(type: t, rows: sectionRows)
                            }
                        }
                    }
                }
            }
            .confirmationDialog(
                "Varlığı portföyden kaldır?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Sil", role: .destructive) {
                    if let p = pendingDelete {
                        delete(offsets: p.offsets, within: p.sectionRows)
                        pendingDelete = nil
                    }
                }
                Button("Vazgeç", role: .cancel) {
                    pendingDelete = nil
                }
            } message: {
                Text("Bu işlem geri alınamaz.")
            }
            .appScreenBackground()
            .listStyle(platformListStyle)
            .navigationTitle("Varlıklarım")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Güncelle") { vm.refreshPrices() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editing = nil
                        showSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .task {
                await vm.loadFromDisk()
                try? await Task.sleep(nanoseconds: 150_000_000)
                vm.refreshPrices()
            }
            // ✅ Pull-to-refresh kapalı (yenileme butonla yapılır)

            .sheet(isPresented: $showSheet) {
                AddEditAssetSheet(asset: editing) { a in
                    vm.upsert(a)
                    vm.refreshPrices()
                }
                .scrollContentBackground(.hidden)
                .appScreenBackground()
            }

            // tvOS'ta scrollContentBackground bazı sürümlerde farklı davranabilir; derlemeyi bozmasın:
            #if !os(tvOS)
            .scrollContentBackground(.hidden)
            #endif
            .appScreenBackground()
        }

        #if !os(tvOS)
        .scrollContentBackground(.hidden)
        #endif
        .appScreenBackground()
    }

    // MARK: - Platform List Style

    private var platformListStyle: some ListStyle {
        #if os(tvOS)
        return .plain
        #else
        return .insetGrouped
        #endif
    }

    // MARK: - Row Cell (iOS vs tvOS)

    @ViewBuilder
    private func rowCell(idx: Int, r: PortfolioRow, sectionRows: [PortfolioRow]) -> some View {
        #if os(tvOS)
        // ✅ tvOS: Focus ile gezilebilir satır + sağda aksiyonlar
        HStack(alignment: .top, spacing: 12) {
            Button {
                editing = r.asset
                showSheet = true
            } label: {
                rowView(r)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            VStack(spacing: 10) {
                Button {
                    pendingDelete = (IndexSet(integer: idx), sectionRows)
                    showDeleteConfirm = true
                } label: {
                    Label("Sil", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 4)

        #else
        // ✅ iOS: swipeActions + normal tap
        Button {
            editing = r.asset
            showSheet = true
        } label: {
            rowView(r)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                pendingDelete = (IndexSet(integer: idx), sectionRows)
                showDeleteConfirm = true
            } label: {
                Label("Sil", systemImage: "trash")
            }
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

            HStack(alignment: .firstTextBaseline) {
                Text("₺ " + fmtMoney(vm.totalTRY))
                    .font(.title2)
                    .bold()

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Günlük K/Z")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("₺ " + fmtMoney(dayPnL))
                            .font(.subheadline)
                            .bold()
                            .foregroundStyle(dayPnL >= 0 ? .green : .red)
                    }

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Toplam K/Z")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("₺ " + fmtMoney(totalPnL))
                            .font(.subheadline)
                            .bold()
                            .foregroundStyle(totalPnL >= 0 ? .green : .red)
                    }
                }
            }

            if let t = vm.lastUpdated {
                Text("Güncelleme: \(t.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
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

                Spacer()

                if selectedType != nil {
                    Button("Seçimi temizle") {
                        selectedType = nil
                        selectedAngle = nil
                    }
                    .font(.caption)
                }
            }

            if slices.isEmpty || total <= 0 {
                Text("Henüz değer hesaplanacak varlık yok.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ZStack {
                    Chart {
                        ForEach(slices, id: \.type) { s in
                            SectorMark(
                                angle: .value("Değer", s.value),
                                innerRadius: .ratio(0.62),
                                angularInset: 2
                            )
                            .foregroundStyle(by: .value("Tür", s.type.title))
                            .opacity(selectedType == nil || selectedType == s.type ? 1.0 : 0.25)
                        }
                    }
                    .frame(height: 260)

                    // ✅ iOS: touch ile angle seçimi
                    #if !os(tvOS)
                    .chartAngleSelection(value: $selectedAngle)
                    .onChange(of: selectedAngle) { _, newAngle in
                        selectedType = typeForAngle(newAngle, slices: slices)
                    }
                    #endif

                    VStack(spacing: 4) {
                        if let st = selectedType,
                           let v = selectedValue,
                           let p = selectedPct {
                            Text(st.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text("₺ " + fmtMoney(v))
                                .font(.title3)
                                .bold()

                            Text("%" + fmtPct(p))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Toplam")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text("₺ " + fmtMoney(total))
                                .font(.title3)
                                .bold()

                            #if os(tvOS)
                            Text("Legend’den seç")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            #else
                            Text("Pastaya dokun")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            #endif
                        }
                    }
                    .padding(.horizontal, 10)
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
                                Text(s.type.title)
                                    .fontWeight(selectedType == s.type ? .bold : .regular)

                                Spacer()

                                Text("%" + fmtPct(pct))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Text("₺ " + fmtMoney(s.value))
                                    .bold()
                            }
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        #else
                        HStack {
                            Text(s.type.title)
                                .fontWeight(selectedType == s.type ? .bold : .regular)

                            Spacer()

                            Text("%" + fmtPct(pct))
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text("₺ " + fmtMoney(s.value))
                                .bold()
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
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 10, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    // MARK: - Empty State Row

    private var emptyStateRow: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("Henüz varlık yok")
                .font(.headline)
            Text("Sağ üstten + ile ekleyebilirsin.")
                .font(.footnote)
                .foregroundStyle(.secondary)
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
            Spacer()
            Text("₺ " + fmtMoney(sum))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .textCase(nil)
    }

    // MARK: - Row view

    private func rowView(_ r: PortfolioRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(r.asset.name).bold()
                Spacer()

                if let pnl = r.pnlTRY {
                    Text("₺ " + fmtMoney(pnl))
                        .foregroundStyle(pnl >= 0 ? .green : .red)
                        .bold()
                } else {
                    Text("K/Z —")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Text(r.asset.symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Miktar: \(fmtQty(r.asset.quantity))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Değer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let v = r.valueTRY {
                    Text("₺ " + fmtMoney(v)).bold()
                } else {
                    Text("—")
                        .foregroundStyle(.secondary)
                }
            }

            if let d = r.dayPnlTRY {
                HStack {
                    Text("Günlük")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("₺ " + fmtMoney(d))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(d >= 0 ? .green : .red)

                    if let pct = r.dayChangePct {
                        Text(String(format: "(%+.2f%%)", pct))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(pct >= 0 ? .green : .red)
                    }
                }
            }

            if r.asset.avgCostTRY != nil {
                Text("Maliyet girildi → K/Z hesaplanır.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if r.isUSDConverted {
                Text("USD→TRY çevrildi.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Delete mapping

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

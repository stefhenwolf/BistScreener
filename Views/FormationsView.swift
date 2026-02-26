import SwiftUI

/// Tarama sonuçlarından formasyon bazlı ekran:
/// Her formasyon altında o formasyona uyan hisseler listelenir.
struct FormationsView: View {
    @ObservedObject var vm: ScannerViewModel

    // UI
    @State private var minTotalScore: Double = 60
    @State private var sort: SortMode = .countDesc

    enum SortMode: String, CaseIterable, Identifiable {
        var id: String { rawValue }
        case countDesc = "Adet ↓"
        case bestScoreDesc = "En iyi skor ↓"
        case nameAsc = "İsim ↑"
    }

    var body: some View {
        ZStack {
            TVTheme.bg.ignoresSafeArea()
            content
        }
        .navigationTitle("Formasyonlar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(TVTheme.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)

        // ✅ KRİTİK: Endeks nereden değişirse değişsin (ayarlar / chip / başka ekran)
        // Formasyonlar sayfasında otomatik tarama yok.
        .onChangeCompat(of: vm.selectedIndex, initial: true) { newValue in
            vm.switchIndex(newValue)
            // ✅ Kullanıcı "Yeniden Tara" butonuna basmadan tarama başlamasın.
        }
        .navigationDestination(for: StockDetailRoute.self) { route in
            StockDetailView(route: route)
        }
    }

    private var content: some View {
        VStack(spacing: DS.s12) {
            headerCard
                .padding(.horizontal, DS.s16)
                .padding(.top, DS.s12)

            if vm.isScanning {
                progressCard
                    .padding(.horizontal, DS.s16)
            } else if let e = vm.errorText, !e.isEmpty {
                errorCard(e)
                    .padding(.horizontal, DS.s16)
            }

            listBody
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .tvNavStyle()
    }

    // MARK: - Header

    private var headerCard: some View {
        TVCard {
            VStack(alignment: .leading, spacing: DS.s12) {

                HStack {
                    Text("Filtreler")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(TVTheme.text)

                    Spacer()

                    // ✅ Sağ üst: Endeks seçici (tıklanınca menu açılır)
                    Menu {
                        ForEach(IndexOption.allCases, id: \.self) { idx in
                            Button(idx.title) {
                                vm.switchIndex(idx)
                                // ✅ Endeks değişince otomatik tarama yok.
                            }
                        }
                    } label: {
                        TVChip(vm.selectedIndex.title, systemImage: "chart.line.uptrend.xyaxis")
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Min Skor")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(TVTheme.subtext)
                        Spacer()
                        TVChip("\(Int(minTotalScore))", systemImage: "target")
                    }

                    Slider(value: $minTotalScore, in: 0...100, step: 1)
                        .tint(TVTheme.up)
                }

                HStack(spacing: 10) {
                    TVChip("Sonuç \(filteredResults.count)", systemImage: "list.bullet")

                    Menu {
                        Picker("Sırala", selection: $sort) {
                            ForEach(SortMode.allCases) { s in
                                Text(s.rawValue).tag(s)
                            }
                        }
                    } label: {
                        TVChip(sort.rawValue, systemImage: "arrow.up.arrow.down")
                    }

                    Spacer()

                    Button { vm.startScan() } label: {
                        TVChip(vm.isScanning ? "Taranıyor" : "Yeniden Tara",
                               systemImage: vm.isScanning ? "hourglass" : "play.fill")
                    }
                    .buttonStyle(.plain)
                    .disabled(vm.isScanning)
                }
            }
        }
    }

    // MARK: - Progress / Error

    private var progressCard: some View {
        TVCard {
            VStack(alignment: .leading, spacing: DS.s12) {
                HStack {
                    Text("İlerleme")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(TVTheme.text)
                    Spacer()
                    Text("\(Int(vm.progressValue * 100))%")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(TVTheme.subtext)
                }

                ProgressView(value: vm.progressValue)
                    .tint(TVTheme.up)

                Text(vm.progressText)
                    .font(.footnote)
                    .foregroundStyle(TVTheme.subtext)
            }
        }
    }

    private func errorCard(_ text: String) -> some View {
        TVCard {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)

                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(TVTheme.subtext)
                    .lineLimit(2)

                Spacer()

                Button { vm.startScan() } label: {
                    TVChip("Tekrar", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Grouping

    private var filteredResults: [ScanResult] {
        vm.results.filter { $0.totalScore >= Int(minTotalScore) }
    }

    private var grouped: [CandlePattern: [(ScanResult, Int)]] {
        var dict: [CandlePattern: [(ScanResult, Int)]] = [:]
        for r in filteredResults {
            for ps in r.patterns {
                dict[ps.pattern, default: []].append((r, ps.score))
            }
        }
        return dict
    }

    private var orderedPatterns: [CandlePattern] {
        let keys = Array(grouped.keys)

        switch sort {
        case .countDesc:
            return keys.sorted { (grouped[$0]?.count ?? 0) > (grouped[$1]?.count ?? 0) }

        case .bestScoreDesc:
            return keys.sorted { a, b in
                let maxA = grouped[a]?.map(\.1).max() ?? 0
                let maxB = grouped[b]?.map(\.1).max() ?? 0
                if maxA != maxB { return maxA > maxB }
                return (grouped[a]?.count ?? 0) > (grouped[b]?.count ?? 0)
            }

        case .nameAsc:
            return keys.sorted {
                $0.rawValue.localizedCaseInsensitiveCompare($1.rawValue) == .orderedAscending
            }
        }
    }

    // MARK: - List

    @ViewBuilder
    private var listBody: some View {
        let patterns = orderedPatterns

        if patterns.isEmpty {
            emptyStateCard
                .padding(.horizontal, DS.s16)
                .padding(.top, DS.s12)
        } else {
            List {
                patternsList(patterns)
            }
            .id(vm.selectedIndex)               // ✅ endeks değişince list reset
            .transaction { $0.animation = nil } // ✅ zıplama yok
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
    }

    @ViewBuilder
    private func patternsList(_ patterns: [CandlePattern]) -> some View {
        ForEach(patterns, id: \.self) { p in
            patternBlock(for: p)
        }
    }

    @ViewBuilder
    private func patternBlock(for p: CandlePattern) -> some View {
        if let rows = grouped[p], !rows.isEmpty {
            // ✅ Header row
            sectionHeaderRow(pattern: p, rows: rows)
                .listRowInsets(EdgeInsets(top: 8, leading: DS.s16, bottom: 6, trailing: DS.s16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            // ✅ Sorted rows
            let sortedRows = sortRows(rows)

            ForEach(sortedRows, id: \.0.id) { (r, pScore) in
                NavigationLink(value: StockDetailRoute.snapshot(r)) {
                    FormationRowPro(result: r, pattern: p, patternScore: pScore)
                        .foregroundStyle(TVTheme.text)
                }
                .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        } else {
            EmptyView()
        }
    }

    private func sortRows(_ rows: [(ScanResult, Int)]) -> [(ScanResult, Int)] {
        rows.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            if lhs.0.totalScore != rhs.0.totalScore { return lhs.0.totalScore > rhs.0.totalScore }
            return lhs.0.changePct > rhs.0.changePct
        }
    }

    // MARK: - Header Row

    private func sectionHeaderRow(pattern: CandlePattern, rows: [(ScanResult, Int)]) -> some View {
        let count = rows.count
        let best = rows.map(\.1).max() ?? 0
        let avg = rows.isEmpty ? 0 : Int(Double(rows.map(\.1).reduce(0, +)) / Double(rows.count))

        return VStack(alignment: .leading, spacing: 8) {
            Text(pattern.rawValue)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.black)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white)
                .clipShape(Capsule())

            HStack(spacing: 8) {
                TVChip("\(count) adet", systemImage: "number")
                TVChip("Best \(best)", systemImage: "crown.fill")
                TVChip("Avg \(avg)", systemImage: "sum")
                Spacer()
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

    // MARK: - Empty

    private var emptyStateCard: some View {
        TVCard {
            VStack(spacing: 10) {
                Image(systemName: vm.isScanning ? "hourglass" : "sparkle.magnifyingglass")
                    .font(.system(size: 34))
                    .foregroundStyle(TVTheme.subtext)

                Text(vm.isScanning ? "Taranıyor…" : "Formasyon yok")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(TVTheme.text)

                Text(vm.isScanning ? "Lütfen bekle" : "Min skoru düşür veya taramayı başlat.")
                    .font(.footnote)
                    .foregroundStyle(TVTheme.subtext)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Row

private struct FormationRowPro: View {
    let result: ScanResult
    let pattern: CandlePattern
    let patternScore: Int

    private var changeText: String {
        String(format: "%+.2f%%", result.changePct)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            HStack(alignment: .firstTextBaseline) {
                Text(result.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(TVTheme.text)

                Spacer()

                ScorePill(score: result.totalScore)
            }

            HStack(spacing: 10) {
                Text(changeText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(result.changePct >= 0 ? TVTheme.up : TVTheme.down)

                Text(String(format: "%.2f", result.lastClose))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TVTheme.subtext)

                Spacer()

                Text(result.lastDate, format: .dateTime.day().month().year())
                    .font(.caption)
                    .foregroundStyle(TVTheme.subtext)
            }

            HStack(spacing: 8) {
                TVChip(pattern.rawValue, systemImage: "sparkles")
                TVChip("Pattern \(patternScore)", systemImage: "waveform.path.ecg")
                TVChip("Total \(result.totalScore)", systemImage: "target")
                Spacer()
            }

            scoreBar
        }
        .padding(14)
        .background(TVTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(TVTheme.stroke, lineWidth: 1)
        )
    }

    private var scoreBar: some View {
        let pct = min(max(Double(result.totalScore) / 100.0, 0), 1)
        return GeometryReader { geo in
            let w = geo.size.width
            let fill = result.totalScore >= 60 ? TVTheme.up : TVTheme.down

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(TVTheme.surface2)

                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(fill.opacity(0.60))
                    .frame(width: max(10, w * pct))
            }
        }
        .frame(height: 10)
    }
}

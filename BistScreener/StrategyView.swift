import SwiftUI

struct StrategyView: View {
    @Binding var selectedTab: AppTab
    @EnvironmentObject private var strategy: LiveStrategyStore

    @State private var startThousands: Double = 100
    @State private var selectedStartDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var showStrategyEditor = false
    @State private var expandedDayKeys: Set<TimeInterval> = []

    var body: some View {
        ZStack {
            TVTheme.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: DS.s16) {
                    startCard
                    liveCard
                    pendingActionsCard
                    settingsCard
                    eventsCard
                }
                .padding(.horizontal, DS.s16)
                .padding(.vertical, DS.s12)
            }
            .tint(.white)
            .refreshable {
                await strategy.refreshNow()
            }
        }
        .navigationTitle("Strateji")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showStrategyEditor) {
            NavigationStack {
                StrategyConfigEditorView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Kapat") { showStrategyEditor = false }
                                .foregroundStyle(TVTheme.text)
                        }
                    }
            }
            .presentationBackground(TVTheme.bg)
        }
        .onAppear {
            if strategy.initialCapitalTL >= 10_000 {
                startThousands = strategy.initialCapitalTL / 1_000.0
            }
            if let started = strategy.startedAt {
                let day = Calendar.current.startOfDay(for: started)
                if startDateOptions.contains(day) {
                    selectedStartDate = day
                } else {
                    selectedStartDate = Calendar.current.startOfDay(for: Date())
                }
            }
            if let latest = strategy.events.last {
                let day = Calendar.current.startOfDay(for: latest.date)
                expandedDayKeys = [day.timeIntervalSinceReferenceDate]
            }
        }
        .onChange(of: strategy.events.count) { _ in
            if let latest = strategy.events.last {
                let day = Calendar.current.startOfDay(for: latest.date)
                expandedDayKeys.insert(day.timeIntervalSinceReferenceDate)
            }
        }
        .tvNavStyle()
    }

    private var startCard: some View {
        TVCard {
            VStack(alignment: .leading, spacing: DS.s12) {
                HStack {
                    Text("Strateji Başlat")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(TVTheme.text)
                    Spacer()
                    statusChip
                }

                Text("Başlangıç Sermayesi")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TVTheme.subtext)

                Slider(value: $startThousands, in: 10...1000, step: 10)
                    .tint(TVTheme.up)

                HStack {
                    Text("Başlangıç Günü")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(TVTheme.subtext)
                    Spacer()
                    Menu {
                        ForEach(startDateOptions, id: \.self) { day in
                            Button(dayLabel(day)) {
                                selectedStartDate = day
                            }
                        }
                    } label: {
                        TVChip(dayLabel(selectedStartDate), systemImage: "calendar")
                    }
                }

                HStack {
                    Text("₺\(Int(startThousands)).000")
                        .font(.title3.bold())
                        .foregroundStyle(TVTheme.text)

                    Spacer()

                    if strategy.isRunning {
                        Button {
                            strategy.stopStrategy()
                        } label: {
                            actionCapsule("Durdur", color: TVTheme.down)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            strategy.startStrategy(
                                initialCapitalThousands: Int(startThousands),
                                startDate: selectedStartDate
                            )
                        } label: {
                            actionCapsule("Başlat", color: TVTheme.up)
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        Task { await strategy.refreshNow() }
                    } label: {
                        actionCapsule("Canlı Güncelle", color: TVTheme.surface2)
                    }
                    .buttonStyle(.plain)
                    .disabled(!strategy.isRunning || strategy.isRefreshing)

                    Button {
                        selectedTab = .scan
                    } label: {
                        actionCapsule("Tarama Sekmesi", color: TVTheme.surface2)
                    }
                    .buttonStyle(.plain)
                }

                if let startedAt = strategy.startedAt {
                    Text("Başlangıç: \(startedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(TVTheme.subtext)
                }

                if let snapshotDate = strategy.sourceSnapshotDate {
                    Text("Kullanılan son tarama: \(snapshotDate.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(TVTheme.subtext)
                }

                if let err = strategy.errorText, !err.isEmpty {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var liveCard: some View {
        TVCard {
            VStack(alignment: .leading, spacing: DS.s12) {
                HStack {
                    Text("Canlı Strateji Kartı")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(TVTheme.text)
                    Spacer()

                    if strategy.isRefreshing {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.9)
                    }
                }

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 10) {
                    statCell("Başlangıç", formatTL(strategy.initialCapitalTL))
                    statCell("Nakit", formatTL(strategy.cashTL))
                    statCell("Açık Değer", formatTL(strategy.openValueTL))
                    statCell("Toplam", formatTL(strategy.totalValueTL),
                             color: strategy.totalValueTL >= strategy.initialCapitalTL ? TVTheme.up : TVTheme.down)
                    statCell("Toplam K/Z", formatTL(strategy.totalReturnTL),
                             color: strategy.totalReturnTL >= 0 ? TVTheme.up : TVTheme.down)
                    statCell("Getiri %", String(format: "%+.2f%%", strategy.totalReturnPct),
                             color: strategy.totalReturnPct >= 0 ? TVTheme.up : TVTheme.down)
                }

                if strategy.holdings.isEmpty {
                    Text(strategy.isRunning ? "Henüz açık strateji pozisyonu yok." : "Strateji başlatılmadı.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(TVTheme.subtext)
                } else {
                    VStack(spacing: 8) {
                        ForEach(strategy.holdings) { h in
                            holdingRow(h)
                        }
                    }
                }

                if let updated = strategy.lastUpdated {
                    Text("Son güncelleme: \(updated.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(TVTheme.subtext)
                }
            }
        }
    }

    private var settingsCard: some View {
        TVCard {
            VStack(alignment: .leading, spacing: DS.s12) {
                HStack {
                    Text("Strateji Ayarları")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(TVTheme.text)
                    Spacer()
                    Button {
                        showStrategyEditor = true
                    } label: {
                        actionCapsule("Sinyal Ayarları", color: TVTheme.surface2)
                    }
                    .buttonStyle(.plain)
                }

                Picker("Endeks", selection: indexBinding) {
                    ForEach(IndexOption.allCases) { idx in
                        Text(idx.title).tag(idx)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Preset", selection: presetBinding) {
                    ForEach(TomorrowPreset.allCases, id: \.self) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.segmented)

                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Al/Sat Onayı")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(TVTheme.text)
                        Text("Tüm AL/SAT işlemleri zorunlu olarak onay kuyruğuna düşer.")
                            .font(.caption2)
                            .foregroundStyle(TVTheme.subtext)
                    }
                    Spacer()
                    TVChip("Zorunlu", systemImage: "checkmark.shield")
                }
                .padding(10)
                .background(TVTheme.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                stepperRow(
                    title: "Hisse başı max",
                    valueText: formatTL(strategy.settings.maxPerPositionTL),
                    decrement: { strategy.settings.maxPerPositionTL -= 500 },
                    increment: { strategy.settings.maxPerPositionTL += 500 }
                )

                stepperRow(
                    title: "Maks açık pozisyon",
                    valueText: "\(strategy.settings.maxOpenPositions)",
                    decrement: { strategy.settings.maxOpenPositions -= 1 },
                    increment: { strategy.settings.maxOpenPositions += 1 }
                )

                sliderRow(
                    title: "TP1 (İlk Kâr Al)",
                    value: tp1Binding,
                    range: 1...30,
                    step: 0.5,
                    format: "+%.1f%%"
                )
                sliderRow(
                    title: "TP2 (Nihai Kâr Al)",
                    value: tp2Binding,
                    range: 4...40,
                    step: 0.5,
                    format: "+%.1f%%"
                )
                sliderRow(
                    title: "TP1 Satış Oranı",
                    value: tp1SellBinding,
                    range: 10...90,
                    step: 5,
                    format: "%%%.0f"
                )
                sliderRow(
                    title: "Zarar Kes (SL)",
                    value: slBinding,
                    range: 2...15,
                    step: 0.5,
                    format: "-%.1f%%"
                )

                stepperRow(
                    title: "Max tutma",
                    valueText: "\(strategy.settings.maxHoldDays) gün",
                    decrement: { strategy.settings.maxHoldDays -= 1 },
                    increment: { strategy.settings.maxHoldDays += 1 }
                )

                stepperRow(
                    title: "Cooldown",
                    valueText: "\(strategy.settings.cooldownDays) gün",
                    decrement: { strategy.settings.cooldownDays -= 1 },
                    increment: { strategy.settings.cooldownDays += 1 }
                )

                stepperRow(
                    title: "Oto yenileme",
                    valueText: "\(strategy.settings.autoRefreshMinutes) dk",
                    decrement: { strategy.settings.autoRefreshMinutes -= 1 },
                    increment: { strategy.settings.autoRefreshMinutes += 1 }
                )

                Text("Canlı simülasyon Backtest kurallarını kullanır: preset, kademeli TP1/TP2, SL/Max gün, cooldown, gün sonu hareketleri ve nakit yönetimi.")
                    .font(.caption)
                    .foregroundStyle(TVTheme.subtext)
            }
        }
    }

    private var pendingActionsCard: some View {
        TVCard {
            VStack(alignment: .leading, spacing: DS.s12) {
                HStack {
                    Text("Onay Bekleyen İşlemler")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(TVTheme.text)
                    Spacer()
                    TVChip("\(strategy.pendingActions.count)", systemImage: "clock.badge.exclamationmark")
                }

                if strategy.pendingActions.isEmpty {
                    Text("Bekleyen emir yok.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(TVTheme.subtext)
                } else {
                    HStack(spacing: 8) {
                        Button {
                            strategy.approveAllPendingActions()
                        } label: {
                            actionCapsule("Tümünü Onayla", color: TVTheme.up)
                        }
                        .buttonStyle(.plain)

                        Button {
                            strategy.rejectAllPendingActions()
                        } label: {
                            actionCapsule("Tümünü Reddet", color: TVTheme.down)
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(strategy.pendingActions.sorted { $0.createdAt > $1.createdAt }) { action in
                        pendingActionRow(action)
                    }
                }
            }
        }
    }

    private var eventsCard: some View {
        TVCard {
            VStack(alignment: .leading, spacing: DS.s12) {
                Text("Gün Sonu Hareketleri")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(TVTheme.text)

                if strategy.events.isEmpty {
                    Text("Henüz hareket yok.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(TVTheme.subtext)
                } else {
                    ForEach(daySections) { section in
                        daySectionCard(section)
                    }
                }
            }
        }
    }

    private var daySections: [EventDaySection] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: strategy.events) { event in
            cal.startOfDay(for: event.date)
        }

        return grouped.keys.sorted(by: >).map { day in
            let dayEvents = (grouped[day] ?? []).sorted { $0.date < $1.date }
            let end = dayEvents.last
            return EventDaySection(
                day: day,
                events: dayEvents,
                endCashTL: end?.cashAfterTL ?? 0,
                holdingsText: end?.holdingsText ?? "Yok"
            )
        }
    }

    private struct HoldingExitPlan {
        let tp1Price: Double
        let tp2Price: Double
        let slPrice: Double
        let daysHeld: Int
        let targetExitDate: Date
        let tp1Executed: Bool
        let tp1SellPercent: Double
        let statusText: String
    }

    private func exitPlan(for holding: LiveStrategyHolding) -> HoldingExitPlan {
        let now = Date()
        let cal = Calendar.current
        let tp1Price = holding.firstBuyPriceTL * (1.0 + strategy.settings.tp1Pct / 100.0)
        let tp2Price = holding.avgCostTL * (1.0 + strategy.settings.tp2Pct / 100.0)
        let slPrice = holding.avgCostTL * (1.0 - strategy.settings.stopLossPct / 100.0)
        let entryDay = cal.startOfDay(for: holding.entryDate)
        let today = cal.startOfDay(for: now)
        let daysHeld = max(0, cal.dateComponents([.day], from: entryDay, to: today).day ?? 0)
        let targetExitDate = cal.date(byAdding: .day, value: strategy.settings.maxHoldDays, to: entryDay) ?? entryDay

        let statusText: String
        if holding.lastPriceTL <= slPrice {
            statusText = "SL seviyesinde: seans içi SAT adayı."
        } else if holding.lastPriceTL >= tp2Price {
            statusText = "TP2 seviyesinde: kalan lotlar için SAT adayı."
        } else if !holding.tp1Executed, holding.lastPriceTL >= tp1Price {
            statusText = "TP1 seviyesinde: kısmi SAT adayı."
        } else if holding.tp1Executed {
            statusText = "TP1 alındı: kalan lotlar TP2/SL/Süre ile yönetilir."
        } else if daysHeld >= strategy.settings.maxHoldDays {
            statusText = "Süre doldu: AL sinyali zayıflarsa SAT."
        } else {
            statusText = "Süre çıkışı: \(targetExitDate.formatted(date: .abbreviated, time: .omitted)) sonrası, AL sinyali düşerse."
        }

        return HoldingExitPlan(
            tp1Price: tp1Price,
            tp2Price: tp2Price,
            slPrice: slPrice,
            daysHeld: daysHeld,
            targetExitDate: targetExitDate,
            tp1Executed: holding.tp1Executed,
            tp1SellPercent: strategy.settings.tp1SellPercent,
            statusText: statusText
        )
    }

    private func holdingRow(_ holding: LiveStrategyHolding) -> some View {
        let clean = holding.symbol.replacingOccurrences(of: ".IS", with: "")
        let plan = exitPlan(for: holding)
        let tp1Info = tp1ExecutionInfo(for: holding)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(clean)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(TVTheme.text)
                    Text("Lot \(String(format: "%.2f", holding.quantity)) • Maliyet \(formatTL(holding.avgCostTL))")
                        .font(.caption2)
                        .foregroundStyle(TVTheme.subtext)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatTL(holding.marketValueTL))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(TVTheme.text)
                    Text(String(format: "%+.2f%%", holding.pnlPct))
                        .font(.caption)
                        .foregroundStyle(holding.pnlPct >= 0 ? TVTheme.up : TVTheme.down)
                }
            }

            HStack(spacing: 6) {
                exitRuleChip("\(plan.tp1Executed ? "✓ " : "")TP1 \(formatTL(plan.tp1Price))", color: TVTheme.up)
                exitRuleChip("TP2 \(formatTL(plan.tp2Price))", color: TVTheme.up)
                exitRuleChip("TP1 Sat %\(Int(plan.tp1SellPercent))", color: TVTheme.subtext)
                exitRuleChip("SL \(formatTL(plan.slPrice))", color: TVTheme.down)
                exitRuleChip("Süre \(plan.daysHeld)/\(strategy.settings.maxHoldDays)g", color: TVTheme.subtext)
            }

            Text("Planlanan süre satışı: \(plan.targetExitDate.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption2)
                .foregroundStyle(TVTheme.subtext)

            Text("İlk AL: \(holding.firstBuyDate.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption2)
                .foregroundStyle(TVTheme.subtext)

            if holding.addOnCount > 0 {
                Text("Ek AL: \(holding.addOnCount) • Son ekleme: \(holding.lastBuyDate.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(TVTheme.subtext)
            }

            if holding.tp1Executed {
                Text(String(format: "TP1 gerçekleşti: +%.1f%% • TP2 seviyesi: +%.1f%% (%@)", tp1Info.tp1Pct, strategy.settings.tp2Pct, formatTL(plan.tp2Price)))
                    .font(.caption2)
                    .foregroundStyle(TVTheme.up)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
            }

            Text("Sonraki ekleme: \(nextAddOnHint())")
                .font(.caption2)
                .foregroundStyle(TVTheme.subtext)

            Text(plan.statusText)
                .font(.caption2)
                .foregroundStyle(TVTheme.subtext)
                .lineLimit(2)
                .minimumScaleFactor(0.9)
        }
        .padding(10)
        .background(TVTheme.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func tp1ExecutionInfo(for holding: LiveStrategyHolding) -> (tp1Pct: Double, eventDate: Date?) {
        let normalized = holding.symbol.normalizedBISTSymbol()
        if let event = strategy.events.reversed().first(where: { ev in
            ev.kind == .sell &&
            ev.symbol.normalizedBISTSymbol() == normalized &&
            ev.note.contains("TP1")
        }) {
            if let pct = parseTP1Pct(from: event.note) {
                return (pct, event.date)
            }
            return (strategy.settings.tp1Pct, event.date)
        }
        return (strategy.settings.tp1Pct, holding.tp1ExecutedAt)
    }

    private func parseTP1Pct(from note: String) -> Double? {
        guard let range = note.range(of: #"TP1\s*\+([0-9]+(?:\.[0-9]+)?)%"#, options: .regularExpression) else {
            return nil
        }
        let matched = String(note[range])
        guard let plus = matched.firstIndex(of: "+"),
              let percent = matched.firstIndex(of: "%"),
              plus < percent else {
            return nil
        }
        let number = matched[matched.index(after: plus)..<percent]
        return Double(number)
    }

    private func exitRuleChip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(color.opacity(0.25), lineWidth: 1))
    }

    private func daySectionCard(_ section: EventDaySection) -> some View {
        let isExpanded = expandedDayKeys.contains(section.dayKey)

        return VStack(alignment: .leading, spacing: 8) {
            Button {
                if isExpanded { expandedDayKeys.remove(section.dayKey) }
                else { expandedDayKeys.insert(section.dayKey) }
            } label: {
                HStack(spacing: 8) {
                    Text(section.day.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(TVTheme.text)

                    Text("\(section.events.count) hareket")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(TVTheme.subtext)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(TVTheme.surface2)
                        .clipShape(Capsule())

                    Spacer()

                    Text("Nakit \(formatTL(section.endCashTL))")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(TVTheme.subtext)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(TVTheme.subtext)
                }
            }
            .buttonStyle(.plain)

            Text("Gün sonu elde: \(section.holdingsText)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(TVTheme.subtext)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)

            if isExpanded {
                ForEach(Array(section.events.reversed())) { event in
                    eventRow(event)
                }
            }
        }
        .padding(10)
        .background(TVTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(TVTheme.stroke, lineWidth: 1)
        )
    }

    private func pendingActionRow(_ action: LiveStrategyPendingAction) -> some View {
        let actionColor: Color = action.kind == .buy ? TVTheme.up : Color(red: 0.88, green: 0.70, blue: 0.18)
        let actionText = action.kind == .buy ? "AL" : "SAT"
        let symbol = action.symbol.replacingOccurrences(of: ".IS", with: "")

        return HStack(alignment: .top, spacing: 8) {
            Text(action.createdAt.formatted(date: .omitted, time: .shortened))
                .font(.caption2)
                .foregroundStyle(TVTheme.subtext)
                .frame(width: 55, alignment: .leading)

            Text(actionText)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(actionColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(actionColor.opacity(0.15))
                .clipShape(Capsule())

            Text(symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(TVTheme.text)
                .frame(width: 58, alignment: .leading)

            Text(formatTL(action.amountTL))
                .font(.caption)
                .foregroundStyle(actionColor)

            Text(action.note)
                .font(.caption2)
                .foregroundStyle(TVTheme.subtext)
                .lineLimit(2)

            Spacer()

            HStack(spacing: 6) {
                Button {
                    strategy.approvePendingAction(action.id)
                } label: {
                    Text("Onayla")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(TVTheme.text)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(TVTheme.up)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    strategy.rejectPendingAction(action.id)
                } label: {
                    Text("Reddet")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(TVTheme.text)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(TVTheme.down)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(TVTheme.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func eventRow(_ event: LiveStrategyEvent) -> some View {
        let color: Color = {
            switch event.kind {
            case .buy: return TVTheme.up
            case .sell: return Color(red: 0.88, green: 0.70, blue: 0.18)
            case .skip: return TVTheme.subtext
            }
        }()

        let action: String = {
            switch event.kind {
            case .buy: return "AL"
            case .sell: return "SAT"
            case .skip: return "PAS"
            }
        }()

        return HStack(spacing: 8) {
            Text(event.date.formatted(date: .omitted, time: .shortened))
                .font(.caption2)
                .foregroundStyle(TVTheme.subtext)
                .frame(width: 55, alignment: .leading)

            Text(action)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color.opacity(0.15))
                .clipShape(Capsule())

            Text(event.symbol.replacingOccurrences(of: ".IS", with: ""))
                .font(.caption.weight(.semibold))
                .foregroundStyle(TVTheme.text)
                .frame(width: 58, alignment: .leading)

            Text(formatTL(event.amountTL))
                .font(.caption)
                .foregroundStyle(color)

            Text(event.note)
                .font(.caption2)
                .foregroundStyle(TVTheme.subtext)
                .lineLimit(6)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Text("Nakit \(formatTL(event.cashAfterTL))")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(TVTheme.subtext)
        }
        .padding(8)
        .background(TVTheme.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func stepperRow(
        title: String,
        valueText: String,
        decrement: @escaping () -> Void,
        increment: @escaping () -> Void
    ) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(TVTheme.text)
            Spacer()
            Text(valueText)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(TVTheme.subtext)
            HStack(spacing: 6) {
                Button(action: decrement) {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(TVTheme.text)
                        .frame(width: 24, height: 24)
                        .background(TVTheme.surface2)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                Button(action: increment) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(TVTheme.text)
                        .frame(width: 24, height: 24)
                        .background(TVTheme.surface2)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func sliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        format: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TVTheme.text)
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(TVTheme.subtext)
            }
            Slider(value: value, in: range, step: step)
                .tint(TVTheme.up)
        }
    }

    private func actionCapsule(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(TVTheme.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(color)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(TVTheme.stroke, lineWidth: 1))
    }

    private func statCell(_ title: String, _ value: String, color: Color = TVTheme.text) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(TVTheme.subtext)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(TVTheme.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var statusChip: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(strategy.isRunning ? TVTheme.up : TVTheme.subtext)
                .frame(width: 7, height: 7)
            Text(strategy.isRunning ? "Aktif" : "Durdu")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(TVTheme.text)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(TVTheme.surface2)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(TVTheme.stroke, lineWidth: 1))
    }

    private var indexBinding: Binding<IndexOption> {
        Binding(
            get: { strategy.settings.indexOption },
            set: { strategy.settings.indexOption = $0 }
        )
    }

    private var tp1Binding: Binding<Double> {
        Binding(
            get: { strategy.settings.tp1Pct },
            set: { strategy.settings.tp1Pct = $0 }
        )
    }

    private var tp2Binding: Binding<Double> {
        Binding(
            get: { strategy.settings.tp2Pct },
            set: { strategy.settings.tp2Pct = $0 }
        )
    }

    private var tp1SellBinding: Binding<Double> {
        Binding(
            get: { strategy.settings.tp1SellPercent },
            set: { strategy.settings.tp1SellPercent = $0 }
        )
    }

    private var presetBinding: Binding<TomorrowPreset> {
        Binding(
            get: { strategy.settings.preset },
            set: { strategy.settings.preset = $0 }
        )
    }

    private var slBinding: Binding<Double> {
        Binding(
            get: { strategy.settings.stopLossPct },
            set: { strategy.settings.stopLossPct = $0 }
        )
    }

    private func formatTL(_ value: Double) -> String {
        value.formatted(.currency(code: "TRY"))
    }

    private var startDateOptions: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<30).compactMap { offset in
            cal.date(byAdding: .day, value: -offset, to: today)
        }
    }

    private func dayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Bugün" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func nextAddOnHint(now: Date = Date()) -> String {
        guard strategy.isRunning else { return "Strateji duruyor" }
        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)
        if hour >= 18 {
            let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
            let run = cal.date(bySettingHour: 17, minute: 0, second: 0, of: tomorrow) ?? tomorrow
            return run.formatted(date: .abbreviated, time: .shortened)
        }
        if hour < 17 {
            let today17 = cal.date(bySettingHour: 17, minute: 0, second: 0, of: now) ?? now
            return today17.formatted(date: .abbreviated, time: .shortened)
        }
        return "Şimdi (17:00-18:00)"
    }
}

private struct EventDaySection: Identifiable {
    let day: Date
    let events: [LiveStrategyEvent]
    let endCashTL: Double
    let holdingsText: String

    var dayKey: TimeInterval { day.timeIntervalSinceReferenceDate }
    var id: TimeInterval { dayKey }
}

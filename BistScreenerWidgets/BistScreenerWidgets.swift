import WidgetKit
import SwiftUI

private struct PortfolioEntry: TimelineEntry {
    let date: Date
    let snapshot: PortfolioWidgetSnapshot
}

private struct StrategyEntry: TimelineEntry {
    let date: Date
    let snapshot: StrategyWidgetSnapshot
}

private struct PortfolioProvider: TimelineProvider {
    func placeholder(in context: Context) -> PortfolioEntry {
        PortfolioEntry(date: Date(), snapshot: .init(totalTRY: 0, totalPnLTRY: 0, totalPnLPct: 0, assetCount: 0, updatedAt: Date()))
    }

    func getSnapshot(in context: Context, completion: @escaping (PortfolioEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PortfolioEntry>) -> Void) {
        let entry = loadEntry()
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func loadEntry() -> PortfolioEntry {
        let defaults = widgetDefaults()
        let snapshot = (defaults.data(forKey: WidgetSharedKeys.portfolioSnapshot))
            .flatMap { try? JSONDecoder().decode(PortfolioWidgetSnapshot.self, from: $0) }
            ?? PortfolioWidgetSnapshot(totalTRY: 0, totalPnLTRY: 0, totalPnLPct: 0, assetCount: 0, updatedAt: Date())
        return PortfolioEntry(date: Date(), snapshot: snapshot)
    }
}

private struct StrategyProvider: TimelineProvider {
    func placeholder(in context: Context) -> StrategyEntry {
        StrategyEntry(date: Date(), snapshot: .init(isRunning: false, pendingCount: 0, holdingsCount: 0, equityTL: 0, cashTL: 0, updatedAt: Date()))
    }

    func getSnapshot(in context: Context, completion: @escaping (StrategyEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StrategyEntry>) -> Void) {
        let entry = loadEntry()
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func loadEntry() -> StrategyEntry {
        let defaults = widgetDefaults()
        let snapshot = (defaults.data(forKey: WidgetSharedKeys.strategySnapshot))
            .flatMap { try? JSONDecoder().decode(StrategyWidgetSnapshot.self, from: $0) }
            ?? StrategyWidgetSnapshot(isRunning: false, pendingCount: 0, holdingsCount: 0, equityTL: 0, cashTL: 0, updatedAt: Date())
        return StrategyEntry(date: Date(), snapshot: snapshot)
    }
}

private struct PortfolioWidgetView: View {
    let entry: PortfolioEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Portföyüm")
                .font(.headline)
            Text(currency(entry.snapshot.totalTRY))
                .font(.title3.bold())
            Text("K/Z: \(currency(entry.snapshot.totalPnLTRY)) (\(percent(entry.snapshot.totalPnLPct)))")
                .font(.caption)
                .foregroundStyle(entry.snapshot.totalPnLTRY >= 0 ? .green : .red)
            Text("Varlık: \(entry.snapshot.assetCount)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "bistscreener://profile/assets"))
    }

    private func currency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "TRY"
        formatter.locale = Locale(identifier: "tr_TR")
        return formatter.string(from: NSNumber(value: value)) ?? "₺0"
    }

    private func percent(_ value: Double) -> String {
        String(format: "%+.2f%%", value)
    }
}

private struct StrategyWidgetView: View {
    let entry: StrategyEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Stratejim")
                .font(.headline)
            Text(entry.snapshot.isRunning ? "Aktif" : "Pasif")
                .font(.caption)
                .foregroundStyle(entry.snapshot.isRunning ? .green : .secondary)
            Text("Onay: \(entry.snapshot.pendingCount)")
                .font(.caption)
            Text("Pozisyon: \(entry.snapshot.holdingsCount)")
                .font(.caption)
            Text("Özkaynak: \(currency(entry.snapshot.equityTL))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "bistscreener://profile/strategy"))
    }

    private func currency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "TRY"
        formatter.locale = Locale(identifier: "tr_TR")
        return formatter.string(from: NSNumber(value: value)) ?? "₺0"
    }
}

struct PortfolioWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PortfolioWidget", provider: PortfolioProvider()) { entry in
            PortfolioWidgetView(entry: entry)
        }
        .configurationDisplayName("Portföyüm")
        .description("Toplam portföy ve kâr/zarar özeti")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct StrategyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StrategyWidget", provider: StrategyProvider()) { entry in
            StrategyWidgetView(entry: entry)
        }
        .configurationDisplayName("Stratejim")
        .description("Canlı strateji durum ve onay özeti")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct BistScreenerWidgetBundle: WidgetBundle {
    var body: some Widget {
        PortfolioWidget()
        StrategyWidget()
    }
}

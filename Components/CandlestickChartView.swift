//
//  CandlestickChartView.swift
//  BistScreener
//
//  Created by Sedat Pala on 18.02.2026.
//
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct CandlestickChartView: View {
    let candles: [Candle]
    @Binding var selected: Candle?

    @State private var lastSelectedDateForHaptic: Date?

    /// ✅ true: yatay scroll yok, ekrana sığacak kadar son mum gösterilir
    let fitToWidth: Bool

    // Görsel ayarlar (fit modunda barWidth dinamik hesaplanır)
    private let minBarWidth: CGFloat = 6
    private let maxBarWidth: CGFloat = 14
    @State private var zoomScale: CGFloat = 1.0
    private let barSpacing: CGFloat = 4
    private let horizontalPadding: CGFloat = 12
    private let axisHeight: CGFloat = 28

    private var selectedDate: Date? { selected?.date }

    init(candles: [Candle], selected: Binding<Candle?>, fitToWidth: Bool = true) {
        self.candles = candles
        self._selected = selected
        self.fitToWidth = fitToWidth
    }

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let chartHeight = max(0, height - axisHeight)

            // ✅ Fit modunda: ekrana sığacak kadar son N mum
            let visible = fitToWidth ? visibleCandles(for: geo.size.width) : candles

            let (minL, maxH) = minMaxLowHigh(from: visible)
            let span = max(maxH - minL, 0.000001)

            let y: (Double) -> CGFloat = { price in
                let p = (price - minL) / span
                return chartHeight - CGFloat(p) * chartHeight
            }

            if fitToWidth {
                // ✅ Scroll yok → ekrana sığdır
                let bw = computedBarWidth(for: geo.size.width, count: visible.count)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: barSpacing) {
                        ForEach(visible.indices, id: \.self) { i in
                            let c = visible[i]
                            let isSel = (selectedDate == c.date)

                            CandleStickBar(candle: c, y: y, isSelected: isSel)
                                .frame(width: bw, height: chartHeight)
                                .contentShape(Rectangle())
                                .onTapGesture { updateSelection(c) }
                                .onLongPressGesture(minimumDuration: 0.12) { updateSelection(c) }
                        }
                    }

                    HStack(spacing: barSpacing) {
                        ForEach(visible.indices, id: \.self) { i in
                            let date = visible[i].date
                            let label = axisLabel(at: i, in: visible)
                            let isSel = (selectedDate == date)

                            AxisCell(label: label, isSelected: isSel)
                                .frame(width: bw, height: axisHeight)
                        }
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard !visible.isEmpty else { return }
                            let unit = bw + barSpacing
                            let localX = max(0, min(value.location.x - horizontalPadding, CGFloat(visible.count) * unit))
                            let idx = min(max(Int(localX / max(unit, 0.1)), 0), visible.count - 1)
                            updateSelection(visible[idx])
                        }
                )

            } else {
                // TradingView-benzeri: yatay scroll + pinch zoom
                let zoomedWidth = min(max(12 * zoomScale, minBarWidth), 28)

                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 4) {
                            LazyHStack(spacing: barSpacing) {
                                ForEach(candles.indices, id: \.self) { i in
                                    let c = candles[i]
                                    let isSel = (selectedDate == c.date)

                                    CandleStickBar(candle: c, y: y, isSelected: isSel)
                                        .frame(width: zoomedWidth, height: chartHeight)
                                        .contentShape(Rectangle())
                                        .onTapGesture { updateSelection(c) }
                                        .onLongPressGesture(minimumDuration: 0.12) { updateSelection(c) }
                                        .id("candle-\(i)")
                                }
                            }

                            LazyHStack(spacing: barSpacing) {
                                ForEach(candles.indices, id: \.self) { i in
                                    let date = candles[i].date
                                    let label = axisLabel(at: i, in: candles)
                                    let isSel = (selectedDate == date)

                                    AxisCell(label: label, isSelected: isSel)
                                        .frame(width: zoomedWidth, height: axisHeight)
                                }
                            }
                        }
                        .padding(.horizontal, horizontalPadding)
                        .padding(.vertical, 4)
                    }
                    .onAppear {
                        scrollToLatest(proxy)
                    }
                    .onChange(of: candles.count) { _ in
                        scrollToLatest(proxy)
                    }
                    .onChange(of: selectedDate) { _ in
                        if let idx = candles.firstIndex(where: { $0.date == selectedDate }) {
                            DispatchQueue.main.async {
                                proxy.scrollTo("candle-\(idx)", anchor: .center)
                            }
                        } else {
                            scrollToLatest(proxy)
                        }
                    }
                }
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            zoomScale = min(max(value, 0.7), 2.4)
                        }
                )
            }
        }
        .overlay(alignment: .topLeading) {
            if let s = selected {
                HStack(spacing: 8) {
                    Text(s.date.formatted(date: .abbreviated, time: .omitted))
                    Text(String(format: "O %.2f", s.open))
                    Text(String(format: "H %.2f", s.high))
                    Text(String(format: "L %.2f", s.low))
                    Text(String(format: "C %.2f", s.close))
                    if !fitToWidth { Text(String(format: "x%.1f", zoomScale)) }
                }
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .padding(.top, 4)
                .padding(.leading, 8)
            }
        }
        .overlay(alignment: .bottom) {
            if let s = selected {
                Text("Seçili Gün: \(s.date.formatted(date: .complete, time: .omitted))")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(.bottom, 2)
            }
        }
        .onAppear {
            if selected == nil { selected = candles.last }
        }
    }

    private func updateSelection(_ candle: Candle) {
        selected = candle
        triggerSelectionHapticIfNeeded(for: candle)
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy) {
        guard let lastIdx = candles.indices.last else { return }
        DispatchQueue.main.async {
            proxy.scrollTo("candle-\(lastIdx)", anchor: .trailing)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            proxy.scrollTo("candle-\(lastIdx)", anchor: .trailing)
        }
    }

    private func triggerSelectionHapticIfNeeded(for candle: Candle) {
        guard lastSelectedDateForHaptic != candle.date else { return }
        lastSelectedDateForHaptic = candle.date
#if canImport(UIKit)
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
#endif
    }

    // MARK: - Fit helpers

    private func visibleCandles(for width: CGFloat) -> [Candle] {
        guard !candles.isEmpty else { return [] }

        let usable = max(0, width - 2 * horizontalPadding)
        // Bir mumun minimum kapladığı alan
        let unit = minBarWidth + barSpacing
        let maxCount = Int(usable / unit)

        // Çok az/çok fazla olmasın diye clamp
        let clamped = min(max(maxCount, 25), 60)

        return Array(candles.suffix(clamped))
    }

    private func computedBarWidth(for width: CGFloat, count: Int) -> CGFloat {
        guard count > 0 else { return minBarWidth }
        let usable = max(0, width - 2 * horizontalPadding)
        let totalSpacing = CGFloat(max(0, count - 1)) * barSpacing
        let w = (usable - totalSpacing) / CGFloat(count)
        return min(max(w, minBarWidth), maxBarWidth)
    }

    // MARK: - Axis labeling

    private func axisLabel(at index: Int, in list: [Candle]) -> String {
        guard !list.isEmpty else { return "" }
        let count = list.count
        let interval = max(1, count / 8)

        let d = list[index].date
        let cal = Calendar.current

        let isFirst = index == 0
        let isLast  = index == count - 1

        var isMonthBoundary = false
        if !isFirst {
            let prev = list[index - 1].date
            isMonthBoundary = cal.component(.month, from: prev) != cal.component(.month, from: d)
        }

        if isFirst || isMonthBoundary {
            return Self.monthFormatter.string(from: d)
        }
        if isLast || (index % interval == 0) {
            return Self.dayFormatter.string(from: d)
        }
        return ""
    }

    private func minMaxLowHigh(from candles: [Candle]) -> (Double, Double) {
        guard let first = candles.first else { return (0, 1) }
        var minL = first.low
        var maxH = first.high
        for c in candles {
            if c.low < minL { minL = c.low }
            if c.high > maxH { maxH = c.high }
        }
        return (minL, maxH)
    }

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "MMM"
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d"
        return f
    }()
}

// MARK: - Candle Bar

private struct CandleStickBar: View {
    let candle: Candle
    let y: (Double) -> CGFloat
    let isSelected: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let midX = w / 2

            let yHigh = y(candle.high)
            let yLow  = y(candle.low)
            let yOpen = y(candle.open)
            let yClose = y(candle.close)

            let isBull = candle.close >= candle.open

            let wickTop = min(yHigh, yLow)
            let wickBottom = max(yHigh, yLow)
            let wickH = max(wickBottom - wickTop, 1)

            let bodyTop = min(yOpen, yClose)
            let bodyBottom = max(yOpen, yClose)
            let bodyH = max(bodyBottom - bodyTop, 1)

            ZStack {
                Rectangle()
                    .fill(.secondary)
                    .frame(width: 1, height: wickH)
                    .position(x: midX, y: wickTop + wickH / 2)

                RoundedRectangle(cornerRadius: 2)
                    .fill(isBull ? Color.green : Color.red)
                    .frame(width: w, height: bodyH)
                    .position(x: midX, y: bodyTop + bodyH / 2)

                if isSelected {
                    Rectangle()
                        .fill(Color.primary.opacity(0.35))
                        .frame(width: 1, height: geo.size.height)
                        .position(x: midX, y: geo.size.height / 2)

                    Circle()
                        .fill(Color.primary)
                        .frame(width: 5, height: 5)
                        .position(x: midX, y: geo.size.height - 6)
                }
            }
        }
    }
}

// MARK: - Axis Cell

private struct AxisCell: View {
    let label: String
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 2) {
            Rectangle()
                .fill(.secondary.opacity(0.8))
                .frame(width: 1, height: 5)

            Text(label)
                .font(.caption2)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

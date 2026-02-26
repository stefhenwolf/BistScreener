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
    @State private var verticalPan: CGFloat = 0
    @State private var horizontalBarOffset: Int = 0 // 0 = en güncel sağ taraf
    @State private var dragStartHorizontalOffset: Int?
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
            // ✅ Non-fit modunda: manuel pencere (TradingView benzeri pan/zoom)
            let visible = fitToWidth ? visibleCandles(for: geo.size.width) : windowCandles(for: geo.size.width)

            let (rawMinL, rawMaxH) = minMaxLowHigh(from: visible)
            let rawSpan = max(rawMaxH - rawMinL, 0.000001)
            let pad = rawSpan * 0.12   // üst/alt nefes payı (TV benzeri)
            let minL = rawMinL - pad
            let maxH = rawMaxH + pad
            let span = max(maxH - minL, 0.000001)

            let y: (Double) -> CGFloat = { price in
                let p = (price - minL) / span
                let base = chartHeight - CGFloat(p) * chartHeight
                let clampedPan = min(max(verticalPan, -chartHeight * 0.35), chartHeight * 0.35)
                return base + clampedPan
            }

            let selectedVisible = visible.first { $0.date == selectedDate }
            let selectedY = selectedVisible.map { y($0.close) }

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
                .overlay {
                    if let sy = selectedY {
                        Rectangle()
                            .fill(Color.white.opacity(0.18))
                            .frame(height: 1)
                            .offset(y: sy - chartHeight / 2)
                    }
                }

            } else {
                // TradingView-benzeri manuel pencere: kusursuz yatay pan + pinch zoom
                let zoomedWidth = min(max(12 * zoomScale, minBarWidth), 28)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: barSpacing) {
                        ForEach(visible.indices, id: \.self) { i in
                            let c = visible[i]
                            let isSel = (selectedDate == c.date)

                            CandleStickBar(candle: c, y: y, isSelected: isSel)
                                .frame(width: zoomedWidth, height: chartHeight)
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
                                .frame(width: zoomedWidth, height: axisHeight)
                        }
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { value in
                            if abs(value.translation.width) >= abs(value.translation.height) {
                                let unit = max(zoomedWidth + barSpacing, 1)
                                let deltaBars = Int((value.translation.width / unit).rounded())
                                if dragStartHorizontalOffset == nil {
                                    dragStartHorizontalOffset = horizontalBarOffset
                                }
                                let start = dragStartHorizontalOffset ?? horizontalBarOffset
                                horizontalBarOffset = clampedHorizontalOffset(start + deltaBars, width: geo.size.width)
                            } else {
                                verticalPan = value.translation.height
                            }
                        }
                        .onEnded { value in
                            if abs(value.translation.width) >= abs(value.translation.height) {
                                let unit = max(zoomedWidth + barSpacing, 1)
                                let projectedBars = Int((value.predictedEndTranslation.width / unit).rounded())
                                let start = dragStartHorizontalOffset ?? horizontalBarOffset
                                // Soft-Balanced momentum: projected hareketin tamamını değil bir kısmını uygula
                                let softenedBars = Int((Double(projectedBars) * 0.65).rounded())
                                withAnimation(.interpolatingSpring(stiffness: 170, damping: 28)) {
                                    horizontalBarOffset = clampedHorizontalOffset(start + softenedBars, width: geo.size.width)
                                }
                            } else {
                                // Dikey pan: daha yumuşak ve kontrollü
                                let projected = value.predictedEndTranslation.height * 0.55
                                withAnimation(.interpolatingSpring(stiffness: 165, damping: 30)) {
                                    verticalPan = min(max(projected, -chartHeight * 0.35), chartHeight * 0.35)
                                }
                            }
                            dragStartHorizontalOffset = nil
                        }
                )
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            // Zoom kontrollü: ani sıçramayı azalt
                            let clamped = min(max(value, 0.75), 2.2)
                            zoomScale = (zoomScale * 0.82) + (clamped * 0.18)
                            zoomScale = min(max(zoomScale, 0.75), 2.2)
                            horizontalBarOffset = clampedHorizontalOffset(horizontalBarOffset, width: geo.size.width)
                        }
                )
                .onAppear {
                    horizontalBarOffset = 0 // her açılışta en güncel sağdan başla
                }
                .onChange(of: candles.count) { _ in
                    horizontalBarOffset = 0
                }
                .overlay {
                    if let sy = selectedY {
                        Rectangle()
                            .fill(Color.white.opacity(0.18))
                            .frame(height: 1)
                            .offset(y: sy - chartHeight / 2)
                    }
                }
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
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .padding(.top, 4)
                .padding(.leading, 8)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let s = selected {
                Text(String(format: "C %.2f", s.close))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(TVTheme.text)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(TVTheme.surface)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(TVTheme.stroke, lineWidth: 1))
                    .padding(.trailing, 6)
                    .padding(.top, 6)
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
        .onTapGesture(count: 2) {
            verticalPan = 0
        }
        .onAppear {
            if selected == nil { selected = candles.last }
        }
    }

    private func updateSelection(_ candle: Candle) {
        selected = candle
        triggerSelectionHapticIfNeeded(for: candle)
    }

    private func windowCandles(for width: CGFloat) -> [Candle] {
        guard !candles.isEmpty else { return [] }
        let zoomedWidth = min(max(12 * zoomScale, minBarWidth), 28)
        let unit = max(zoomedWidth + barSpacing, 1)
        let usable = max(0, width - 2 * horizontalPadding)
        let visibleCount = max(20, Int(usable / unit))

        let offset = clampedHorizontalOffset(horizontalBarOffset, width: width)
        let endExclusive = max(0, candles.count - offset)
        let start = max(0, endExclusive - visibleCount)
        guard start < endExclusive else { return [candles.last!]} 
        return Array(candles[start..<endExclusive])
    }

    private func clampedHorizontalOffset(_ value: Int, width: CGFloat) -> Int {
        guard !candles.isEmpty else { return 0 }
        let zoomedWidth = min(max(12 * zoomScale, minBarWidth), 28)
        let unit = max(zoomedWidth + barSpacing, 1)
        let usable = max(0, width - 2 * horizontalPadding)
        let visibleCount = max(20, Int(usable / unit))
        let maxOffset = max(0, candles.count - visibleCount)
        return min(max(value, 0), maxOffset)
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

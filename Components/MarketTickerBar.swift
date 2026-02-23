import SwiftUI
import UIKit

struct MarketTickerBar: View {
    @ObservedObject var vm: MarketTickerViewModel

    var body: some View {
        let attributed = buildAttributedTicker(items: vm.items, errorText: vm.errorText, isLoading: vm.isLoading)

        MarqueeUIKitText(attributedText: attributed, speed: 38)
            .frame(height: 40)
            .padding(.horizontal, 12)

            // ✅ TV surface (thinMaterial yerine)
            .background(TVTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(TVTheme.stroke, lineWidth: 1)
                    .allowsHitTesting(false)
            )

            .padding(.horizontal, DS.s16)
            .padding(.top, 6)
            .padding(.bottom, 2)

            // ✅ Fade mask (aynı kalsın)
            .compositingGroup()
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.00),
                        .init(color: .black, location: 0.08),
                        .init(color: .black, location: 0.92),
                        .init(color: .clear, location: 1.00)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .onAppear {
                vm.start()
                vm.refreshNow()
            }
            .onTapGesture {
                vm.refreshNow()
            }
    }

    private func buildAttributedTicker(items: [MarketTickerItem], errorText: String?, isLoading: Bool) -> NSAttributedString {
        let font = UIFont.preferredFont(forTextStyle: .footnote)

        // ✅ Base rengi TVTheme.text
        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor(TVTheme.text)
        ]

        func pctAttrs(_ pct: Double) -> [NSAttributedString.Key: Any] {
            let c: UIColor
            if pct > 0 { c = UIColor(TVTheme.up) }
            else if pct < 0 { c = UIColor(TVTheme.down) }
            else { c = UIColor(TVTheme.subtext) }
            return [.font: font, .foregroundColor: c]
        }

        let result = NSMutableAttributedString(string: "", attributes: baseAttrs)

        // ✅ BOŞKEN: error/loading
        if items.isEmpty {
            let msg: String
            if let e = errorText, !e.isEmpty {
                msg = "Piyasa verisi alınamadı: \(e)   •   Dokun → Yenile   •   "
            } else if isLoading {
                msg = "Piyasa verileri yükleniyor…   •   "
            } else {
                msg = "Piyasa verisi bekleniyor…   •   Dokun → Yenile   •   "
            }
            result.append(NSAttributedString(string: msg, attributes: baseAttrs))
            return result
        }

        for (idx, it) in items.enumerated() {
            if idx > 0 {
                result.append(NSAttributedString(string: "   •   ", attributes: [
                    .font: font,
                    .foregroundColor: UIColor(TVTheme.subtext)
                ]))
            }

            // ✅ Title + value
            result.append(NSAttributedString(string: "\(it.title) \(it.valueText)", attributes: baseAttrs))

            // ✅ Percent colored
            if let pct = it.changePct {
                let pctText = String(format: " (%+.2f%%)", pct)
                result.append(NSAttributedString(string: pctText, attributes: pctAttrs(pct)))
            }
        }

        result.append(NSAttributedString(string: "   •   ", attributes: [
            .font: font,
            .foregroundColor: UIColor(TVTheme.subtext)
        ]))
        return result
    }
}

// MARK: - UIKit Marquee

private struct MarqueeUIKitText: UIViewRepresentable {
    let attributedText: NSAttributedString
    let speed: CGFloat

    func makeUIView(context: Context) -> MarqueeView {
        let v = MarqueeView()
        v.speed = speed
        v.setAttributedText(attributedText)
        return v
    }

    func updateUIView(_ uiView: MarqueeView, context: Context) {
        uiView.speed = speed
        uiView.setAttributedText(attributedText)
    }
}

private final class MarqueeView: UIView {
    var speed: CGFloat = 38

    private let label1 = UILabel()
    private let label2 = UILabel()

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var lastKey: String = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    deinit { stop() }

    private func setup() {
        clipsToBounds = true
        backgroundColor = .clear

        [label1, label2].forEach { lbl in
            lbl.numberOfLines = 1
            lbl.lineBreakMode = .byClipping
            lbl.textAlignment = .left
            lbl.adjustsFontForContentSizeCategory = true
            lbl.backgroundColor = .clear
            addSubview(lbl)
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { start() } else { stop() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 else { return }
        centerLabelsVertically()
    }

    func setAttributedText(_ attr: NSAttributedString) {
        // ✅ içerik değişmediyse yeniden ölçme yok
        let key = "\(attr.string)#\(attr.length)"
        guard key != lastKey else { return }
        lastKey = key

        label1.attributedText = attr
        label2.attributedText = attr

        label1.sizeToFit()
        label2.sizeToFit()

        let w1 = label1.bounds.width
        label1.frame.origin.x = 0
        label2.frame.origin.x = w1

        if bounds.width > 0, w1 < bounds.width {
            label2.frame.origin.x = max(bounds.width, w1)
        }

        centerLabelsVertically()
        setNeedsLayout()
        layoutIfNeeded()
    }

    private func centerLabelsVertically() {
        let h = bounds.height
        label1.frame.origin.y = max(0, (h - label1.bounds.height) / 2)
        label2.frame.origin.y = max(0, (h - label2.bounds.height) / 2)
    }

    private func start() {
        if displayLink != nil { return }
        lastTimestamp = 0
        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stop() {
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = 0
    }

    @objc private func step(_ link: CADisplayLink) {
        if lastTimestamp == 0 {
            lastTimestamp = link.timestamp
            return
        }
        let dt = link.timestamp - lastTimestamp
        lastTimestamp = link.timestamp

        let dx = speed * CGFloat(dt)
        label1.frame.origin.x -= dx
        label2.frame.origin.x -= dx

        if label1.frame.maxX <= 0 { label1.frame.origin.x = label2.frame.maxX }
        if label2.frame.maxX <= 0 { label2.frame.origin.x = label1.frame.maxX }
    }
}

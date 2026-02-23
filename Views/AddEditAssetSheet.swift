import SwiftUI

struct AddEditAssetSheet: View {

    let asset: Asset?
    let onSave: (Asset) -> Void
    let onDelete: ((Asset) -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var type: AssetType = .stock

    @State private var useManualSymbol: Bool = false
    @State private var presetID: String = ""

    @State private var name: String = ""
    @State private var symbol: String = ""

    @State private var quantityText: String = ""
    @State private var avgCostText: String = ""

    @State private var quantityStep: Double = 1

    @State private var alert: AlertInfo?
    @State private var showDeleteConfirm = false

    struct AlertInfo: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    // MARK: - Presets

    struct Preset: Identifiable, Hashable {
        let id: String
        let title: String
        let symbol: String
        let defaultName: String
        let hint: String

        init(title: String, symbol: String, defaultName: String, hint: String) {
            self.id = symbol.isEmpty ? title : symbol
            self.title = title
            self.symbol = symbol
            self.defaultName = defaultName
            self.hint = hint
        }
    }

    private var presetsForType: [Preset] {
        switch type {
        case .metal:
            return [
                .init(title: "Altın", symbol: "XAUUSD=X", defaultName: "Altın", hint: "Gram bazında takip edilir."),
                .init(title: "Gümüş", symbol: "XAGUSD=X", defaultName: "Gümüş", hint: "Gram bazında takip edilir.")
            ]
        case .fx:
            return [
                .init(title: "USD/TRY", symbol: "USDTRY=X", defaultName: "USD/TRY", hint: "TRY birimi varsayılır."),
                .init(title: "EUR/TRY", symbol: "EURTRY=X", defaultName: "EUR/TRY", hint: "TRY birimi varsayılır.")
            ]
        case .crypto:
            return [
                .init(title: "Bitcoin", symbol: "BTC-USD", defaultName: "Bitcoin", hint: "USD fiyat → TRY’ye çevrilir."),
                .init(title: "Ethereum", symbol: "ETH-USD", defaultName: "Ethereum", hint: "USD fiyat → TRY’ye çevrilir.")
            ]
        case .stock:
            return [
                .init(title: "BIST Hisse (manual)", symbol: "", defaultName: "", hint: "BIST hisselerinde .IS kullan. Örn: THYAO.IS")
            ]
        case .fund:
            return [
                .init(title: "Fon (manual)", symbol: "", defaultName: "", hint: "Fonlar için Yahoo sembolünü manuel gir.")
            ]
        }
    }

    private var selectedPreset: Preset? {
        presetsForType.first(where: { $0.id == presetID })
    }

    private var presetHint: String {
        if let p = selectedPreset, !p.hint.isEmpty { return p.hint }
        switch type {
        case .metal:  return "Miktar: gram. Fiyat USD/ons gelir, TRY/gram’a çevrilir."
        case .fx:     return "Örn: USDTRY=X"
        case .crypto: return "Örn: BTC-USD"
        case .stock:  return "Örn: THYAO.IS"
        case .fund:   return "Fon sembolünü Yahoo formatında gir."
        }
    }

    private var qty: Double? { parseDoubleTR(quantityText) }

    private var avgCost: Double? {
        let t = avgCostText.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        return parseDoubleTR(t)
    }

    private var quantityPlaceholder: String {
        switch type {
        case .metal:  return "Miktar (gram)"
        case .stock:  return "Miktar (lot/adet)"
        case .fund:   return "Miktar (adet)"
        case .fx:     return "Miktar"
        case .crypto: return "Miktar"
        }
    }

    private var avgCostPlaceholder: String {
        switch type {
        case .metal:  return "Ortalama maliyet (₺/gram) (opsiyonel)"
        default:      return "Ortalama maliyet (TRY) (opsiyonel)"
        }
    }

    private var canSave: Bool {
        let sym = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        let nameOk = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let symOk = !sym.isEmpty
        let qtyOk = (qty ?? 0) > 0

        let presetNameOk = !(selectedPreset?.defaultName.isEmpty ?? true)
        let effectiveNameOk = nameOk || presetNameOk

        return effectiveNameOk && symOk && qtyOk
    }

    init(
        asset: Asset?,
        onSave: @escaping (Asset) -> Void,
        onDelete: ((Asset) -> Void)? = nil
    ) {
        self.asset = asset
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            ZStack {
                TVTheme.bg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: DS.s12) {

                        headerCard

                        TVCard { typeCard }
                        TVCard { presetCard }
                        TVCard { detailsCard }

                        if asset != nil {
                            TVCard { deleteCard }
                        }

                        Spacer(minLength: 12)
                    }
                    .padding(.horizontal, DS.s16)
                    .padding(.top, DS.s12)
                    .padding(.bottom, 90) // bottom bar alanı
                }
                .safeAreaInset(edge: .bottom) {
                    bottomBar
                }
            }
            .navigationTitle(asset == nil ? "Varlık Ekle" : "Varlık Düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(TVTheme.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Kapat") { dismiss() }
                        .foregroundStyle(TVTheme.text)
                }
            }
            .onAppear {
                seedFromAssetIfEditing()
                applyPresetIfNeeded()
            }
            .alert(item: $alert) { a in
                Alert(title: Text(a.title), message: Text(a.message), dismissButton: .default(Text("Tamam")))
            }
            .confirmationDialog(
                "Varlığı portföyden kaldır?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Sil", role: .destructive) {
                    guard let a = asset else { return }
                    onDelete?(a)
                    dismiss()
                }
                Button("Vazgeç", role: .cancel) {}
            } message: {
                Text("Bu işlem geri alınamaz.")
            }
            .tvNavStyle()   
        }
        .presentationDetents([.large])
        .tvNavStyle()
    }

    // MARK: - UI blocks

    private var headerCard: some View {
        TVCard {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(asset == nil ? "Yeni varlık ekle" : "Varlığı düzenle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(TVTheme.text)
                    Text(presetHint)
                        .font(.footnote)
                        .foregroundStyle(TVTheme.subtext)
                        .lineLimit(2)
                }
                Spacer()
                if let a = asset {
                    TVChip(a.type.title, systemImage: "tag")
                } else {
                    TVChip("Portföy", systemImage: "tray.full")
                }
            }
        }
    }

    private var typeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tür")
                .font(.caption)
                .foregroundStyle(TVTheme.subtext)

            Picker("Tür", selection: $type) {
                ForEach(AssetType.allCases, id: \.self) { t in
                    Text(t.title).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: type) {
                resetForTypeChange()
                applyPresetIfNeeded()
            }
        }
    }

    private var presetCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Hazır Liste")
                    .font(.caption)
                    .foregroundStyle(TVTheme.subtext)
                Spacer()
                Toggle("Manuel", isOn: $useManualSymbol)
                    .labelsHidden()
            }

            Picker("Hazır Liste", selection: $presetID) {
                Text("Seç").tag("")
                ForEach(presetsForType) { p in
                    Text(p.title).tag(p.id)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: presetID) {
                applyPresetIfNeeded()
            }

            Text("Not: Manuel kapalıyken preset sembolü kilitler.")
                .font(.caption2)
                .foregroundStyle(TVTheme.subtext)
        }
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 12) {

            Text("Detaylar")
                .font(.caption)
                .foregroundStyle(TVTheme.subtext)

            TextField("İsim", text: $name)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)

            TextField("Sembol", text: $symbol)
                .textInputAutocapitalization(.characters)
                .keyboardType(.asciiCapable)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .disabled(!useManualSymbol && !(selectedPreset?.symbol.isEmpty ?? true) && !presetID.isEmpty)

            quantityEditor

            TextField(avgCostPlaceholder, text: $avgCostText)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)

            Text(exampleLine())
                .font(.caption2)
                .foregroundStyle(TVTheme.subtext)
        }
    }

    private var deleteCard: some View {
        Button(role: .destructive) {
            showDeleteConfirm = true
        } label: {
            HStack {
                Image(systemName: "trash")
                Text("Portföyden Kaldır")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(TVTheme.subtext)
            }
            .foregroundStyle(.red)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .disabled(onDelete == nil)
        .opacity(onDelete == nil ? 0.5 : 1)
    }

    private var quantityEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(quantityPlaceholder)
                .font(.caption)
                .foregroundStyle(TVTheme.subtext)

            HStack(spacing: 10) {
                Button { adjustQuantity(by: -quantityStep) } label: {
                    Image(systemName: "minus.circle.fill").font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(TVTheme.text)

                TextField(quantityPlaceholder, text: $quantityText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)

                Button { adjustQuantity(by: quantityStep) } label: {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(TVTheme.text)

                Menu {
                    Button("0,1") { quantityStep = 0.1 }
                    Button("1") { quantityStep = 1 }
                    Button("10") { quantityStep = 10 }
                } label: {
                    TVChip("Adım \(fmtStep(quantityStep))", systemImage: "dial.low")
                }
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {

                if asset != nil {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "trash")
                            Text("Sil")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(onDelete == nil)
                }

                Button {
                    save()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: asset == nil ? "plus.circle.fill" : "checkmark.circle.fill")
                        Text(asset == nil ? "Ekle" : "Kaydet")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(TVTheme.up)
                .disabled(!canSave)
            }
        }
        .padding(.horizontal, DS.s16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(TVTheme.bg)
        .overlay(
            Rectangle()
                .fill(TVTheme.stroke.opacity(0.6))
                .frame(height: 1)
                .allowsHitTesting(false),
            alignment: .top
        )
    }

    // MARK: - Logic

    private func seedFromAssetIfEditing() {
        guard let a = asset else {
            type = .stock
            useManualSymbol = false
            presetID = ""
            name = ""
            symbol = ""
            quantityText = ""
            avgCostText = ""
            quantityStep = 1
            return
        }

        type = a.type
        useManualSymbol = true
        presetID = ""

        name = a.name
        symbol = a.symbol
        quantityText = fmtTR(a.quantity)
        avgCostText = a.avgCostTRY.map(fmtTR) ?? ""
        quantityStep = 1
    }

    private func resetForTypeChange() {
        if asset != nil { return }
        presetID = ""
        useManualSymbol = false
        name = ""
        symbol = ""
        quantityText = ""
        avgCostText = ""
    }

    private func applyPresetIfNeeded() {
        guard asset == nil else { return }

        guard let p = selectedPreset, !presetID.isEmpty else {
            useManualSymbol = true
            return
        }

        if p.symbol.isEmpty {
            useManualSymbol = true
            symbol = ""
        } else {
            useManualSymbol = false
            symbol = p.symbol
        }

        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !p.defaultName.isEmpty {
            name = p.defaultName
        }
    }

    private func save() {
        let sym = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let nm = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = nm.isEmpty ? (selectedPreset?.defaultName ?? "") : nm

        guard !finalName.isEmpty else {
            alert = .init(title: "Eksik bilgi", message: "İsim boş olamaz.")
            return
        }
        guard !sym.isEmpty else {
            alert = .init(title: "Eksik bilgi", message: "Sembol boş olamaz.")
            return
        }
        guard let q = qty else {
            alert = .init(title: "Eksik bilgi", message: "Miktar sayısal olmalı.")
            return
        }

        // edit modunda 0 -> sil
        if q <= 0 {
            if asset != nil {
                showDeleteConfirm = true
                return
            }
            alert = .init(title: "Eksik bilgi", message: "Miktar 0’dan büyük olmalı.")
            return
        }

        let avgTrim = avgCostText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !avgTrim.isEmpty && avgCost == nil {
            alert = .init(title: "Hatalı değer", message: "Ortalama maliyet sayısal olmalı.")
            return
        }

        let id = asset?.id ?? UUID()

        let new = Asset(
            id: id,
            type: type,
            name: finalName,
            symbol: sym,
            quantity: q,
            avgCostTRY: avgCost
        )

        onSave(new)
        dismiss()
    }

    private func adjustQuantity(by delta: Double) {
        let current = qty ?? 0
        let next = max(0, current + delta)
        quantityText = fmtTR(next)
    }

    // MARK: - Helpers

    private func exampleLine() -> String {
        switch type {
        case .metal:
            return "Örnek: XAUUSD=X, Miktar: 50 (gram), Maliyet: 2.100 (₺/gr)"
        case .fx:
            return "Örnek: USDTRY=X, Miktar: 1000"
        case .crypto:
            return "Örnek: BTC-USD, Miktar: 0,15"
        case .stock:
            return "Örnek: THYAO.IS, Miktar: 100"
        case .fund:
            return "Örnek: (Yahoo fon sembolü), Miktar: 10"
        }
    }

    private func parseDoubleTR(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        let normalized = t
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    private func fmtTR(_ x: Double) -> String {
        let nf = NumberFormatter()
        nf.locale = Locale(identifier: "tr_TR")
        nf.numberStyle = .decimal
        nf.minimumFractionDigits = 0
        nf.maximumFractionDigits = 6
        return nf.string(from: NSNumber(value: x)) ?? "\(x)"
    }

    private func fmtStep(_ x: Double) -> String {
        if x == floor(x) { return String(Int(x)) }
        return String(format: "%.1f", x).replacingOccurrences(of: ".", with: ",")
    }
}

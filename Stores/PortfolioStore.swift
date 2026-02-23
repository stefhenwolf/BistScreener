import Foundation

actor PortfolioStore {
    static let shared = PortfolioStore()

    private let fileName = "portfolio_assets.json"

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent(fileName)
    }

    // MARK: - Read

    func load() -> [Asset] {
        do {
            let url = fileURL
            guard FileManager.default.fileExists(atPath: url.path) else { return [] }
            let data = try Data(contentsOf: url)

            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            return try dec.decode([Asset].self, from: data)
        } catch {
            print("PortfolioStore.load error:", error)
            return []
        }
    }

    // MARK: - Write

    func save(_ assets: [Asset]) {
        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted]
            enc.dateEncodingStrategy = .iso8601

            let data = try enc.encode(assets)
            try data.write(to: fileURL, options: [.atomic]) // ✅ overwrite + atomic
        } catch {
            print("PortfolioStore.save error:", error)
        }
    }

    // MARK: - CRUD Helpers

    /// Dosyadan yükle → mutate → geri yaz
    private func mutate(_ block: (inout [Asset]) -> Void) {
        var assets = load()
        block(&assets)
        save(assets)
    }

    /// Ekle veya güncelle (id bazlı). id yoksa ekler.
    func upsert(_ asset: Asset) {
        mutate { arr in
            if let i = arr.firstIndex(where: { $0.id == asset.id }) {
                arr[i] = asset
            } else {
                arr.append(asset)
            }
        }
    }

    /// ID ile sil
    func delete(id: UUID) {
        mutate { arr in
            arr.removeAll { $0.id == id }
        }
    }

    /// Birden fazla ID ile sil
    func delete(ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let set = Set(ids)
        mutate { arr in
            arr.removeAll { set.contains($0.id) }
        }
    }

    /// Sembol bazlı sil (senin merge mantığına uygun: aynı sembolden ne varsa siler)
    func delete(symbol: String) {
        let key = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !key.isEmpty else { return }
        mutate { arr in
            arr.removeAll { $0.symbol.uppercased() == key }
        }
    }

    /// Birden çok sembol ile sil
    func delete(symbols: [String]) {
        let keys = Set(symbols.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }.filter { !$0.isEmpty })
        guard !keys.isEmpty else { return }
        mutate { arr in
            arr.removeAll { keys.contains($0.symbol.uppercased()) }
        }
    }

    /// Tüm portföyü temizle
    func deleteAll() {
        save([])
    }
}

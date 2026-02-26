//
//  Asset.swift
//  BistScreener
//
//  Created by Sedat Pala on 18.02.2026.
//

import Foundation

enum AssetType: String, CaseIterable, Identifiable, Codable {
    case stock   // hisse
    case fund    // fon
    case fx      // döviz
    case metal   // değerli maden
    case crypto  // kripto
    case cash    // nakit (TRY)

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stock: return "Hisse"
        case .fund: return "Fon"
        case .fx: return "Döviz"
        case .metal: return "Değerli Maden"
        case .crypto: return "Kripto"
        case .cash: return "Nakit"
        }
    }

    /// Varsayılan örnek sembol (Yahoo)
    var exampleSymbol: String {
        switch self {
        case .stock: return "THYAO.IS"
        case .fund: return "FROTO.IS" // TR fonlar Yahoo’da tutarsız olabilir; istersen farklı kullan
        case .fx: return "USDTRY=X"
        case .metal: return "GC=F"    // Gold futures (USD/oz)
        case .crypto: return "BTC-USD"
        case .cash: return "TRY"
        }
    }
}

struct Asset: Identifiable, Codable, Hashable {
    let id: UUID
    var type: AssetType
    var name: String
    var symbol: String
    var quantity: Double

    /// Ortalama maliyet (TRY) - opsiyonel
    var avgCostTRY: Double?

    var createdAt: Date

    init(
        id: UUID = UUID(),
        type: AssetType,
        name: String,
        symbol: String,
        quantity: Double,
        avgCostTRY: Double? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.symbol = symbol
        self.quantity = quantity
        self.avgCostTRY = avgCostTRY
        self.createdAt = createdAt
    }
}

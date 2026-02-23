//
//  TradeSignal.swift
//  BistScreener
//
//  Created by Sedat Pala on 22.02.2026.
//

import Foundation

enum TradeSignal: String, Codable, CaseIterable {
    case strongBuy  = "Güçlü AL"
    case buy        = "AL"
    case hold       = "BEKLET"
    case sell       = "SAT"
    case strongSell = "Güçlü SAT"
}

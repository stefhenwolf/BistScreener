//
//  StockDetailRoute.swift
//  BistScreener
//
//  Created by Sedat Pala on 21.02.2026.
//

import Foundation

enum StockDetailRoute: Hashable {
    case snapshot(ScanResult)
    case live(symbol: String)

    var symbol: String {
        switch self {
        case .snapshot(let result): return result.symbol
        case .live(let symbol): return symbol
        }
    }
}

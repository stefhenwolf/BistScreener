//
//  ScanScoringConfig.swift
//  BistScreener
//
//  Created by Sedat Pala on 22.02.2026.
//

import Foundation

struct ScanScoringConfig: Codable, Equatable {
    var strongTotal: Int = 80
    var total: Int = 60

    var bias: Int = 8
    var strongBias: Int = 20

    var neutralBias: Int = 12
    var adxBuyMin: Double = 14          // 18 -> 14
    var adxStrongBuyMin: Double = 18    // 22 -> 18

    var volBuyMult: Double = 1.00       // 1.15 -> 1.00  (vol MA üstü yeter)
    var volStrongBuyMult: Double = 1.15 // 1.35 -> 1.15

    static let `default` = ScanScoringConfig()
}

//
//  IndexOption.swift
//  BistScreener
//
//  Created by Sedat Pala on 18.02.2026.
//

//
//  IndexOption.swift
//  BistScreener
//
//  Created by Sedat Pala on 18.02.2026.
//

import Foundation

enum IndexOption: String, CaseIterable, Identifiable, Codable {
    case bistAll = "BIST"    // ✅ Tümü
    case xu100   = "XU100"   // ✅ BIST100
    case xu030   = "XU030"   // ✅ BIST30

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bistAll: return "BIST"
        case .xu100:   return "BIST 100"
        case .xu030:   return "BIST 30"
        }
    }
}

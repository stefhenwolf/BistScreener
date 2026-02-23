//
//  TVGrid.swift
//  BistScreener
//
//  Created by Sedat Pala on 21.02.2026.
//

import SwiftUI

struct TVGrid: View {
    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let h = g.size.height

            Path { p in
                for i in 1..<10 { // vertical
                    let x = w * CGFloat(i) / 10
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: h))
                }
                for i in 1..<6 {  // horizontal
                    let y = h * CGFloat(i) / 6
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: w, y: y))
                }
            }
            .stroke(Color.white.opacity(0.06), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

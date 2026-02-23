//
//  TVAppearance.swift
//  BistScreener
//
//  Created by Sedat Pala on 21.02.2026.
//

import UIKit

enum TVAppearance {
    static func apply() {
        // --- Tab Bar ---
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(TVTheme.bg)

        // ikon/yazı renkleri (seçili / seçili değil)
        let normal = UITabBarItemAppearance()
        normal.normal.iconColor = UIColor(TVTheme.subtext)
        normal.normal.titleTextAttributes = [.foregroundColor: UIColor(TVTheme.subtext)]
        normal.selected.iconColor = UIColor(TVTheme.text)
        normal.selected.titleTextAttributes = [.foregroundColor: UIColor(TVTheme.text)]

        tab.stackedLayoutAppearance = normal
        tab.inlineLayoutAppearance = normal
        tab.compactInlineLayoutAppearance = normal

        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        // --- Navigation Bar (opsiyonel ama tavsiye) ---
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(TVTheme.bg)          // TV arka plan
        nav.shadowColor = .clear

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor(TVTheme.text)
        ]
        nav.titleTextAttributes = titleAttrs
        nav.largeTitleTextAttributes = titleAttrs

        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().tintColor = UIColor(TVTheme.up)     // back button/icon rengi  
        
        
        
    }
}

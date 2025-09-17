//
//  StikAIApp.swift
//  StikAI
//
//  Created by Stephen Bove on 9/17/25.
//

import SwiftUI

@main
struct StikAIApp: App {
    @AppStorage("useDarkMode") private var useDarkMode = false
    
    var body: some Scene {
        WindowGroup {
            ChatListView()
                .preferredColorScheme(useDarkMode ? .dark : .light)
        }
    }
}

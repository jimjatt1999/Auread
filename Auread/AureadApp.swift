//
//  AureadApp.swift
//  Auread
//
//  Created by Jimi on 28/04/2025.
//

import SwiftUI

@main
struct AureadApp: App {
    // Instantiate the BookLibrary and SettingsManager as StateObjects
    @StateObject private var bookLibrary = BookLibrary()
    @StateObject private var settingsManager = SettingsManager.shared // Use the shared instance
    
    var body: some Scene {
        WindowGroup {
            // Inject both into the environment
            HomeView()
                .environmentObject(bookLibrary)
                .environmentObject(settingsManager)
        }
    }
}

//
//  AureadApp.swift
//  Auread
//
//  Created by Jimi on 28/04/2025.
//

import SwiftUI

@main
struct AureadApp: App {
    // Create a shared BookLibrary instance for the whole app
    @StateObject private var bookLibrary = BookLibrary()
    
    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(bookLibrary)
        }
    }
}

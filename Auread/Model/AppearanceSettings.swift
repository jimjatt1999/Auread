import Foundation
import SwiftUI

// Enum for available themes
enum ReaderTheme: String, CaseIterable, Identifiable {
    case light = "Light"
    case sepia = "Sepia"
    case dark = "Dark"

    var id: String { self.rawValue }

    var backgroundColor: Color {
        switch self {
        case .light: return Color.white
        case .sepia: return Color("#F8F1E3") ?? Color(red: 0.98, green: 0.94, blue: 0.89)
        case .dark: return Color("#121212") ?? Color.black // Slightly off-black
        }
    }

    var textColor: Color {
        switch self {
        case .light: return Color.black
        case .sepia: return Color("#5F4B32") ?? Color(red: 0.37, green: 0.29, blue: 0.2)
        case .dark: return Color("#E0E0E0") ?? Color.white // Slightly off-white
        }
    }
    
    // Corresponding Readium Theme value
    var readiumThemeValue: String {
        switch self {
        case .light: return "light"
        case .sepia: return "sepia"
        case .dark: return "dark"
        }
    }
}

// Struct to hold appearance settings
// Using Float for font size as Readium uses percentages (e.g., 1.0 = 100%)
struct AppearanceSettings: Codable, Equatable {
    var theme: ReaderTheme.RawValue = ReaderTheme.light.rawValue
    var fontSize: Float = 1.0 // Representing 100%

    // Computed property to get the actual Theme enum
    var readerTheme: ReaderTheme {
        ReaderTheme(rawValue: theme) ?? .light
    }

    // Default instance
    static let `default` = AppearanceSettings()
} 

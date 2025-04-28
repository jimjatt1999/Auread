import Foundation
import SwiftUI
import Combine

// Manages loading and saving of AppearanceSettings
class SettingsManager: ObservableObject {
    
    // Use AppStorage to persist the settings data
    // Encode/Decode AppearanceSettings to/from Data for storage
    @AppStorage("appearanceSettings") private var settingsData: Data?
    
    // Published property holding the current settings - NO didSet here.
    @Published var currentSettings: AppearanceSettings 
    
    // Cancellable to hold the Combine subscription for saving.
    private var saveCancellable: AnyCancellable?
    
    // Singleton instance (optional, but common for managers)
    static let shared = SettingsManager()
    
    private init() {
        // 1. Try to load saved data directly without involving self yet.
        //    We access AppStorage's underlying UserDefaults.
        let loadedData = UserDefaults.standard.data(forKey: "appearanceSettings")

        // 2. Determine the initial value (decode or default).
        let initialSettings: AppearanceSettings
        if let data = loadedData,
           let decodedSettings = try? JSONDecoder().decode(AppearanceSettings.self, from: data) {
            initialSettings = decodedSettings
            print("SettingsManager: Loaded settings - Theme: \(initialSettings.theme), FontSize: \(initialSettings.fontSize)")
        } else {
            initialSettings = AppearanceSettings.default
            print("SettingsManager: No saved settings found or decoding failed. Using default settings.")
        }
        
        // 3. Initialize the @Published property.
        //    This assignment is now safe.
        self.currentSettings = initialSettings 

        // 4. Set up the Combine pipeline to save future changes.
        //    This runs AFTER all properties are initialized.
        saveCancellable = $currentSettings
            .dropFirst() // Ignore the initial value set above.
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main) // Optional: Debounce to avoid rapid saves.
            .sink { [weak self] updatedSettings in
                self?.saveSettings(settings: updatedSettings)
            }
    }
    
    // Pass the settings explicitly to avoid race conditions with the published property.
    private func saveSettings(settings: AppearanceSettings) {
        do {
            let data = try JSONEncoder().encode(settings)
            settingsData = data // Write to AppStorage
            print("SettingsManager: Saved settings - Theme: \(settings.theme), FontSize: \(settings.fontSize)")
        } catch {
            print("SettingsManager: Error saving settings: \(error)")
        }
    }
    
    // Update functions modify currentSettings directly. The Combine sink will handle saving.
    func updateTheme(_ newTheme: ReaderTheme) {
        currentSettings.theme = newTheme.rawValue
    }
    
    func updateFontSize(_ newSize: Float) {
        let clampedSize = max(0.5, min(2.5, newSize)) // Example: 50% to 250%
        currentSettings.fontSize = clampedSize
    }
    
    deinit {
        saveCancellable?.cancel()
    }
}

// Let's refine the initializer and property definition to avoid confusion and ensure saving works correctly.

class RefinedSettingsManager: ObservableObject {
    @AppStorage("appearanceSettings") private var settingsData: Data?
    
    @Published var currentSettings: AppearanceSettings { 
        // Add the didSet observer here to trigger saving when currentSettings changes.
        didSet {
            saveSettings()
        }
    }
    
    static let shared = RefinedSettingsManager()
    
    private init() {
        // 1. Read data directly from UserDefaults first.
        let loadedData = UserDefaults.standard.data(forKey: "appearanceSettings")

        // 2. Try to load and decode saved settings.
        if let data = loadedData,
           let decodedSettings = try? JSONDecoder().decode(AppearanceSettings.self, from: data) {
            // 3. If successful, initialize _currentSettings directly with the loaded value.
            _currentSettings = Published(initialValue: decodedSettings)
            print("RefinedSettingsManager: Loaded settings - Theme: \(decodedSettings.theme), FontSize: \(decodedSettings.fontSize)")
        } else {
            // 4. Otherwise, initialize with the default value.
            _currentSettings = Published(initialValue: AppearanceSettings.default)
            print("RefinedSettingsManager: No saved settings found or decoding failed. Using default settings.")
            // Note: The didSet for saveSettings() won't trigger on this initial assignment.
            // If you need to save the default immediately, call saveSettings() explicitly AFTER initialization completes,
            // perhaps using a DispatchQueue.main.async block, or just let the first change trigger the save.
        }
        // Initialization is complete here. The didSet on currentSettings is now active.
    }
    
    private func saveSettings() {
        do {
            let data = try JSONEncoder().encode(currentSettings)
            settingsData = data
            print("SettingsManager: Saved settings - Theme: \(currentSettings.theme), FontSize: \(currentSettings.fontSize)")
        } catch {
            print("SettingsManager: Error saving settings: \(error)")
        }
    }
    
    // Update functions now modify currentSettings directly
    func updateTheme(_ newTheme: ReaderTheme) {
        currentSettings.theme = newTheme.rawValue
    }
    
    func updateFontSize(_ newSize: Float) {
        let clampedSize = max(0.5, min(2.5, newSize))
        currentSettings.fontSize = clampedSize
    }
} 
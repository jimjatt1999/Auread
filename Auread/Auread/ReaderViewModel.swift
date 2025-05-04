import SwiftUI
import ReadiumShared
import ReadiumStreamer
import ReadiumNavigator
import ReadiumAdapterGCDWebServer
import ReadiumOPDS
import ReadiumInternal
import Combine
import UIKit

// ViewModel to handle Readium logic
// Conform to EPUBNavigatorDelegate, SearchDelegate?
class ReaderViewModel: ObservableObject, EPUBNavigatorDelegate, Loggable {
    
    // MARK: - Published Properties
    @Published var publication: Publication?
    @Published var currentLocator: Locator? // Track current reading position
    @Published var tableOfContents: [ReadiumShared.Link] = [] // Publish ToC
    @Published var currentPage: Int? = nil // Track current page number
    @Published var totalPages: Int? = nil // Track total page count
    @Published var isCurrentLocationBookmarked: Bool = false // Track bookmark status
    @Published var currentChapterTitle: String? = nil // Track title for current locator

    // Search State
    @Published var searchQuery: String = ""
    @Published var searchResults: [Locator] = []
    @Published var isSearching: Bool = false
    @Published var activeSearchHighlightID: String? = nil // ID of the currently active search highlight decoration
    @Published var searchResultCount: Int? = nil // Optional total count from iterator

    // Highlight Interaction State
    @Published var tappedHighlightID: String? = nil
    @Published var tappedHighlightFrame: CGRect? = nil
    @Published var showHighlightMenu: Bool = false

    // Toast Notification State
    @Published var showToast: Bool = false
    @Published var toastMessage: String = ""
    @Published var toastIconName: String? = nil

    // MARK: - Stored Properties
    private let bookID: UUID
    private let bookLibrary: BookLibrary
    private let settingsManager: SettingsManager // Add SettingsManager
    private var settingsCancellable: AnyCancellable? // To observe settings changes

    // Keep components accessible for the Navigator
    let server: GCDHTTPServer
    let opener: PublicationOpener
    let httpClient: HTTPClient // Needed for AssetRetriever
    let assets: AssetRetriever // Needed?

    // Search Internals
    private var searchIterator: SearchIterator?
    private var currentSearchTask: Task<Void, Never>?
    private var currentLoadPageTask: Task<Void, Never>?

    // Haptic Feedback Generator
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)

    // MARK: - Initialization
    init(bookID: UUID, bookLibrary: BookLibrary, settingsManager: SettingsManager) {
        self.bookID = bookID
        self.bookLibrary = bookLibrary // Assign passed-in instance
        self.settingsManager = settingsManager // Assign passed-in instance
        
        // Initialize dependencies (order matters for some)
        self.httpClient = DefaultHTTPClient()
        self.assets = AssetRetriever(httpClient: httpClient)

        // Initialize HTTP Server - Use try! as init is not optional
        self.server = try! GCDHTTPServer(assetRetriever: assets)

        // Initialize PublicationOpener
        self.opener = PublicationOpener(
            parser: EPUBParser(),
            contentProtections: [] // No LCP for now
        )
        
        // Observe changes in SettingsManager
        settingsCancellable = settingsManager.$currentSettings
            .dropFirst() // Ignore the initial value
            .sink { [weak self] newSettings in
                print("ReaderViewModel: Detected settings change, applying...")
                self?.applySettings(newSettings)
            }

        // Prepare the feedback generator
        feedbackGenerator.prepare()

        // Ensure toast state is initially false
        showToast = false
    }

    // MARK: - Public Methods
    func openPublication(at url: URL, initialLocator: Locator? = nil) {
        guard publication == nil else { return }

        guard let absoluteURL = url.anyURL.absoluteURL else {
            print("Error: Could not convert \(url) to AbsoluteURL")
            return
        }

        Task {
            switch await assets.retrieve(url: absoluteURL) {
            case .success(let asset):
                let presentingViewController = UIApplication.shared.windows.first?.rootViewController ?? UIViewController()
                let openResult = await opener.open(asset: asset, allowUserInteraction: false, sender: presentingViewController)
                await MainActor.run {
                    switch openResult {
                    case .success(let pub):
                        self.publication = pub
                        
                        // Apply initial settings WHEN the publication is ready
                        // We will do this in the navigator delegate or after navigator setup
                        
                        // Fetch Table of Contents
                        Task {
                            let tocResult = await pub.tableOfContents()
                            await MainActor.run {
                                if case .success(let toc) = tocResult {
                                    self.tableOfContents = toc
                                    print("Successfully loaded ToC with \(toc.count) items.")
                                } else {
                                    self.tableOfContents = []
                                    print("Failed to load ToC")
                                }
                            }
                        }
                        
                        // Fetch total page count (positions)
                        Task {
                            do {
                                // Try getting the positions array directly, catching errors
                                let positionsArray = try await pub.positions().get()
                                await MainActor.run {
                                    self.totalPages = positionsArray.count // Get count from the [Locator] array
                                    print("Total pages calculated: \(self.totalPages ?? 0)")
                                    // Update current page initially if locator is available
                                    self.currentPage = initialLocator?.locations.position
                                }
                            } catch {
                                // Handle potential errors from .get()
                                await MainActor.run {
                                    print("Failed to get positions: \(error)")
                                    self.totalPages = nil
                                }
                            }
                        }

                    case .failure(let error):
                        print("Error opening publication: \(error)")
                        self.publication = nil
                        url.stopAccessingSecurityScopedResource()
                    }
                }
            case .failure(let error):
                print("Error retrieving asset: \(error)")
                await MainActor.run {
                    self.publication = nil
                    url.stopAccessingSecurityScopedResource()
                }
            }
        }
    }

    func closePublication() {
        // Clear any remaining highlights from view
        clearAllUserHighlights()
        clearSearchHighlight()
        
        publication = nil
        currentLocator = nil
        currentPage = nil // Reset page numbers
        totalPages = nil
        settingsCancellable?.cancel() // Stop observing settings
        print("Publication closed.")
    }
    
    // MARK: - Settings Application
    
    // Called initially when navigator is ready and when settings change
    func applySettings(_ settings: AppearanceSettings) {
        guard let navigator = navigatorViewController else {
            print("ApplySettings: Navigator not available yet.")
            return
        }
        
        // Map local ReaderTheme to ReadiumNavigator.Theme
        let navigatorTheme: ReadiumNavigator.Theme
        switch settings.readerTheme {
        case .light: navigatorTheme = .light
        case .sepia: navigatorTheme = .sepia
        case .dark: navigatorTheme = .dark
        }
        
        // Build the EPUBPreferences object using its initializer
        let preferences = ReadiumNavigator.EPUBPreferences(
            fontSize: Double(settings.fontSize), theme: navigatorTheme // Convert Float to Double
            // Add other preferences here as needed, e.g.:
            // scroll: false,
            // spread: .auto 
        )

        print("Applying EPUBPreferences: Theme=\(navigatorTheme), FontSize=\(settings.fontSize)")
        
        // Submit the EPUBPreferences object
        Task {
            await navigator.submitPreferences(preferences)
        }
    }

    // MARK: - NavigatorDelegate Methods
    
    // Apply initial settings once the navigator is ready (viewDidAppear)
    func navigator(_ navigator: UIViewController & Navigator, viewDidAppear animated: Bool) {
        print("ReaderViewModel: Navigator viewDidAppear, applying initial settings...")
        applySettings(settingsManager.currentSettings)
        
        Task {
             // Load existing user highlights
             await loadAllUserHighlights()
        }
    }
    
    func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
        Task {
            await MainActor.run { 
                // print("Location changed to: \(locator.href.description) with progression: \(String(describing: locator.locations.progression)), totalProgression: \(String(describing: locator.locations.totalProgression)), position: \(String(describing: locator.locations.position)))")
                self.currentLocator = locator
                self.currentPage = locator.locations.position // Update current page
                self.currentChapterTitle = locator.title // <--- Update current chapter title
                
                // Check if current location is bookmarked
                self.isCurrentLocationBookmarked = (self.bookLibrary.findBookmark(for: self.bookID, near: locator) != nil)
                
                // print("ReaderViewModel: Saving locator: \(locator.locations.totalProgression ?? -1.0)")
                self.bookLibrary.savePosition(for: self.bookID, locator: locator)
            }
        }
    }
    
    func navigator(_ navigator: any ReadiumNavigator.Navigator, didFailToLoadResourceAt href: ReadiumShared.RelativeURL, withError error: ReadiumShared.ReadError) {
        print("Navigator failed to load resource at \(href.string): \(error)")
    }
    
    func navigator(_ navigator: any ReadiumNavigator.Navigator, presentError error: ReadiumNavigator.NavigatorError) {
        print("Navigator presented error: \(error)")
    }
    
    // MARK: - VisualNavigatorDelegate Methods (Optional)
    
    // Called when the user taps the publication content.
    func navigator(_ navigator: VisualNavigator, didTapAt point: CGPoint) {
        // We receive the tap point in the navigator's view coordinate system.
        log(.info, "User tapped content at point: \(point)")
        
        // Check if tap is on a highlight decoration
        // This is implemented in the DecorableNavigator.onDecorationActivated method
        // Readium will automatically detect if the tap was on a decoration and call
        // the appropriate delegate method.
        
        // If we get here without a highlight being detected, it's a regular tap
        // This might be used to toggle controls in the ReaderView
    }
    
    // Implementation for the DecorableNavigator decoration interaction
    func navigator(_ navigator: DecorableNavigator, didActivateDecoration decoration: Decoration, at point: CGPoint?, in frame: CGRect?) {
        log(.info, "Decoration activated: \(decoration.id) at \(String(describing: point)) in frame \(String(describing: frame))")
        
        // Only show the highlight menu for user highlights stored in the library
        if let uuid = UUID(uuidString: decoration.id), bookLibrary.getHighlight(id: uuid) != nil {
            handleHighlightTap(id: decoration.id, frame: frame)
        }
    }
    
    // MARK: - Helpers
    var navigatorViewController: EPUBNavigatorViewController? {
        guard let keyWindow = UIApplication.shared.windows.first(where: { $0.isKeyWindow }) else {
            return nil
        }
        // More robust way to find the navigator
        return keyWindow.rootViewController?.findViewController(ofType: EPUBNavigatorViewController.self)
    }
    
    // MARK: - Search Functionality

    func beginSearch() {
        // Cancel any previous search tasks
        currentSearchTask?.cancel()
        currentLoadPageTask?.cancel()
        searchIterator?.close() // Close previous iterator if any
        searchIterator = nil

        // Clear previous results and state
        clearSearchHighlight() // Remove visual highlight
        Task { @MainActor in // Ensure UI updates happen on main thread
            self.searchResults = []
            self.searchResultCount = nil
            self.activeSearchHighlightID = nil
        }
        
        guard let pub = publication, !searchQuery.isEmpty else {
            log(.warning, "Search query is empty or publication is not loaded.")
            Task { @MainActor in self.isSearching = false }
            return
        }
        
        Task { @MainActor in self.isSearching = true }

        currentSearchTask = Task {
            do {
                let iteratorResult = await pub.search(query: searchQuery)
                let iterator = try iteratorResult.get() // Use .get() to extract iterator or throw error
                log(.info, "Search started for query: \(searchQuery)")
                // Check for cancellation after await
                try Task.checkCancellation()
                
                // Store iterator and load first page
                self.searchIterator = iterator
                await loadNextSearchResultsPage(reset: true) // Load first page (reset results)
                
                // Update total count if available AFTER first page load
                if let count = await iterator.resultCount {
                    Task { @MainActor in self.searchResultCount = count }
                }
                
            } catch is CancellationError {
                log(.info, "Search task cancelled for query: \(searchQuery)")
                searchIterator?.close() // Ensure iterator is closed on cancellation
                self.searchIterator = nil
            } catch {
                log(.error, "Error starting search for query \(searchQuery): \(error)")
            }            
            // Ensure searching state is reset regardless of success/failure/cancellation
            Task { @MainActor in self.isSearching = false }
        }
    }

    func loadNextSearchResultsPage(reset: Bool = false) async {
        guard let iterator = searchIterator else {
            log(.warning, "Attempted to load next page but searchIterator is nil.")
            return
        }
        
        // Prevent concurrent page loads
        guard currentLoadPageTask == nil else {
            log(.info, "Page load already in progress.")
            return
        }

        currentLoadPageTask = Task {
            do {
                log(.info, "Loading next search results page...")
                let collectionResult = await iterator.next()
                let collection = try collectionResult.get() // Use .get() to extract LocatorCollection? or throw error
                // Check for cancellation after await
                try Task.checkCancellation()

                // Update results on main thread
                await MainActor.run {
                    if reset {
                        self.searchResults = collection?.locators ?? []
                    } else {
                        self.searchResults.append(contentsOf: collection?.locators ?? [])
                    }
                    log(.info, "Loaded \(collection?.locators.count ?? 0) new search results. Total: \(self.searchResults.count)")
                }
                
                // Update total count if it has changed
                if let count = await iterator.resultCount, count != self.searchResultCount {
                    Task { @MainActor in self.searchResultCount = count }
                }

            } catch is CancellationError {
                log(.info, "Search page load task cancelled.")
            } catch {
                log(.error, "Error loading next search results page: \(error)")
            }
            // Reset task tracker
            currentLoadPageTask = nil
        }
        // Wait for the page load task to finish
        await currentLoadPageTask?.value
    }

    func cancelSearch() {
        log(.info, "Cancelling search.")
        currentSearchTask?.cancel()
        currentLoadPageTask?.cancel()
        searchIterator?.close()
        searchIterator = nil
        clearSearchHighlight()
        Task { @MainActor in
            self.searchResults = []
            self.searchQuery = ""
            self.searchResultCount = nil
            self.activeSearchHighlightID = nil
            self.isSearching = false
        }
    }

    func navigateToSearchResult(locator: Locator, id: String) async {
        guard let navigator = navigatorViewController else {
            log(.error, "Navigator not available for search result navigation.")
            return
        }
        
        log(.info, "Navigating to search result: \(id) at \(locator.href)")
        
        // Navigate first
        let success = await navigator.go(to: locator)
        
        // Apply highlight AFTER navigation (if successful)
        if success {
            Task { @MainActor in // Ensure UI update on main thread
                 // Clear previous highlight before applying new one
                 self.clearSearchHighlight()
                 self.activeSearchHighlightID = id
                 self.applySearchHighlight(locator: locator, id: id)
            }
        } else {
            log(.warning, "Navigation to search result \(id) failed.")
        }
    }

    private func applySearchHighlight(locator: Locator, id: String) {
        guard let navigator = navigatorViewController else { return }
        
        log(.info, "Applying search highlight decoration: \(id)")
        let style = Decoration.Style.underline(tint: .yellow, isActive: true) // Use stylistic underline for search highlights
        let decoration = Decoration(id: id, locator: locator, style: style)
        
        Task {
            do {
                // Apply decoration in the "search" group
                try await navigator.apply(decorations: [decoration], in: "search") // Use in: label
            } catch {
                log(.error, "Failed to apply search highlight decoration \(id): \(error)")
            }
        }
    }

    func clearSearchHighlight() {
        guard let navigator = navigatorViewController else { return }
        log(.info, "Clearing search highlight decorations.")
        Task {
            do {
                // Clear decorations in the "search" group
                try await navigator.apply(decorations: [], in: "search") // Use in: label
                await MainActor.run { self.activeSearchHighlightID = nil } // Clear ID on main thread
            } catch {
                log(.error, "Failed to clear search highlight decorations: \(error)")
            }
        }
    }

    // MARK: - Highlighting Functionality

    /// Called by UI to attempt highlighting the current text selection
    func attemptHighlightCurrentSelection() {
        guard let navigator = navigatorViewController else {
            log(.warning, "Navigator not available for highlight attempt.")
            return
        }
        Task {
            guard let selection = navigator.currentSelection else {
                log(.warning, "No text selection found for highlight attempt.")
                // Optionally provide user feedback here (e.g., a toast) that no text is selected
                return
            }
            log(.info, "Attempting to create highlight at locator: \(selection.locator)")
            await self.createHighlightFromSelection(locator: selection.locator)
        }
    }

    // Called from Coordinator when "Highlight" menu item is tapped
    func createHighlightFromSelection(locator: Locator) async {
        // Extract selected text from locator (fallback needed?)
        let selectedText = locator.text.highlight ?? ""
        guard !selectedText.isEmpty else {
            log(.warning, "Cannot create highlight with empty selected text.")
            return
        }
        
        // Create the new Highlight object (using default color for now)
        let newHighlight = Highlight(
            bookID: self.bookID, 
            locatorData: BookPosition(from: locator).encode() ?? Data(), // Encode BookPosition
            selectedText: selectedText
            // color: uses default "yellow"
            // note: uses default nil
        )

        // Save it via BookLibrary
        bookLibrary.addHighlight(
            for: newHighlight.bookID, 
            locator: locator, // Original locator needed here for BookPosition conversion inside addHighlight
            text: newHighlight.selectedText
            // Use default color and note
        )

        // Apply the decoration immediately
        applyHighlightDecoration(highlight: newHighlight)
    }
    
    // Applies a single highlight decoration
    private func applyHighlightDecoration(highlight: Highlight) {
        guard let navigator = navigatorViewController else { return }
        guard let position = BookPosition.decode(from: highlight.locatorData) else {
            log(.error, "[Highlight Error] Failed to decode BookPosition for highlight \(highlight.id)")
            return
        }

        let locator = position.asLocator() // Get Locator from BookPosition
        let color = UIColor(named: highlight.color) ?? .yellow // Use named color or fallback
        
        log(.debug, "Applying user highlight decoration: \(highlight.id) with color \(highlight.color) at locator: \(locator.href)")
        let style = Decoration.Style.underline(tint: color, isActive: true) // Decorative underline style for user highlights
        let decoration = Decoration(id: highlight.id.uuidString, locator: locator, style: style)
        
        Task {
            do {
                // Apply decoration in the "userHighlights" group
                log(.debug, "Calling navigator.apply for highlight decoration: \(decoration.id)")
                try await navigator.apply(decorations: [decoration], in: "userHighlights")
                log(.info, "Successfully applied highlight decoration: \(decoration.id)")
                // Trigger haptic feedback on successful application
                await MainActor.run {
                    self.feedbackGenerator.impactOccurred()
                    // Show success toast
                    self.toastMessage = "Highlighted"
                    self.toastIconName = "checkmark.circle.fill"
                    self.showToast = true
                }
            } catch {
                log(.error, "[Highlight Error] Failed to apply user highlight decoration \(highlight.id): \(error)")
            }
        }
    }

    // Loads and applies all existing highlights for the current book
    func loadAllUserHighlights() async {
        guard let navigator = navigatorViewController else { return }

        let highlights = bookLibrary.getHighlights(for: bookID)
        log(.info, "Loading \(highlights.count) user highlights for book \(bookID)")
        guard !highlights.isEmpty else { 
            // Ensure any stale decorations are cleared if there are no highlights
            Task {
                 try? await navigator.apply(decorations: [], in: "userHighlights")
            }
            return
        }

        var decorations: [Decoration] = []
        for highlight in highlights {
            if let position = BookPosition.decode(from: highlight.locatorData) {
                let locator = position.asLocator()
                let color = UIColor(named: highlight.color) ?? .yellow
                let style = Decoration.Style.underline(tint: color, isActive: true) // Decorative underline style for user highlights
                decorations.append(Decoration(id: highlight.id.uuidString, locator: locator, style: style))
            } else {
                log(.error, "Failed to decode BookPosition for highlight \(highlight.id) during bulk load.")
            }
        }
        
        log(.info, "Applying \(decorations.count) user highlight decorations in bulk.")
        Task {
            do {
                // Apply all decorations at once in the "userHighlights" group
                try await navigator.apply(decorations: decorations, in: "userHighlights")
            } catch {
                log(.error, "Failed to apply bulk user highlight decorations: \(error)")
            }
        }
    }
    
    // Clears all user highlight decorations (e.g., when closing book)
    func clearAllUserHighlights() {
        guard let navigator = navigatorViewController else { return }
        log(.info, "Clearing all user highlight decorations.")
        Task {
            do {
                try await navigator.apply(decorations: [], in: "userHighlights")
            } catch {
                 log(.error, "Failed to clear user highlight decorations: \(error)")
            }
        }
    }
    
    // TODO: Add methods for handling taps on highlights (requires delegate method)
    // TODO: Add methods for updating highlight color/note and deleting highlights
    
    // MARK: - Deinit
    deinit {
        print("ReaderViewModel deinit.")
        settingsCancellable?.cancel()
    }

    // MARK: - Highlight Interaction
    func handleHighlightTap(id: String, frame: CGRect?) {
         log(.debug, "Handling tap for highlight ID: \(id)")
         // TODO: Fetch the highlight details from BookLibrary if needed
         // For now, just set state to show a generic menu
         Task { @MainActor in
             self.tappedHighlightID = id
             self.tappedHighlightFrame = frame
             self.showHighlightMenu = true
         }
     }

    // Called by UI when the highlight menu should be dismissed
     func dismissHighlightMenu() {
         Task { @MainActor in
             self.showHighlightMenu = false
             self.tappedHighlightID = nil
             self.tappedHighlightFrame = nil
         }
     }
     
    // Placeholder functions for menu actions (to be implemented)
     func changeHighlightColor(id: String, newColor: String) {
         guard let uuid = UUID(uuidString: id) else { return }
         log(.info, "Request to change color for \(id) to \(newColor)")
         bookLibrary.updateHighlight(id: uuid, newColor: newColor)
         // Need to re-apply the specific decoration or all highlights
         // For simplicity now, reload all
         Task { await loadAllUserHighlights() } 
         dismissHighlightMenu()
     }
     
     func addNoteToHighlight(id: String, note: String) {
         guard let uuid = UUID(uuidString: id) else { return }
         log(.info, "Request to add note to \(id): \(note)")
         bookLibrary.updateHighlight(id: uuid, newNote: note)
          // Potentially update decoration style? For now, just save.
         Task { await loadAllUserHighlights() } // Reload to potentially show note icon later
         dismissHighlightMenu()
     }
     
     func deleteHighlight(id: String) {
         guard let uuid = UUID(uuidString: id) else { return }
         log(.info, "Request to delete highlight \(id)")
         bookLibrary.deleteHighlight(id: uuid)
         // Remove the specific decoration
         Task {
             // Apply an empty array to the group to clear it, then reload remaining.
             // Alternatively, just reload all, which will omit the deleted one.
             // try? await navigatorViewController?.apply(decorations: [], in: "userHighlights") // Clear all first?
             await loadAllUserHighlights() // Reload remaining highlights
         }
         dismissHighlightMenu()
     }

    // MARK: - @objc Actions for Editing Menu

    @objc func handleHighlightSelection(_ sender: Any?) {
        guard let navigator = navigatorViewController else {
            log(.error, "Navigator not found for highlight action.")
            return
        }
        
        // Get the current text selection from the navigator
        Task {
             // Access currentSelection as a property, not an async func
             if let selection = navigator.currentSelection {
                 log(.info, "Highlight action tapped for selection: \(selection.locator)")
                 // Call ViewModel method to create the highlight
                 await self.createHighlightFromSelection(locator: selection.locator)
                 // Clear the selection in the webview
                 await navigator.clearSelection()
             } else {
                 log(.warning, "Highlight action tapped but no selection found.")
             }
        }
    }
}

// REMOVED Duplicate Helper Extension
// // Helper Extension to find view controllers (ensure it's defined only once)
// // If not already defined elsewhere, keep it here or move to Extensions/
// extension UIViewController {
//     func findViewController<T: UIViewController>(ofType type: T.Type) -> T? {
//         if let vc = self as? T {
//             return vc
//         }
//         for child in children {
//             if let vc = child.findViewController(ofType: type) {
//                 return vc
//             }
//         }
//         if let presented = presentedViewController {
//             if let vc = presented.findViewController(ofType: type) {
//                 return vc
//             }
//         }
//         // Also check navigation controllers
//         if let navController = self as? UINavigationController {
//             return navController.viewControllers.compactMap { $0.findViewController(ofType: type) }.first
//         }
//         // Also check tab bar controllers
//         if let tabBarController = self as? UITabBarController {
//             return tabBarController.viewControllers?.compactMap { $0.findViewController(ofType: type) }.first
//         }
//         return nil
//     }
// }

// --- ADDED Helpers for BookPosition encoding/decoding ---
// It might be better to place these in BookProgress.swift
extension BookPosition {
    func encode() -> Data? {
        try? JSONEncoder().encode(self)
    }

    static func decode(from data: Data) -> BookPosition? {
        try? JSONDecoder().decode(BookPosition.self, from: data)
    }
}

// Helper to get UIColor from name (needs color assets or more robust mapping)
extension UIColor {
    convenience init?(named name: String) {
        // Simple mapping for now - expand or use Color Assets
        switch name.lowercased() {
        case "yellow": self.init(red: 1.0, green: 1.0, blue: 0.0, alpha: 1.0)
        case "blue": self.init(red: 0.0, green: 0.0, blue: 1.0, alpha: 1.0)
        case "green": self.init(red: 0.0, green: 1.0, blue: 0.0, alpha: 1.0)
        case "pink": self.init(red: 1.0, green: 0.0, blue: 1.0, alpha: 1.0) // Magenta as Pink
        default: return nil // Fallback if name not found
        }
    }
}

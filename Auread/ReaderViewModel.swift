//
//  ReaderViewModel.swift
//  Auread
//
//  Created by Jimi Olaoya.
//  Copyright © [Current Year] Jimi Olaoya. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import ReadiumNavigator
import Combine

@MainActor
class ReaderViewModel: NSObject, ObservableObject, Loggable, EPUBNavigatorDelegate {
    let bookID: UUID
    let bookLibrary: BookLibrary
    let settingsManager: SettingsManager
    
    // Server & Publication
    let server = PublicationServer()
    @Published private(set) var publication: Publication?
    
    // Navigation
    @Published var currentLocator: Locator?
    @Published var currentPage: Int?
    @Published var totalPages: Int?
    @Published var currentChapterTitle: String?
    @Published var isCurrentLocationBookmarked: Bool = false
    weak var navigator: Navigator?

    // Search
    @Published var searchQuery: String = ""
    @Published var searchResults: [Locator] = []
    @Published var isSearching: Bool = false
    @Published var activeSearchHighlightID: String? = nil
    @Published var searchResultCount: Int? = nil
    private var searchIterator: SearchIterator?
    private var currentSearchTask: Task<Void, Error>?
    private var currentLoadPageTask: Task<Void, Never>?

    // Highlights
    private let highlightRepository = HighlightRepository()
    @Published var highlights: [Highlight] = []
    @Published var showHighlightMenu: Bool = false
    @Published var tappedHighlightID: String?
    @Published var tappedHighlightFrame: CGRect?

    // Keep cancellables if needed for settings or other things
    private var cancellables = Set<AnyCancellable>()

    init(bookID: UUID, bookLibrary: BookLibrary, settingsManager: SettingsManager) {
        self.bookID = bookID
        self.bookLibrary = bookLibrary
        self.settingsManager = settingsManager
        super.init()
        
        // Subscribe to settings changes
        settingsManager.$currentSettings
             .sink { [weak self] newSettings in
                 self?.applySettings(newSettings)
             }
             .store(in: &cancellables)
    }

    // MARK: - Publication Loading
    func openPublication(at url: URL, initialLocator: Locator?) {
        Task {
            guard let pub = await Publication.open(asset: FileAsset(url: url), services: PublicationServices(baseURL: server.baseURL)).get() else {
                log(.error, "Failed to open publication at \(url)")
                return
            }
            self.publication = pub
            await MainActor.run {
                self.navigator = navigatorViewController
                if let locator = initialLocator {
                    self.currentLocator = locator
                    self.isCurrentLocationBookmarked = bookLibrary.findBookmark(for: bookID, near: locator) != nil
                    self.currentChapterTitle = locator.title
                }
                self.applySettings(settingsManager.currentSettings)
                self.loadHighlights()
            }
        }
    }

    var navigatorViewController: EPUBNavigatorViewController? {
        return UIApplication.shared.windows.first?.rootViewController?.children.first as? EPUBNavigatorViewController
    }

    // MARK: - EPUBNavigatorDelegate Methods

    func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
        currentLocator = locator
        currentPage = locator.locations.position
        totalPages = publication?.positions.count
        currentChapterTitle = locator.title

        isCurrentLocationBookmarked = bookLibrary.findBookmark(for: bookID, near: locator) != nil

        Task {
            await bookLibrary.savePosition(BookPosition(from: locator), for: bookID)
        }
    }
    
    func navigator(_ navigator: Navigator, didFailWithError error: NavigatorError) {
        log(.error, "Navigator failed: \(error)")
    }

    func navigator(_ navigator: Navigator, setupAppearance preferences: EPUBPreferencesEditor) {
        applySettings(settingsManager.currentSettings)
    }
    
    func navigator(_ navigator: Navigator, present externalURL: URL) -> Bool {
        print("Attempting to open external URL: \(externalURL)")
        return false
    }
    
    func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
         print("Navigator presentation error: \(error)")
     }

    // MARK: - Settings
     private func applySettings(_ settings: AppearanceSettings) {
         guard let navigator = self.navigator as? EPUBNavigator else { return }
         Task {
             await navigator.applyPreferences(
                 update: { prefs in
                     prefs.theme = settings.readerTheme.readiumTheme
                     prefs.fontSize = Double(settings.fontSize * 100)
                 }
             )
             print("ViewModel: Applied theme \(settings.theme) and font size \(settings.fontSize * 100)% using applyPreferences")
         }
     }

    // MARK: - Highlight Creation (Triggered Indirectly)
    
    // This method is called indirectly via the manualHighlightTrigger subject
    // It attempts to highlight whatever text is currently selected in the navigator
    func attemptHighlightCurrentSelection() {
        guard let navigator = self.navigator as? SelectableNavigator else {
            print("ViewModel Error: Navigator is not selectable or not available.")
            return
        }
        if let selection = navigator.currentSelection {
            print("ViewModel: Found selection to highlight: \(selection.locator)")
            Task {
                await createHighlightFromSelection(locator: selection.locator)
                await navigator.clearSelection()
                print("ViewModel: Highlight created and selection cleared.")
            }
        } else {
            print("ViewModel: Attempted to highlight, but no text is currently selected.")
        }
    }

    // Existing highlight creation logic (now called by attemptHighlightCurrentSelection)
    @MainActor
    func createHighlightFromSelection(locator: Locator) async {
        print("ViewModel: Creating highlight from selection: \(locator)")
        guard let pubID = publication?.metadata.identifier else {
            print("ViewModel Error: Cannot create highlight, missing publication ID.")
            return
        }
        let newHighlight = Highlight(
            id: UUID().uuidString,
            publicationID: pubID,
            locator: locator,
            color: 0,
            created: Date()
        )
        highlights.append(newHighlight)
        print("ViewModel: Added new highlight locally. Total: \(highlights.count)")
        await navigator?.addHighlight(newHighlight)
        print("ViewModel: Highlight added to navigator.")
        Task.detached(priority: .background) {
            await self.highlightRepository.saveHighlight(newHighlight)
            print("ViewModel: Highlight saved to repository (async).")
        }
    }
    
    @MainActor
    func loadHighlights() async {
        guard let pubID = publication?.metadata.identifier else { return }
        print("ViewModel: Loading highlights for \(pubID)")
        let fetchedHighlights = await highlightRepository.getHighlights(forPublication: pubID)
        print("ViewModel: Fetched \(fetchedHighlights.count) highlights")
        self.highlights = fetchedHighlights
        await reloadHighlightsInNavigator()
    }
    
    @MainActor
    func reloadHighlightsInNavigator() async {
        guard let navigator = self.navigator else { return }
        await navigator.clearHighlights()
        for highlight in highlights {
            await navigator.addHighlight(highlight)
        }
        print("ViewModel: Reloaded \(highlights.count) highlights in navigator.")
    }

    @MainActor
    func deleteHighlight(id: String) {
        print("ViewModel: Deleting highlight \(id)")
    }
    
    @MainActor
    func changeHighlightColor(id: String, newColor colorName: String) {
        print("ViewModel: Changing color for highlight \(id) to \(colorName)")
    }

    func dismissHighlightMenu() {
        print("ViewModel: Dismissing highlight menu.")
        self.showHighlightMenu = false
        self.tappedHighlightID = nil
        self.tappedHighlightFrame = nil
    }

    // Updated: Handle deselection to hide menu
    func navigator(_ navigator: SelectableNavigator, didSelect selection: Selection?) {
         DispatchQueue.main.async { // Ensure UI-related state updates on main thread
             print("ViewModel: didSelect called. Selection frame: \(selection?.frame)")
             // Original simple version: Do nothing specific here unless needed elsewhere
         }
     }

}

extension ReaderTheme {
    var readiumTheme: ReadiumNavigator.Theme {
        switch self {
        case .light: return .light
        case .sepia: return .sepia
        case .dark: return .dark
        }
    }
}

typealias Selection = ReadiumNavigator.Selection


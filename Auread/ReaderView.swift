import SwiftUI
import ReadiumShared // Import necessary Readium modules
import ReadiumStreamer
import ReadiumNavigator
import ReadiumAdapterGCDWebServer // Import the GCDWebServer adapter
import ReadiumOPDS // Potentially needed for default clients
import ReadiumInternal // Import for URL extensions like anyURL
// import ReadiumLCP // Removed for now
import Combine
import UIKit // Needed for UIViewController in open func

struct ReaderView: View {
    let fileURL: URL
    let bookID: UUID // Add book ID for identifying which book to update
    let initialLocator: Locator? // Optional initial locator for resuming position
    @Environment(\.dismiss) var dismiss // Environment value to dismiss the view
    @StateObject private var model: ReaderViewModel
    @EnvironmentObject var bookLibrary: BookLibrary
    @EnvironmentObject var settingsManager: SettingsManager // Get settings manager from environment
    
    // State for UI elements
    @State private var showTableOfContents = false
    @State private var showControls = true // Initially show controls
    @State private var showBookmarksHighlights = false // State for Bookmarks/Highlights sheet
    @State private var showCustomMenuSheet = false // Replaces showOptionsMenu
    @State private var showSearchView = false // <- ADDED: State for presenting Search View
    
    // State for scrubber
    @State private var sliderValue: Double = 0.0 // Value bound to slider (0.0 to 1.0)
    @State private var currentTotalProgression: Double = 0.0 // Actual progress from locator
    @State private var isScrubbing = false // Is user dragging the slider?
    
    // Default init with optional initialLocator - now requires bookLibrary & settingsManager
    init(fileURL: URL, bookID: UUID, bookLibrary: BookLibrary, settingsManager: SettingsManager, initialLocator: Locator? = nil) {
        self.fileURL = fileURL
        self.bookID = bookID
        self.initialLocator = initialLocator
        
        // Initialize the ViewModel here, passing the required dependencies
        _model = StateObject(wrappedValue: ReaderViewModel(bookID: bookID, bookLibrary: bookLibrary, settingsManager: settingsManager)) 
    }

    var body: some View {
        // Use GeometryReader to get view dimensions for tap zones
        GeometryReader { geometry in
        ZStack {
                // Conditionally show ReaderContainer or ProgressView
                if let publication = model.publication {
                    ReaderContainer(model: model, fileURL: fileURL, initialLocator: initialLocator ?? bookLibrary.getPosition(for: bookID), onTapLeft: { goToPreviousPage() }, onTapCenter: { withAnimation { showControls.toggle() } }, onTapRight: { goToNextPage() })
                        .edgesIgnoringSafeArea(.all)
                        .onChange(of: model.currentLocator) { newLocator in
                            updateSliderValueIfNeeded(locator: newLocator)
                        }
                    } else {
                    // Show loading indicator while publication is nil
                        ProgressView("Opening EPUB...")
                }
                
                // --- Temporarily Comment Out Tap Zones to Allow Text Selection --- 
                /*
                // --- Tap Zone Overlays --- 
                HStack(spacing: 0) {
                    // Left Tap Zone (20%)
                    Color.clear
                        .frame(width: geometry.size.width * 0.20)
                        .contentShape(Rectangle())
                        .highPriorityGesture(
                            TapGesture().onEnded { _ in
                                print("Tap: Left Zone - Previous Page")
                                goToPreviousPage()
                            }
                        )
                    
                    // Center Tap Zone (60%)
                    Color.clear
                        .frame(maxWidth: .infinity) 
                        .contentShape(Rectangle())
                        .highPriorityGesture(
                            TapGesture().onEnded { _ in
                                print("Tap: Center Zone - Toggle Controls")
                                withAnimation {
                                    showControls.toggle()
                            }
                    }
                        )
                    
                    // Right Tap Zone (20%)
                    Color.clear
                        .frame(width: geometry.size.width * 0.20)
                        .contentShape(Rectangle())
                        .highPriorityGesture(
                            TapGesture().onEnded { _ in
                                print("Tap: Right Zone - Next Page")
                                goToNextPage()
                            }
                        )
                }
                .edgesIgnoringSafeArea(.all) // Ensure zones cover screen edges
                */

                // --- Control Overlay --- 
                // Display controls if showControls is true
                if showControls {
                    VStack {
                        // Top Bar with Close, Highlight, and Bookmark Buttons
                        HStack {
                            Button {
                            model.closePublication()
                            dismiss()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .semibold))
                                    .padding(12) // Make tap area reasonable
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                            .padding([.top, .leading]) // Position top-left

                            Spacer() // Pushes buttons to sides

                            // Existing Bookmark Button (Toggle Action)
                            Button {
                                guard let currentLocator = model.currentLocator else {
                                    print("Cannot toggle bookmark, current location unknown.")
                                    return
                                }
                                
                                // Re-check bookmark status AT THE MOMENT OF TAP
                                let existingBookmark = bookLibrary.findBookmark(for: bookID, near: currentLocator)

                                if let bookmarkToDelete = existingBookmark {
                                    // If a bookmark exists near the current location, delete it.
                                    bookLibrary.deleteBookmark(id: bookmarkToDelete.id)
                                    print("Bookmark removed by button tap for locator: \(currentLocator.href)")
                                    // Update state immediately for responsiveness
                                    model.isCurrentLocationBookmarked = false 
                                } else {
                                    // If no bookmark exists near the current location, add one.
                                    // Pass the current chapter title from the ViewModel
                                    bookLibrary.addBookmark(for: bookID, locator: currentLocator, title: model.currentChapterTitle)
                                    print("Bookmark added by button tap for locator: \(currentLocator.href) with title: \(model.currentChapterTitle ?? "nil")")
                                    // Update state immediately for responsiveness
                                    model.isCurrentLocationBookmarked = true
                                }
                            } label: {
                                // Change icon based on state
                                Image(systemName: model.isCurrentLocationBookmarked ? "bookmark.fill" : "bookmark") 
                                    .font(.system(size: 16, weight: .semibold))
                                    .padding(12)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                            .padding([.top, .trailing]) // Position top-right
                        }

                        Spacer() // Pushes controls to bottom

                        HStack(alignment: .bottom) { // Use HStack to place buttons side-by-side
                            Spacer() // Push buttons to the right

                            // Existing Floating Ellipsis Button (Triggers custom sheet)
                            Button {
                                showCustomMenuSheet = true // Set state for custom sheet
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 20, weight: .semibold))
                                    .padding()
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                            .padding(.bottom)

                        } // End HStack for bottom buttons

                    } // End main VStack for controls
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                    .allowsHitTesting(true)
                }
                
            } // End ZStack
            .onAppear { // Trigger loading when the ZStack appears
                // Initialize slider value (if possible from initial locator)
                updateSliderValueIfNeeded(locator: initialLocator)
                
                // Start loading the publication if it hasn't started/finished
                if model.publication == nil {
                    // Start accessing the security-scoped resource before opening
                    _ = fileURL.startAccessingSecurityScopedResource()
                    
                    // Get initial locator from BookLibrary if not provided
                    let locator = initialLocator ?? bookLibrary.getPosition(for: bookID)
                    print("ReaderView: Attempting to open with locator: \(locator?.locations.progression ?? -1.0)") // Log loaded locator
                    model.openPublication(at: fileURL, initialLocator: locator)
                }
            }
            .onDisappear {
                // ... (Existing onDisappear logic remains the same) ...
                model.closePublication()
                fileURL.stopAccessingSecurityScopedResource()
                print("ReaderView: Stopped accessing security scoped resource on disappear for: \(fileURL.lastPathComponent)")
            }
            // Present the CUSTOM menu sheet
            .sheet(isPresented: $showCustomMenuSheet) {
                // Pass settings manager down to the options menu
                OptionsMenuView(
                    settingsManager: settingsManager, // Pass the manager
                    sliderValue: $sliderValue,
                    isScrubbing: $isScrubbing,
                    currentPage: model.currentPage,
                    totalPages: model.totalPages,
                    showTableOfContents: $showTableOfContents, 
                    showBookmarksHighlights: $showBookmarksHighlights,
                    showSearchView: $showSearchView, // <- ADDED: Pass binding
                    navigateToProgression: navigateToProgression 
                )
                 .presentationDetents([.height(320)]) // Adjust height for new controls
            }
            // Keep existing ToC sheet
            .sheet(isPresented: $showTableOfContents) {
                // Remove NavigationView, use VStack + manual elements
                VStack(spacing: 0) {
                    // Manual Header
                HStack {
                    Spacer()
                        Text("Contents")
                            .font(.headline)
                            .padding(.vertical)
                        Spacer()
                        Button("Done") {
                            showTableOfContents = false
                        }
                            .padding()
                    }
                    .background(.ultraThinMaterial) // Optional background for header
                    
                    Divider()

                List {
                        if model.tableOfContents.isEmpty && model.publication != nil {
                        Text("No table of contents available")
                            .foregroundColor(.gray)
                            .padding()
                    } else {
                            ForEach(model.tableOfContents, id: \.href) { link in
                            Button(action: {
                                // Wrap the async call here
                                Task {
                                   await navigateToLink(link)
                                }
                                showTableOfContents = false
                            }) {
                                Text(link.title ?? "Untitled")
                                    .padding(.vertical, 5)
                            }
                        }
                    }
                }
                    .listStyle(.plain) // Use plain style
                    // Removed .navigationTitle / .navigationBarTitleDisplayMode / .toolbar
                }
            }
            // --- NEW: Bookmarks & Highlights Sheet --- 
            .sheet(isPresented: $showBookmarksHighlights) { // Need state for this
                // Pass the callback closure directly via initializer
                BookmarksHighlightsView(bookID: bookID) { locator in // Trailing closure syntax
                    Task {
                        await model.navigatorViewController?.go(to: locator)
                    }
                }
                .environmentObject(bookLibrary) // Pass BookLibrary
            }
            // --- ADDED: Search Sheet ---
            .sheet(isPresented: $showSearchView) {
                 SearchView(model: model) // Pass the ReaderViewModel
             }
            // --- ADDED: Highlight Options Popover --- 
            // This uses a simple overlay + popover approach. 
            // A more sophisticated solution might use UIViewControllerRepresentable 
            // to present a UIMenu directly at the tapped location.
             .overlay(alignment: .topLeading) { // Use overlay to position relative to ZStack
                 // Invisible anchor view for popover positioning
                 // Position this view based on the tappedHighlightFrame
                 if model.showHighlightMenu, let frame = model.tappedHighlightFrame {
                     Color.clear
                          .frame(width: frame.width, height: frame.height)
                          .offset(x: frame.origin.x, y: frame.origin.y)
                          .popover(isPresented: $model.showHighlightMenu, arrowEdge: .bottom) { // Present popover from bottom
                               HighlightOptionsMenu(model: model)
                          }
                 } else {
                     EmptyView()
                 }
             }
            .navigationBarHidden(true)
            .navigationBarBackButtonHidden(true)
        } // End GeometryReader
    }
    
    // MARK: - Navigation Helpers
    private func goToNextPage() {
        Task {
            // Ensure we use the async version
            let _ = await model.navigatorViewController?.goForward()
        }
    }

    private func goToPreviousPage() {
        Task {
            // Ensure we use the async version
            let _ = await model.navigatorViewController?.goBackward()
        }
    }
    
    // Helper function to update slider based on locator
    private func updateSliderValueIfNeeded(locator: Locator?) {
        guard let locator = locator else { return }
        // Update the actual progression state
        currentTotalProgression = locator.locations.totalProgression ?? 0.0
        
        // Only update slider if user is not actively dragging it
        if !isScrubbing {
            sliderValue = currentTotalProgression
        }
    }
    
    // Helper function to navigate based on slider value
    private func navigateToProgression(_ progression: Double) {
        guard let publication = model.publication else { return }
        Task {
            // Ask the publication to find the locator for the target overall progression
            if let targetLocator = await publication.locate(progression: progression) {
                print("Navigating to progression: \(progression), Locator: \(targetLocator.href.description)")
                await model.navigatorViewController?.go(to: targetLocator)
            } else {
                print("Failed to find locator for progression: \(progression)")
                }
            }
        }
    
    // Helper to format progress percentage
    private func formatProgress(_ progress: Double) -> String {
        let percentage = Int(max(0.0, min(1.0, progress)) * 100)
        return "\(percentage)%"
    }
    
    // Navigation handler for table of contents
    private func navigateToLink(_ link: ReadiumShared.Link) async {
        guard let navigator = model.navigatorViewController,
              let publication = model.publication else { return }
        
        // Convert Link to Locator using publication.locate instead of direct initialization
        guard let locator = await publication.locate(link) else {
            print("Error: Could not create locator for link: \(link.href.description)")
            return
        }
        
        // Navigate to the locator
        Task {
            try? await navigator.go(to: locator)
        }
    }
}

// UIViewControllerRepresentable to host the Readium Navigator
struct ReaderContainer: UIViewControllerRepresentable {
    @ObservedObject var model: ReaderViewModel // Get model from parent
    let fileURL: URL
    let initialLocator: Locator? // Add initialLocator property

    // Actions passed from ReaderView
    let onTapLeft: () -> Void
    let onTapCenter: () -> Void
    let onTapRight: () -> Void

    // --- REMOVED Subclass Definition ---
    // class MyEPUBNavigatorViewController: EPUBNavigatorViewController { ... }
    // --- END REMOVED Subclass Definition ---

    func makeUIViewController(context: Context) -> EPUBNavigatorViewController {
        guard let publication = model.publication else {
            fatalError("Publication is nil in ReaderContainer")
        }

        print("ReaderContainer: Initializing standard navigator with locator: \(initialLocator?.locations.progression ?? -1.0)")

        // --- REMOVED Configuration for EditingAction ---
        // let config = EPUBNavigatorViewController.Configuration(editingActions: ...)
        // --- END REMOVED ---

        // Initialize with default config or only necessary non-editing config
        let config = EPUBNavigatorViewController.Configuration()

        let navigator = try! EPUBNavigatorViewController(
            publication: publication,
            initialLocation: initialLocator,
            config: config, // <-- Use default or basic config
            httpServer: model.server
        )

        navigator.delegate = model

        // --- Add Tap Gesture Recognizer ---
        let tapRecognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tapRecognizer.delegate = context.coordinator
        tapRecognizer.cancelsTouchesInView = false
        navigator.view.addGestureRecognizer(tapRecognizer)
        // --- End Gesture Recognizer ---

        // Assign the navigator instance to the coordinator
        context.coordinator.navigatorViewController = navigator

        return navigator
    }

    // Update to expect the standard class type
    func updateUIViewController(_ uiViewController: EPUBNavigatorViewController, context: Context) {
        // Ensure coordinator link is maintained if needed
        // uiViewController.readerCoordinator = context.coordinator // REMOVED
        context.coordinator.navigatorViewController = uiViewController // Keep coordinator's reference up-to-date
    }

    // Pass actions to Coordinator
    func makeCoordinator() -> Coordinator {
        Coordinator(model: model, onTapLeft: onTapLeft, onTapCenter: onTapCenter, onTapRight: onTapRight) // Pass model
    }

    // Coordinator now handles taps and holds model + navigator ref
    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let model: ReaderViewModel
        let onTapLeft: () -> Void
        let onTapCenter: () -> Void
        let onTapRight: () -> Void
        // Keep a weak reference to the navigator
        weak var navigatorViewController: EPUBNavigatorViewController? // <-- Changed type

        // Store actions and model
        init(model: ReaderViewModel, onTapLeft: @escaping () -> Void, onTapCenter: @escaping () -> Void, onTapRight: @escaping () -> Void) {
            self.model = model
            self.onTapLeft = onTapLeft
            self.onTapCenter = onTapCenter
            self.onTapRight = onTapRight
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let view = recognizer.view else { return }
            let location = recognizer.location(in: view)
            let screenWidth = view.bounds.width
            let tapZoneWidth = screenWidth * 0.20 // 20% edge zones

            // --- Temporarily disable edge taps to allow long-press selection ---
            if location.x < tapZoneWidth { // Left Zone
                print("Coordinator Tap: Left Zone - Ignored to allow selection")
                // onTapLeft() // Disabled
            } else if location.x > screenWidth - tapZoneWidth { // Right Zone
                print("Coordinator Tap: Right Zone - Ignored to allow selection")
                // onTapRight() // Disabled
            } else { // Center Zone
                print("Coordinator Tap: Center Zone - Toggle Controls")
                onTapCenter()
            }
        }

        // Optional: UIGestureRecognizerDelegate method to allow simultaneous recognition
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }

        // --- REMOVED: Action handler moved to ReaderViewModel --- 
        // @objc func handleHighlightSelection(_ sender: Any?) { ... }
         // --- END REMOVED --- 

    }
} 

// --- NEW OptionsMenuView Struct ---
struct OptionsMenuView: View {
    @ObservedObject var settingsManager: SettingsManager // Observe the manager
    @Binding var sliderValue: Double
    @Binding var isScrubbing: Bool
    let currentPage: Int?
    let totalPages: Int?
    @Binding var showTableOfContents: Bool
    @Binding var showBookmarksHighlights: Bool // Add binding
    @Binding var showSearchView: Bool // <- ADDED: Binding for search view presentation
    let navigateToProgression: (Double) -> Void // Closure for navigation

    @Environment(\.dismiss) var dismiss // To dismiss the sheet
    
    // Local state for font size stepper interaction
    @State private var currentFontSize: Float

    // Initialize local state from settings manager
    init(settingsManager: SettingsManager,
         sliderValue: Binding<Double>,
         isScrubbing: Binding<Bool>,
         currentPage: Int?,
         totalPages: Int?,
         showTableOfContents: Binding<Bool>,
         showBookmarksHighlights: Binding<Bool>,
         showSearchView: Binding<Bool>, // <- ADDED
         navigateToProgression: @escaping (Double) -> Void) {
        self.settingsManager = settingsManager
        self._sliderValue = sliderValue
        self._isScrubbing = isScrubbing
        self.currentPage = currentPage
        self.totalPages = totalPages
        self._showTableOfContents = showTableOfContents
        self._showBookmarksHighlights = showBookmarksHighlights
        self._showSearchView = showSearchView // <- ADDED
        self.navigateToProgression = navigateToProgression
        // Initialize the local state with the current setting
        _currentFontSize = State(initialValue: settingsManager.currentSettings.fontSize)
    }

    var body: some View {
        VStack(spacing: 15) {
            // --- Slider and Page Count ---
             VStack(spacing: 0) {
                Slider(value: $sliderValue, in: 0...1) { editing in
                    isScrubbing = editing
                    if !editing {
                        navigateToProgression(sliderValue)
                    }
                }
                .tint(.primary)
                .padding(.horizontal)

                Text("\(currentPage ?? 1) of \(totalPages ?? 1)")
                    .font(.caption)
                    .padding(.bottom, 5)
            }
            .padding(.vertical, 8)

            Divider()

            // --- Theme Selection ---
            VStack(alignment: .leading) {
                Text("Theme").font(.caption).foregroundStyle(.secondary)
                Picker("Theme", selection: $settingsManager.currentSettings.theme) {
                    ForEach(ReaderTheme.allCases) { theme in
                        Text(theme.rawValue).tag(theme.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal)
            
            Divider()
            
            // --- Font Size Adjustment ---
            VStack(alignment: .leading) {
                Text("Font Size").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button {
                        let newSize = currentFontSize - 0.1
                        currentFontSize = newSize
                        settingsManager.updateFontSize(newSize)
                    } label: {
                        Image(systemName: "textformat.size.smaller")
                    }.disabled(currentFontSize <= 0.5) // Disable at min size

                    Spacer()
                    Text("\(Int(currentFontSize * 100))%") // Display as percentage
                    Spacer()

                    Button {
                        let newSize = currentFontSize + 0.1
                        currentFontSize = newSize
                        settingsManager.updateFontSize(newSize)
                    } label: {
                        Image(systemName: "textformat.size.larger")
                    }.disabled(currentFontSize >= 2.5) // Disable at max size
                }
            }
            .padding(.horizontal)
            
            Divider()

            // --- Menu Buttons ---
            HStack {
                Button {
                    showTableOfContents = true
                    dismiss() // Dismiss this sheet first
                } label: {
                    Label("Contents", systemImage: "list.bullet")
                }
                Spacer()
                Button { 
                    showBookmarksHighlights = true
                    dismiss()
                } label: { 
                    Label("Bookmarks", systemImage: "bookmark") // Simplified label
                }
                Spacer()
                Button { 
                     showSearchView = true // <- MODIFIED: Set state to true
                     dismiss() // Dismiss this sheet first
                 } label: {
                    Label("Search", systemImage: "magnifyingglass") // Simplified label
                }
            }
            .padding(.horizontal)

            Spacer() // Push content up
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity) // Allow background to fill sheet
        .background(.ultraThinMaterial) // Apply frosted glass background
        .buttonStyle(.borderless) // Use plain button style
        // Apply the selected theme's background color to the sheet itself
        // .background(settingsManager.currentSettings.readerTheme.backgroundColor)
        // .colorScheme(settingsManager.currentSettings.readerTheme == .dark ? .dark : .light) // Adjust color scheme
    }
} 

// --- ADDED: Highlight Options Menu View ---
struct HighlightOptionsMenu: View {
    @ObservedObject var model: ReaderViewModel
    
    // Sample colors (match the names in UIColor extension)
    let availableColors = ["yellow", "blue", "green", "pink"]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Color Selection
            HStack {
                Text("Color:").font(.caption).foregroundStyle(.secondary)
                Spacer()
                ForEach(availableColors, id: \.self) { colorName in
                    Button { 
                        if let id = model.tappedHighlightID {
                             model.changeHighlightColor(id: id, newColor: colorName)
                        }
                    } label: {
                        Circle()
                            .fill(Color(uiColor: UIColor(named: colorName) ?? .clear))
                            .frame(width: 20, height: 20)
                            .overlay(Circle().stroke(Color.gray, lineWidth: 1))
                    }
                }
            }
            .padding()
            
            Divider()
            
            // Actions
            Button { 
                // TODO: Implement note adding UI
                print("Add/Edit Note Tapped - UI NYI")
                // if let id = model.tappedHighlightID {
                //     model.addNoteToHighlight(id: id, note: "Sample Note")
                // }
                 model.dismissHighlightMenu()
            } label: {
                Label("Add/Edit Note", systemImage: "note.text.badge.plus")
            }
            .padding()
            
             Divider()
            
             Button(role: .destructive) { 
                 if let id = model.tappedHighlightID {
                     model.deleteHighlight(id: id)
                 }
             } label: {
                 Label("Delete Highlight", systemImage: "trash")
             }
             .padding()
        }
        .buttonStyle(.plain) // Ensure buttons are tappable inside popover
        .frame(minWidth: 180) // Give the popover some minimum width
        .background(.regularMaterial) // Background for popover
        .cornerRadius(10)
         .onDisappear { 
             // Ensure menu state is reset if popover is dismissed interactively
             model.dismissHighlightMenu()
         }
    }
} 

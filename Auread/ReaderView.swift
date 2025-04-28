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
    @EnvironmentObject var bookLibrary: BookLibrary // Remove private modifier
    
    // State for UI elements
    @State private var showTableOfContents = false
    @State private var showControls = true // Initially show controls
    @State private var showCustomMenuSheet = false // Replaces showOptionsMenu
    
    // State for scrubber
    @State private var sliderValue: Double = 0.0 // Value bound to slider (0.0 to 1.0)
    @State private var currentTotalProgression: Double = 0.0 // Actual progress from locator
    @State private var isScrubbing = false // Is user dragging the slider?

    // Default init with optional initialLocator - now requires bookLibrary
    init(fileURL: URL, bookID: UUID, bookLibrary: BookLibrary, initialLocator: Locator? = nil) {
        self.fileURL = fileURL
        self.bookID = bookID
        self.initialLocator = initialLocator
        
        // Initialize the ViewModel here, passing the required dependencies
        // Use the bookLibrary instance passed into this View's initializer
        _model = StateObject(wrappedValue: ReaderViewModel(bookID: bookID, bookLibrary: bookLibrary)) 
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
                        // NEW: Top Bar with Close Button
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

                            Spacer() // Pushes button left
                        }

                        Spacer() // Pushes controls to bottom

                        // Floating Ellipsis Button (Triggers custom sheet)
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
                OptionsMenuView(
                    sliderValue: $sliderValue,
                    isScrubbing: $isScrubbing,
                    currentPage: model.currentPage,
                    totalPages: model.totalPages,
                    showTableOfContents: $showTableOfContents, // Pass binding
                    navigateToProgression: navigateToProgression // Pass function
                )
                // Apply presentation detents if desired (iOS 16+)
                 .presentationDetents([.medium, .height(280)]) // Example detents
            }
            // Keep existing ToC sheet
            .sheet(isPresented: $showTableOfContents) {
                // Restore the original NavigationView for the ToC sheet
                NavigationView {
                    List {
                        // Observe ToC from the ViewModel
                        if model.tableOfContents.isEmpty && model.publication != nil {
                            Text("No table of contents available")
                                .foregroundColor(.gray)
                                .padding()
                        } else {
                            // Observe ToC from the ViewModel
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
                    .navigationTitle("Contents")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                showTableOfContents = false
                            }
                        }
                    }
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

    func makeUIViewController(context: Context) -> EPUBNavigatorViewController {
        guard let publication = model.publication else {
            fatalError("Publication is nil in ReaderContainer")
        }

        print("ReaderContainer: Initializing navigator with locator: \(initialLocator?.locations.progression ?? -1.0)")
        
        let navigator = try! EPUBNavigatorViewController(
            publication: publication,
            initialLocation: initialLocator,
            httpServer: model.server
        )

        navigator.delegate = model
        
        // --- Add Tap Gesture Recognizer --- 
        let tapRecognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tapRecognizer.delegate = context.coordinator // Optional delegate for fine-tuning
        tapRecognizer.cancelsTouchesInView = false // Allow other gestures (selection, swipe)
        navigator.view.addGestureRecognizer(tapRecognizer)
        // --- End Gesture Recognizer --- 

        return navigator
    }

    func updateUIViewController(_ uiViewController: EPUBNavigatorViewController, context: Context) {
        // Handle updates if necessary
    }

    // Pass actions to Coordinator
    func makeCoordinator() -> Coordinator {
        Coordinator(onTapLeft: onTapLeft, onTapCenter: onTapCenter, onTapRight: onTapRight)
    }

    // Coordinator now handles taps
    class Coordinator: NSObject, UIGestureRecognizerDelegate { // Make NSObject for @objc, Add Delegate
        let onTapLeft: () -> Void
        let onTapCenter: () -> Void
        let onTapRight: () -> Void

        // Store actions
        init(onTapLeft: @escaping () -> Void, onTapCenter: @escaping () -> Void, onTapRight: @escaping () -> Void) {
            self.onTapLeft = onTapLeft
            self.onTapCenter = onTapCenter
            self.onTapRight = onTapRight
        }
        
        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let view = recognizer.view else { return }
            let location = recognizer.location(in: view)
            let screenWidth = view.bounds.width
            let tapZoneWidth = screenWidth * 0.20 // 20% edge zones

            if location.x < tapZoneWidth { // Left Zone
                print("Coordinator Tap: Left Zone - Previous Page")
                onTapLeft()
            } else if location.x > screenWidth - tapZoneWidth { // Right Zone
                print("Coordinator Tap: Right Zone - Next Page")
                onTapRight()
            } else { // Center Zone
                print("Coordinator Tap: Center Zone - Toggle Controls")
                onTapCenter()
            }
        }
        
        // Optional: UIGestureRecognizerDelegate method to allow simultaneous recognition
        // This might be needed if Readium's internal gestures still conflict.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            // Allow our tap recognizer to work alongside others (like Readium's swipes/selection)
            return true 
        }

        // Deinit no longer needs to stop accessing resource
        deinit {}
    }
} 

// --- NEW OptionsMenuView Struct ---
struct OptionsMenuView: View {
    @Binding var sliderValue: Double
    @Binding var isScrubbing: Bool
    let currentPage: Int?
    let totalPages: Int?
    @Binding var showTableOfContents: Bool
    let navigateToProgression: (Double) -> Void // Closure for navigation

    @Environment(\.dismiss) var dismiss // To dismiss the sheet

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

            // --- Menu Buttons ---
            Button {
                showTableOfContents = true
                dismiss() // Dismiss this sheet first
            } label: {
                Label("Contents", systemImage: "list.bullet")
            }

            Button { /* Implement later */ } label: {
                Label("Bookmarks & Highlights", systemImage: "bookmark") // Example icon
            }

            Button { /* Implement later */ } label: {
                Label("Search Book", systemImage: "magnifyingglass") // Example icon
            }

            Button { /* Implement later */ } label: {
                Label("Themes & Settings", systemImage: "textformat.size") // Example icon
            }

            Spacer() // Push content up
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity) // Allow background to fill sheet
        .background(.ultraThinMaterial) // Apply frosted glass background
        // Optional: Add a grabber indicator
        // .overlay(alignment: .top) { Capsule().fill(.secondary).frame(width: 40, height: 5).padding(.top, 8) }
        .buttonStyle(.borderless) // Use plain button style
    }
} 

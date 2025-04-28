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
    @State private var showOptionsMenu = false // For future options menu
    
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
                    ReaderContainer(model: model, fileURL: fileURL, initialLocator: initialLocator ?? bookLibrary.getPosition(for: bookID))
                        .edgesIgnoringSafeArea(.all)
                        .onChange(of: model.currentLocator) { newLocator in
                            updateSliderValueIfNeeded(locator: newLocator)
                        }
                } else {
                    // Show loading indicator while publication is nil
                    ProgressView("Opening EPUB...")
                }
                
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

                // --- Control Overlay --- 
                if showControls {
                    // Removed the separate tap gesture layer for controls
                    // Add the actual controls on top
                    VStack {
                        // Top Bar (using safe area)
                        HStack {
                            Button("Close") {
                                model.closePublication()
                                dismiss()
                            }
                            .padding()
                            Spacer()
                            Text(model.publication?.metadata.title ?? "Reader")
                               .font(.headline)
                               .lineLimit(1)
                            Spacer()
                            Button {
                                // Will show options menu later
                                // For now, directly show ToC
                                showTableOfContents = true 
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .imageScale(.large)
                            }
                            .padding()
                        }
                        .frame(maxWidth: .infinity)
                        .background(.thinMaterial)
                        
                        Spacer() // Pushes bottom controls down
                        
                        // Bottom Scrubber Bar (using safe area)
                        VStack(spacing: 0) {
                            Slider(value: $sliderValue, in: 0...1) { editing in
                                isScrubbing = editing
                                if !editing {
                                    // User finished scrubbing, navigate
                                    navigateToProgression(sliderValue)
                                }
                            }
                            .tint(.primary) // Match dark text color
                            .padding(.horizontal)
                            
                            // Display Page Numbers
                            Text("\(model.currentPage ?? 1) of \(model.totalPages ?? 1)")
                                .font(.caption)
                                .padding(.bottom, 5)
                        }
                        .padding(.bottom) // Add padding below scrubber text
                        .frame(maxWidth: .infinity)
                        .background(.thinMaterial)
                        
                    } // End main VStack for controls
                    .transition(.opacity.animation(.easeInOut(duration: 0.2))) // Fade controls in/out
                    // Prevent taps on controls from passing through to the background tap handler
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
            // We handle navigation title and close button within the overlay now
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

    func makeUIViewController(context: Context) -> EPUBNavigatorViewController {
        guard let publication = model.publication else {
            // This should ideally not happen if ReaderContainer is only shown when publication is ready
            fatalError("Publication is nil in ReaderContainer")
        }

        print("ReaderContainer: Initializing navigator with locator: \(initialLocator?.locations.progression ?? -1.0)") // Log locator passed to navigator
        
        // Revert to simple init until asset opening is fixed
        let navigator = try! EPUBNavigatorViewController(
            publication: publication,
            initialLocation: initialLocator, // Pass initialLocator here
            httpServer: model.server
        )

        // Set the delegate to receive location updates
        navigator.delegate = model
        
        // Configuration removed temporarily

        return navigator
    }

    func updateUIViewController(_ uiViewController: EPUBNavigatorViewController, context: Context) {
        // Handle updates if necessary
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator {
        var parent: ReaderContainer

        init(_ parent: ReaderContainer) {
            self.parent = parent
        }

        deinit {
            // No longer needed here as it's handled in onDisappear
            // parent.fileURL.stopAccessingSecurityScopedResource()
            // print("Coordinator: Stopped accessing security scoped resource for: \(parent.fileURL.lastPathComponent)")
        }
    }
} 

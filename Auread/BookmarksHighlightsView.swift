import SwiftUI
import ReadiumShared

struct BookmarksHighlightsView: View {
    let bookID: UUID
    @EnvironmentObject var bookLibrary: BookLibrary
    @Environment(\.dismiss) var dismiss
    
    // Callback to ReaderView to handle navigation
    var onItemSelected: ((Locator) -> Void)?
    
    @State private var selectedTab: Tab = .bookmarks
    
    enum Tab {
        case bookmarks, highlights
    }
    
    // Fetch data based on selected tab
    private var bookmarks: [Bookmark] {
        bookLibrary.getBookmarks(for: bookID).sorted { $0.creationDate > $1.creationDate } // Show newest first
    }
    private var highlights: [Highlight] {
        bookLibrary.getHighlights(for: bookID).sorted { $0.creationDate > $1.creationDate } // Show newest first
    }
    
    var body: some View {
        NavigationView {
            VStack {
                Picker("Type", selection: $selectedTab) {
                    Text("Bookmarks").tag(Tab.bookmarks)
                    Text("Highlights").tag(Tab.highlights)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                
                List {
                    if selectedTab == .bookmarks {
                        if bookmarks.isEmpty {
                            Text("No bookmarks yet.").foregroundColor(.gray)
                        } else {
                            ForEach(bookmarks) { bookmark in
                                bookmarkRow(bookmark)
                                    // Add swipe to delete later
                            }
                        }
                    } else { // Highlights
                        if highlights.isEmpty {
                            Text("No highlights yet.").foregroundColor(.gray)
                        } else {
                            ForEach(highlights) { highlight in
                                highlightRow(highlight)
                                    // Add swipe to delete later
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Notes") // Keep title simple
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    // Row view for a bookmark
    @ViewBuilder
    private func bookmarkRow(_ bookmark: Bookmark) -> some View {
        if let position = decodePosition(from: bookmark.locatorData) {
            Button {
                handleItemSelection(locatorData: bookmark.locatorData)
            } label: {
                HStack {
                    VStack(alignment: .leading) {
                        Text(position.resourceTitle ?? "Unknown Chapter")
                            .font(.headline)
                            .lineLimit(1)
                        Text("Page \(position.position ?? 0) • \(formatProgress(position.totalProgression))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(bookmark.creationDate, style: .relative)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    Image(systemName: "chevron.right") // Indicate tappable
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle()) // Make whole row tappable
            }
            .buttonStyle(.plain)
        } else {
            Text("Error loading bookmark")
        }
    }
    
    // Row view for a highlight
    @ViewBuilder
    private func highlightRow(_ highlight: Highlight) -> some View {
        if let position = decodePosition(from: highlight.locatorData) {
            Button {
                handleItemSelection(locatorData: highlight.locatorData)
            } label: {
                HStack {
                    VStack(alignment: .leading) {
                        Text(highlight.selectedText)
                            .font(.body)
                            .lineLimit(3) // Show a snippet
                        Text(position.resourceTitle ?? "Unknown Chapter")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(highlight.creationDate, style: .relative)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                     Spacer()
                    Image(systemName: "chevron.right") // Indicate tappable
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle()) // Make whole row tappable
            }
             .buttonStyle(.plain)
        } else {
            Text("Error loading highlight")
        }
    }
    
    // Helper to decode BookPosition safely
    private func decodePosition(from data: Data) -> BookPosition? {
        try? JSONDecoder().decode(BookPosition.self, from: data)
    }
    
    // Helper to format progress percentage
    private func formatProgress(_ progress: Double) -> String {
        let percentage = Int(max(0.0, min(1.0, progress)) * 100)
        return "\(percentage)%"
    }
    
    // Handle item tap
    private func handleItemSelection(locatorData: Data) {
        // Decode BookPosition first
        if let position = decodePosition(from: locatorData) {
            let locator = position.asLocator() // Convert BookPosition back to Locator
            onItemSelected?(locator) // Call the callback closure
            dismiss() // Dismiss this sheet
        }
    }
}

struct BookmarkRow: View {
    let bookmark: Bookmark
    
    // Helper to decode BookPosition safely
    private func decodePosition(from data: Data) -> BookPosition? {
        try? JSONDecoder().decode(BookPosition.self, from: data)
    }

    // Helper to get a displayable title
    private var displayTitle: String {
        // Use the explicitly saved chapter title first
        if let chapterTitle = bookmark.chapterTitle, !chapterTitle.isEmpty {
            return chapterTitle
        } else if let position = decodePosition(from: bookmark.locatorData), let positionTitle = position.resourceTitle, !positionTitle.isEmpty {
            // Fallback to title from BookPosition
            return positionTitle
        } else {
            // Further fallback
            return "Unknown Chapter"
        }
    }
    
    // Helper to get a displayable subtitle (e.g., page number or progression)
    private var displaySubtitle: String {
        if let position = decodePosition(from: bookmark.locatorData) {
            if let page = position.position {
                return "Page \(page)"
            } else {
                // Use totalProgression if position (page) is not available
                return "\(String(format: "%.1f", position.totalProgression * 100))%"
            }
        }
        // Fallback if location info is unavailable
        return "Created: \(bookmark.creationDate.formatted(date: .abbreviated, time: .omitted))"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Display title using the helper
            Text(displayTitle)
                .font(.headline)
                .lineLimit(1)
            
            // Show subtitle using the helper
            Text(displaySubtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
} 
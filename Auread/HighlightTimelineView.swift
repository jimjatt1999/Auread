import SwiftUI
import ReadiumShared

struct HighlightTimelineView: View {
    @EnvironmentObject var bookLibrary: BookLibrary
    @EnvironmentObject var settingsManager: SettingsManager
    @State private var searchText = ""
    @State private var selectedBookID: UUID? = nil
    @State private var selectedHighlightID: UUID? = nil
    @State private var navigateToReader = false
    @State private var errorMessage: String? = nil
    @State private var showErrorAlert = false
    @State private var groupByBook = false
    @State private var grouping: HighlightGrouping = .date
    
    enum HighlightGrouping {
        case date, book, color
    }
    
    var filteredHighlights: [Highlight] {
        let highlights = bookLibrary.highlights
        
        return highlights.filter { highlight in
            if !searchText.isEmpty {
                return highlight.selectedText.localizedCaseInsensitiveContains(searchText) ||
                       (highlight.note?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
            return true
        }.sorted { $0.creationDate > $1.creationDate } // Most recent first
    }
    
    var groupedHighlights: [String: [Highlight]] {
        let highlights = filteredHighlights
        var result: [String: [Highlight]] = [:]
        
        switch grouping {
        case .date:
            // Group by date (today, yesterday, this week, earlier)
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
            let weekAgo = calendar.date(byAdding: .day, value: -7, to: today)!
            
            for highlight in highlights {
                let date = highlight.creationDate
                let startOfDate = calendar.startOfDay(for: date)
                
                if calendar.isDate(startOfDate, inSameDayAs: today) {
                    let key = "Today"
                    result[key, default: []].append(highlight)
                } else if calendar.isDate(startOfDate, inSameDayAs: yesterday) {
                    let key = "Yesterday"
                    result[key, default: []].append(highlight)
                } else if startOfDate >= weekAgo {
                    let key = "This Week"
                    result[key, default: []].append(highlight)
                } else {
                    let key = "Earlier"
                    result[key, default: []].append(highlight)
                }
            }
            
        case .book:
            // Group by book title
            for highlight in highlights {
                if let book = bookLibrary.getBook(id: highlight.bookID) {
                    let key = book.title
                    result[key, default: []].append(highlight)
                } else {
                    let key = "Unknown Book"
                    result[key, default: []].append(highlight)
                }
            }
            
        case .color:
            // Group by highlight color
            for highlight in highlights {
                let key = highlight.color.capitalized
                result[key, default: []].append(highlight)
            }
        }
        
        return result
    }
    
    var sortedGroupKeys: [String] {
        // Custom sort order for date groups
        if grouping == .date {
            let allKeys = groupedHighlights.keys
            var sortedKeys: [String] = []
            
            if allKeys.contains("Today") { sortedKeys.append("Today") }
            if allKeys.contains("Yesterday") { sortedKeys.append("Yesterday") }
            if allKeys.contains("This Week") { sortedKeys.append("This Week") }
            if allKeys.contains("Earlier") { sortedKeys.append("Earlier") }
            
            return sortedKeys
        } else {
            return groupedHighlights.keys.sorted()
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Segmented control for grouping
                Picker("Group By", selection: $grouping) {
                    Text("Date").tag(HighlightGrouping.date)
                    Text("Book").tag(HighlightGrouping.book)
                    Text("Color").tag(HighlightGrouping.color)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)
                
                // Main content
                if filteredHighlights.isEmpty {
                    VStack {
                        Spacer()
                        Image(systemName: "highlighter")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                            .padding()
                        
                        Text("No highlights yet")
                            .font(.title2)
                            .foregroundColor(.gray)
                        
                        Text("Highlights you create while reading will appear here")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding()
                        
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    List {
                        ForEach(sortedGroupKeys, id: \.self) { groupKey in
                            if let highlights = groupedHighlights[groupKey] {
                                Section(header: Text(groupKey)) {
                                    ForEach(highlights) { highlight in
                                        HighlightRow(highlight: highlight, bookTitle: getBookTitle(for: highlight.bookID))
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                selectedBookID = highlight.bookID
                                                selectedHighlightID = highlight.id
                                                prepareForNavigation(highlight: highlight)
                                            }
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Highlights")
            .searchable(text: $searchText, prompt: "Search highlights")
            .background(
                NavigationLink(
                    destination: buildReaderDestination()
                        .navigationBarHidden(true)
                        .hideTabBar(), // Use the new modifier
                    isActive: $navigateToReader
                ) {
                    EmptyView()
                }
                .hidden()
            )
            .alert(
                "Error Opening Book", 
                isPresented: $showErrorAlert,
                presenting: errorMessage
            ) { _ in
                Button("OK", role: .cancel) { }
            } message: { message in
                Text(message)
            }
        }
    }
    
    private func prepareForNavigation(highlight: Highlight) {
        guard let bookID = selectedBookID,
              let book = bookLibrary.getBook(id: bookID) else {
            errorMessage = "Book not found in library"
            showErrorAlert = true
            return
        }
        
        guard let url = book.getURL() else {
            errorMessage = "Could not access book file"
            showErrorAlert = true
            return
        }
        
        // Check if we can get a valid locator from the highlight
        if let highlightID = selectedHighlightID,
           let highlight = bookLibrary.getHighlight(id: highlightID),
           let _ = try? JSONDecoder().decode(BookPosition.self, from: highlight.locatorData) {
            // We have a valid highlight and locator, proceed to navigation
            print("Highlight locator valid, proceeding to navigation")
            navigateToReader = true
        } else {
            errorMessage = "Could not navigate to highlight location"
            showErrorAlert = true
        }
    }
    
    @ViewBuilder
    private func buildReaderDestination() -> some View {
        if let bookID = selectedBookID,
           let book = bookLibrary.getBook(id: bookID),
           let url = book.getURL() {
           
           let initialLocator: Locator? = {
               if let highlightID = selectedHighlightID,
                  let highlight = bookLibrary.getHighlight(id: highlightID),
                  let position = try? JSONDecoder().decode(BookPosition.self, from: highlight.locatorData) {
                   return position.asLocator()
               }
               return bookLibrary.getPosition(for: bookID)
           }()
           
           ReaderView(fileURL: url,
                     bookID: bookID,
                     bookLibrary: bookLibrary,
                     settingsManager: settingsManager,
                     initialLocator: initialLocator)
               .environmentObject(bookLibrary)
               .environmentObject(settingsManager)
               .onAppear {
                   if let loc = initialLocator {
                       print("[HighlightTimelineView] Reader navigating with:")
                       print("  - Href: \(loc.href)")
                       print("  - Progression: \(loc.locations.progression ?? -1)")
                   }
               }
               .onDisappear {
                   navigateToReader = false
                   selectedBookID = nil
                   selectedHighlightID = nil
               }
       } else {
           Text("Error: Book not available")
               .onAppear {
                   navigateToReader = false
                   showErrorAlert = true
                   errorMessage = "Failed to open book"
               }
       }
    }
    
    private func getBookTitle(for bookID: UUID) -> String {
        return bookLibrary.getBook(id: bookID)?.title ?? "Unknown Book"
    }
}

struct HighlightRow: View {
    let highlight: Highlight
    let bookTitle: String
    
    // Add computed properties to extract more detail from the highlight
    private var pageInfo: String {
        if let position = try? JSONDecoder().decode(BookPosition.self, from: highlight.locatorData),
           let positionNumber = position.position {
            return "Page \(positionNumber)"
        } else {
            return ""
        }
    }
    
    private var chapterTitle: String {
        if let position = try? JSONDecoder().decode(BookPosition.self, from: highlight.locatorData),
           let title = position.resourceTitle, !title.isEmpty {
            return title.replacingOccurrences(of: ".html", with: "")
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "split_", with: "")
            // Clean up common filename artifacts
        } else {
            return ""
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // First line: Book title and date
            HStack {
                Text(bookTitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Date formatted more concisely
                Text(highlight.creationDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            // NEW: Chapter and page info line when available
            if !chapterTitle.isEmpty || !pageInfo.isEmpty {
                HStack {
                    if !chapterTitle.isEmpty {
                        Text(chapterTitle)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    if !chapterTitle.isEmpty && !pageInfo.isEmpty {
                        Spacer()
                    }
                    
                    if !pageInfo.isEmpty {
                        Text(pageInfo)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Highlight text with color indicator
            HStack(alignment: .top, spacing: 10) {
                // Color indicator
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(UIColor(named: highlight.color) ?? .yellow))
                    .frame(width: 4)
                
                // Main highlight text
                Text("\"\(highlight.selectedText)\"")
                    .font(.subheadline)
                    .lineLimit(3)
            }
            .padding(.top, 2)
            
            // Optional note
            if let note = highlight.note, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 14)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 8)
    }
}

struct HighlightTimelineView_Previews: PreviewProvider {
    static var previews: some View {
        let bookLibrary = BookLibrary()
        let settingsManager = SettingsManager.shared
        
        return HighlightTimelineView()
            .environmentObject(bookLibrary)
            .environmentObject(settingsManager)
    }
} 
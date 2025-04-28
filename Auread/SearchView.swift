import SwiftUI
import ReadiumShared // For Locator

struct SearchView: View {
    @ObservedObject var model: ReaderViewModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search Bar
                HStack {
                    TextField("Search in book...", text: $model.searchQuery, onCommit: {
                        model.beginSearch() // Start search on commit
                    })
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .onSubmit { // Also trigger on keyboard submit button
                         model.beginSearch()
                    }

                    if model.isSearching {
                        ProgressView()
                            .padding(.leading, 5)
                    } else if !model.searchQuery.isEmpty {
                        Button {
                           model.searchQuery = "" // Clear query
                           model.cancelSearch() // Cancel ongoing search and clear results
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .padding(.leading, 5)
                    }
                }
                .padding()

                Divider()

                // Results List
                List {
                    if !model.isSearching && model.searchResults.isEmpty && !model.searchQuery.isEmpty {
                         Text("No results found for \(model.searchQuery).")
                             .foregroundColor(.secondary)
                             .listRowSeparator(.hidden)
                    } else {
                        // Display results count if available
                        if let count = model.searchResultCount {
                            Text("Found \(count) result\(count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .listRowSeparator(.hidden)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        
                        ForEach(Array(model.searchResults.enumerated()), id: \.element.hashValue) { index, locator in
                            SearchResultRow(locator: locator)
                                .contentShape(Rectangle()) // Make row tappable
                                .onTapGesture {
                                    let searchID = "search-\(locator.hashValue)" // Generate a unique ID
                                    Task {
                                        await model.navigateToSearchResult(locator: locator, id: searchID)
                                        dismiss() // Dismiss search view after selection
                                    }
                                }
                                .onAppear {
                                     // Load next page when the last item appears
                                     // Add a small buffer to trigger before reaching the absolute end
                                     if index == model.searchResults.count - 5 {
                                         Task {
                                             await model.loadNextSearchResultsPage()
                                         }
                                     }
                                }
                        }
                         // Show loading indicator at the bottom if actively loading next page
                         // Check currentLoadPageTask might be better here if exposed
                         if model.isSearching && !model.searchResults.isEmpty {
                              ProgressView()
                                  .frame(maxWidth: .infinity, alignment: .center)
                                  .padding()
                                  .listRowSeparator(.hidden)
                         }
                    }
                }
                .listStyle(.plain)
                .animation(.default, value: model.searchResults) // Animate list changes
                
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        model.cancelSearch() // Clear search state
                        dismiss()
                    }
                }
            }
            // Start search automatically if query is already populated when view appears
             .onAppear {
                 if !model.searchQuery.isEmpty && model.searchResults.isEmpty && !model.isSearching {
                      model.beginSearch()
                 }
             }
             // Ensure search is cancelled when the view disappears
             .onDisappear {
                 // Only cancel if the user is dismissing the sheet,
                 // not if just navigating away temporarily (e.g., to reader)
                 // This logic might need refinement based on how dismissal occurs.
                 // For now, let's assume disappearing means cancelling search.
                 // model.cancelSearch() // Reconsider if this clears highlights too early
             }
        }
    }
}

struct SearchResultRow: View {
    let locator: Locator
    
    // Extract relevant text snippets from locator
    private var beforeText: String { locator.text.before?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
    private var highlightText: String { locator.text.highlight?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
    private var afterText: String { locator.text.after?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }

    var body: some View {
        VStack(alignment: .leading) {
            // Display chapter/section title if available
             if let title = locator.title, !title.isEmpty {
                 Text(title)
                     .font(.caption)
                     .foregroundColor(.secondary)
                     .padding(.bottom, 1)
             }
            
            // Combine text snippets for context, bolding the highlight
            HStack(spacing: 0) {
                 if !beforeText.isEmpty {
                      Text("...") // Indicate truncation
                      Text(String(beforeText.suffix(50))) // Show some context before
                          .foregroundColor(.gray)
                 }
                 Text(highlightText)
                     .bold() // Highlight the matched term
                 if !afterText.isEmpty {
                      Text(String(afterText.prefix(50))) // Show some context after
                          .foregroundColor(.gray)
                     Text("...") // Indicate truncation
                 }
            }
            .font(.body)
            .lineLimit(2) // Limit context lines
             
             // Optionally show progression
             if let progress = locator.locations.totalProgression {
                 Text(String(format: "%.1f%%", progress * 100))
                     .font(.caption2)
                     .foregroundColor(.blue)
             }
        }
        .padding(.vertical, 4)
    }
}

// #Preview {
//    // Need a mock ReaderViewModel with sample search results for preview
//    let mockModel = ReaderViewModel(bookID: UUID(), bookLibrary: BookLibrary.shared, settingsManager: SettingsManager.shared)
//    // Populate mockModel.searchResults here...
//    return SearchView(model: mockModel)
// } 
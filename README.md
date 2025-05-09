# Auread - EPUB Reader

A simple EPUB reader application for iOS built with SwiftUI and the Readium Mobile toolkit.

Created by Jimi Olaoya.

## How to Run

1.  Clone the repository.
2.  Open the `Auread.xcodeproj` file in Xcode.
3.  Select a target simulator or a connected iOS device.
4.  Click the "Run" button (or press Cmd+R).

    *   **Dependency Note:** If you encounter issues resolving the Readium dependency via Swift Package Manager using the URL, try cloning the [Readium Swift Toolkit repository](https://github.com/readium/swift-toolkit) locally. Add the cloned directory as a local Swift Package dependency in Xcode instead.

**Note:** Active development on this project has paused due to complexities encountered with integrating certain Readium features. However, it remains a useful example and base for building a simple EPUB reader for iOS with SwiftUI and Readium.

## Features

### Implemented

*   Import EPUB files via Document Picker.
*   Display EPUBs using Readium Navigator.
*   Library view with book covers, titles, authors, and progress.
*   Basic reader controls (close, next/previous page via swipe).
*   Adjustable appearance settings (Light/Sepia/Dark themes, Font Size).
*   Table of Contents navigation.
*   Progress saving (saves exact location within chapter).
*   Bookmarking (saving location with chapter title).
*   Bookmark list display and navigation.
*   In-book search with result highlighting.
*   Highlighting text selections (creation, saving, loading, display).
*   Decorative underline highlights for selected text via the highlighter button.
*   Highlight timeline view with chronological organization and filtering options.
*   Modern, Apple-style minimalist UI with grid layout for library.
*   Hold-to-delete books from the library grid.
*   Consistent reader presentation from both library and timeline views (fixed black borders and theme issues).

### Planned / Ideas

*   Highlight annotation/notes.
*   Highlight color selection.
*   Highlight deletion.
*   More robust error handling.
*   Library sorting/filtering options.
*   User accounts / Syncing (potentially via iCloud).
*   OPDS feed browsing/downloading.
*   Text-to-Speech (TTS).
*   Improved UI/UX refinements.

## Features (In Progress)

*   EPUB file importing
*   Library view (HomeView)
*   EPUB Reading View (ReaderView)
    *   Table of Contents navigation
    *   Reading progress saving/restoring across sessions
    *   Basic reader controls (Close, Scrubber, Options Menu)
    *   Tap/Swipe navigation
    *   Text selection 
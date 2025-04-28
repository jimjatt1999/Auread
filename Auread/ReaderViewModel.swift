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
// Conform to EPUBNavigatorDelegate
class ReaderViewModel: ObservableObject, EPUBNavigatorDelegate {
    
    // MARK: - Published Properties
    @Published var publication: Publication?
    @Published var currentLocator: Locator? // Track current reading position
    @Published var tableOfContents: [ReadiumShared.Link] = [] // Publish ToC
    @Published var currentPage: Int? = nil // Track current page number
    @Published var totalPages: Int? = nil // Track total page count

    // MARK: - Stored Properties
    private let bookID: UUID
    private let bookLibrary: BookLibrary 

    // Keep components accessible for the Navigator
    let server: GCDHTTPServer
    let opener: PublicationOpener
    let httpClient: HTTPClient // Needed for AssetRetriever
    let assets: AssetRetriever // Needed?

    // MARK: - Initialization
    init(bookID: UUID, bookLibrary: BookLibrary) {
        self.bookID = bookID
        self.bookLibrary = bookLibrary // Assign passed-in instance
        
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
        publication = nil
        currentLocator = nil
        currentPage = nil // Reset page numbers
        totalPages = nil
        print("Publication closed.")
    }

    // MARK: - NavigatorDelegate Methods
    func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
        Task {
            await MainActor.run { 
                print("Location changed to: \(locator.href.description) with progression: \(String(describing: locator.locations.progression)), totalProgression: \(String(describing: locator.locations.totalProgression)), position: \(String(describing: locator.locations.position)))")
                self.currentLocator = locator
                self.currentPage = locator.locations.position // Update current page
                
                print("ReaderViewModel: Saving locator: \(locator.locations.totalProgression ?? -1.0)")
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
    
    // MARK: - Helpers
    var navigatorViewController: EPUBNavigatorViewController? {
        guard let keyWindow = UIApplication.shared.windows.first(where: { $0.isKeyWindow }) else {
            return nil
        }
        return keyWindow.rootViewController?.findViewController(ofType: EPUBNavigatorViewController.self)
    }
    
    // MARK: - Deinit
    deinit {
        print("ReaderViewModel deinit.")
    }
}

// REMOVE Duplicate UIViewController Helper Extension
/*
// MARK: - UIViewController Helper Extension
// Keep this extension here OR move it to a dedicated Extensions file
// Ensure it's NOT also defined in ReaderView.swift or elsewhere causing redeclaration.
extension UIViewController {
    func findViewController<T: UIViewController>(ofType: T.Type) -> T? {
        if let vc = self as? T {
            return vc
        }
        for child in children {
            if let vc = child.findViewController(ofType: T.self) {
                return vc
            }
        }
        if let presented = presentedViewController {
            if let vc = presented.findViewController(ofType: T.self) {
                return vc
            }
        }
        return nil
    }
}
*/ 

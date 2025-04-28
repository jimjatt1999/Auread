import SwiftUI
import UIKit // For UIImage

struct BookItemView: View {
    // Accept parameters for customization later
    let title: String
    let author: String?
    // Path to the cover image in sandbox
    let coverImagePath: String?
    // Add progress property
    let progress: Double?

    // Add explicit initializer
    init(title: String, author: String?, coverImagePath: String?, progress: Double?) {
        self.title = title
        self.author = author
        self.coverImagePath = coverImagePath
        self.progress = progress
    }

    var body: some View {
        HStack(spacing: 15) {
            coverImageView
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 120)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
                .shadow(radius: 3)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                    .lineLimit(2)
                if let author = author {
                    Text(author)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                
                // Add ProgressView conditionally
                if let progress = progress, progress >= 0 {
                    HStack { // Group ProgressView and Text
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .frame(height: 5) // Make it subtle
                        Text(formatProgress(progress))
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 5)
                } else {
                    // Add a placeholder to maintain layout consistency when no progress
                    Spacer().frame(height: 10) // Height = ProgressView height + padding
                }
            }

            Spacer() // Pushes content to the left
        }
        .padding(.vertical, 8)
    }

    // Extract cover image or placeholder
    private var coverImageView: Image {
        if let path = coverImagePath,
           let uiImage = UIImage(contentsOfFile: path) {
            return Image(uiImage: uiImage)
        } else {
            return Image(systemName: "book.closed")
        }
    }
    
    // Helper to format progress percentage
    private func formatProgress(_ progress: Double) -> String {
        let percentage = Int(progress * 100)
        return "\(percentage)%"
    }
}

// Preview Provider (optional)
struct BookItemView_Previews: PreviewProvider {
    static var previews: some View {
        // Update preview to include progress
        BookItemView(title: "To Kill a Mockingbird", author: "Harper Lee", coverImagePath: nil, progress: 0.65)
            .padding()
            .previewLayout(.sizeThatFits)
        
        BookItemView(title: "New Book", author: "Author Name", coverImagePath: nil, progress: nil)
            .padding()
            .previewLayout(.sizeThatFits)
    }
} 
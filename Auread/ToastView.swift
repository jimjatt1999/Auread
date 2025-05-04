import SwiftUI

/// A view that displays a brief message overlay (toast) at the top of the screen.
struct ToastView: View {
    let message: String
    let iconName: String? // Optional SF Symbol name
    @Binding var isShowing: Bool
    let duration: TimeInterval = 2.0 // How long the toast stays visible

    var body: some View {
        VStack {
            HStack(spacing: 10) {
                if let iconName = iconName {
                    Image(systemName: iconName)
                        .foregroundColor(.primary) // Use adaptive color
                }
                Text(message)
                    .font(.caption)
                    .foregroundColor(.primary) // Use adaptive color
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(.regularMaterial) // Frosted glass effect
            .clipShape(Capsule())
            .shadow(radius: 5)
            .transition(.move(edge: .top).combined(with: .opacity)) // Animate from top
            .onAppear {
                // Schedule dismissal
                DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                    withAnimation {
                        isShowing = false
                    }
                }
            }
            Spacer() // Pushes toast to the top
        }
        .padding(.top) // Add some padding from the screen edge
        .frame(maxWidth: .infinity) // Allow VStack to position toast
        .allowsHitTesting(false) // Prevent toast from blocking interaction
    }
}

// Preview provider for ToastView
struct ToastView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack { // Example usage in a ZStack
            Color.blue.ignoresSafeArea() // Background to see the toast
            ToastView(
                message: "Highlighted",
                iconName: "checkmark.circle.fill",
                isShowing: .constant(true) // Keep preview visible
            )
        }
    }
} 
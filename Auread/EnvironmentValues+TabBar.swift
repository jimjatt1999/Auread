import SwiftUI

private struct HideTabBarKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var hideTabBar: Bool {
        get { self[HideTabBarKey.self] }
        set { self[HideTabBarKey.self] = newValue }
    }
}

extension View {
    func hideTabBar(_ hide: Bool = true) -> some View {
        environment(\.hideTabBar, hide)
    }
} 
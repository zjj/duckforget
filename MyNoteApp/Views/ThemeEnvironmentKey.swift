import SwiftUI

// MARK: - AppTheme EnvironmentKey

private struct AppThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue: AppTheme = .system
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeEnvironmentKey.self] }
        set { self[AppThemeEnvironmentKey.self] = newValue }
    }
}

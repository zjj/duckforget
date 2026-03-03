import Foundation
import Combine
import WidgetKit

/// 应用设置管理类
@Observable
class AppSettings {
    static let shared = AppSettings()
    
    private let trashRetentionDaysKey = "TrashRetentionDays"
    private let appThemeKey = "AppTheme"
    private let hasCompletedOnboardingKey = "HasCompletedOnboarding"

    /// 废纸篓保留天数，默认30天
    var trashRetentionDays: Int {
        didSet {
            UserDefaults.standard.set(trashRetentionDays, forKey: trashRetentionDaysKey)
        }
    }

    /// 当前应用主题，持久化至 UserDefaults（同时写入 App Group 供 Widget 读取）
    var currentTheme: AppTheme {
        didSet {
            UserDefaults.standard.set(currentTheme.rawValue, forKey: appThemeKey)
            // 写入 App Group，让 Widget Extension 也能读到最新主题
            UserDefaults(suiteName: SharedDefaults.suiteName)?
                .set(currentTheme.rawValue, forKey: SharedDefaults.appThemeKey)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// 是否已完成新手引导，持久化至 UserDefaults
    var hasCompletedOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: hasCompletedOnboardingKey)
        }
    }

    private init() {
        let storedTrash = UserDefaults.standard.integer(forKey: trashRetentionDaysKey)
        self.trashRetentionDays = storedTrash > 0 ? storedTrash : 30

        let storedTheme = UserDefaults.standard.string(forKey: "AppTheme") ?? ""
        self.currentTheme = AppTheme(rawValue: storedTheme) ?? .system

        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: hasCompletedOnboardingKey)

        // 首次启动时同步写入 App Group，确保 Widget 有初始值
        UserDefaults(suiteName: SharedDefaults.suiteName)?
            .set(self.currentTheme.rawValue, forKey: SharedDefaults.appThemeKey)
    }
}

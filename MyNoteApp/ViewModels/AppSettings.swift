import Foundation
import Combine

/// 应用设置管理类
@Observable
class AppSettings {
    static let shared = AppSettings()
    
    private let trashRetentionDaysKey = "TrashRetentionDays"
    private let appThemeKey = "AppTheme"
    
    /// 废纸篓保留天数，默认30天
    var trashRetentionDays: Int {
        didSet {
            UserDefaults.standard.set(trashRetentionDays, forKey: trashRetentionDaysKey)
        }
    }

    /// 当前应用主题，持久化至 UserDefaults
    var currentTheme: AppTheme {
        didSet {
            UserDefaults.standard.set(currentTheme.rawValue, forKey: appThemeKey)
        }
    }
    
    private init() {
        let storedTrash = UserDefaults.standard.integer(forKey: trashRetentionDaysKey)
        self.trashRetentionDays = storedTrash > 0 ? storedTrash : 30

        let storedTheme = UserDefaults.standard.string(forKey: "AppTheme") ?? ""
        self.currentTheme = AppTheme(rawValue: storedTheme) ?? .system
    }
}

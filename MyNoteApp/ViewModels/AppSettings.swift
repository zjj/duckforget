import Foundation
import Combine

/// 应用设置管理类
@Observable
class AppSettings {
    static let shared = AppSettings()
    
    private let trashRetentionDaysKey = "TrashRetentionDays"
    
    /// 回收站保留天数，默认30天
    var trashRetentionDays: Int {
        didSet {
            UserDefaults.standard.set(trashRetentionDays, forKey: trashRetentionDaysKey)
        }
    }
    
    private init() {
        let storedValue = UserDefaults.standard.integer(forKey: trashRetentionDaysKey)
        self.trashRetentionDays = storedValue > 0 ? storedValue : 30
    }
}

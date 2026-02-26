import Foundation

/// App Group 共享存储的键名常量
/// 主 App 写入，Widget Extension 读取
enum SharedDefaults {
    /// App Group 标识符 —— 需在两个 Target 的 Signing & Capabilities 中开启同一个 App Group
    static let suiteName = "group.com.duckforget.MyNoteApp"
    static let appThemeKey = "AppTheme"
}

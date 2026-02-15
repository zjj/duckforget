import Foundation
import SwiftData
import UIKit

enum WidgetType: String, Codable, CaseIterable, Identifiable {
    case search
    case folders
    case recentNotes
    case newNote
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .search: return "搜索"
        case .folders: return "文件夹"
        case .recentNotes: return "最近笔记"
        case .newNote: return "新建备忘录"
        }
    }
    
    var iconName: String {
        switch self {
        case .search: return "magnifyingglass"
        case .folders: return "folder"
        case .recentNotes: return "clock"
        case .newNote: return "square.and.pencil"
        }
    }
}

enum WidgetSize: String, Codable, CaseIterable {
    case small
    case medium
    case large
    case fullPage
    
    var height: CGFloat {
        switch self {
        case .small: return 80
        case .medium: return 160
        case .large: return 320
        case .fullPage: return UIScreen.main.bounds.height * 0.85
        }
    }
    
    var displayName: String {
        switch self {
        case .small: return "小"
        case .medium: return "中"
        case .large: return "大"
        case .fullPage: return "全屏"
        }
    }
}

struct DashboardItem: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var type: WidgetType
    var size: WidgetSize
    var order: Int
}

struct DashboardPage: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var items: [DashboardItem]
    var creationDate: Date = Date()
}

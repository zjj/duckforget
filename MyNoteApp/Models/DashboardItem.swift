import Foundation
import SwiftData
import UIKit

enum WidgetType: String, Codable, CaseIterable, Identifiable {
    case search
    case tag
    case recentNotes
    case newNote
    case trash
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .newNote: return "新建"
        case .tag: return "xx标签"
        case .recentNotes: return "最近"
        case .search: return "搜索"
        case .trash: return "回收站"
        }
    }
    
    var iconName: String {
        switch self {
        case .search: return "magnifyingglass"
        case .tag: return "tag"
        case .recentNotes: return "clock"
        case .newNote: return "text.pad.header.badge.plus"
        case .trash: return "trash"
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
        case .fullPage: return 600
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
    var tagName: String? // 用于tag类型组件，存储要显示的标签名
}

struct DashboardPage: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var items: [DashboardItem]
    var creationDate: Date = Date()
}

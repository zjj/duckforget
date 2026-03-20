import Foundation
import SwiftData
import UIKit

enum WidgetType: String, Codable, CaseIterable, Identifiable {
    case search
    case tag
    case recentNotes
    //case newNote
    case trash
    case encouragement
    case statistics
    case calendar
    case inlineInput
    case timeline
    case location
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        //case .newNote: return "新建"
        case .tag: return "标签视图"
        case .recentNotes: return "最近记录"
        case .search: return "搜索"
        case .trash: return "废纸篓"
        case .encouragement: return "鼓励语录"
        case .statistics: return "统计"
        case .calendar: return "月历"
        case .inlineInput: return "快捷输入"
        case .timeline: return "时间轴"
        case .location: return "地图"
        }
    }
    
    var iconName: String {
        switch self {
        case .search: return "magnifyingglass"
        case .tag: return "tag"
        case .recentNotes: return "clock"
        //case .newNote: return "text.pad.header.badge.plus"
        case .trash: return "trash"
        case .encouragement: return "heart.text.square"
        case .statistics: return "chart.bar.xaxis"
        case .calendar: return "calendar"
        case .inlineInput: return "square.and.pencil"
        case .timeline: return "calendar.day.timeline.left"
        case .location: return "mappin.and.ellipse"
        }
    }

    /// 每种组件支持的尺寸列表，空数组表示不支持调整大小
    var supportedSizes: [WidgetSize] {
        switch self {
        case .search:
            return [] // 搜索组件不支持调整大小
        case .recentNotes:
            return [.medium, .large]
        case  .tag: 
            return [.medium, .large]
        case .inlineInput:
            return [.large]
        case .encouragement:
            return [.small, .medium]
        case .trash, .calendar, .statistics:
            return [] // 不支持调整大小
        case .timeline:
            return [] // 时间轴仅支持全屏，不允许调整大小
        case .location:
            return [.large, .fullPage]
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

    var label: String {
        switch self {
        case .small: return "小"
        case .medium: return "中"
        case .large: return "大"
        case .fullPage: return "全屏"
        }
    }

    var iconName: String {
        switch self {
        case .small: return "rectangle.grid.1x2"
        case .medium: return "rectangle.grid.2x2"
        case .large: return "rectangle.grid.3x2"
        case .fullPage: return "rectangle.expand.vertical"
        }
    }
}

struct DashboardItem: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var type: WidgetType
    var size: WidgetSize
    var order: Int
    var tagName: String? = nil // 用于tag类型组件，存储要显示的标签名
    var content: String? = nil // 用于鼓励组件，存储鼓励语
    
    static let defaultEncouragement = "记录不是任务，是温柔的坚持。"
}

struct DashboardPage: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var items: [DashboardItem]
    var creationDate: Date = Date()
}

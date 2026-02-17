import Foundation

extension Date {
    /// 短格式：今天显示时间，昨天显示"昨天"，今年显示月/日，其余显示年/月/日
    var formattedShort: String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(self) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: self)
        } else if calendar.isDateInYesterday(self) {
            return "昨天"
        } else if calendar.isDate(self, equalTo: now, toGranularity: .year) {
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d"
            return formatter.string(from: self)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy/M/d"
            return formatter.string(from: self)
        }
    }
    
    /// 完整格式
    var formattedFull: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter.string(from: self)
    }
    
    /// 绝对日期格式（用于卡片显示）：今年内显示 M月d日，跨年显示完整日期
    var formattedAbsolute: String {
        let calendar = Calendar.current
        let now = Date()
        let formatter = DateFormatter()
        
        if calendar.isDate(self, equalTo: now, toGranularity: .year) {
            formatter.dateFormat = "M月d日 HH:mm"
        } else {
            formatter.dateFormat = "yyyy年M月d日 HH:mm"
        }
        return formatter.string(from: self)
    }
}

/// 日期分组段
enum DateSection: String, CaseIterable {
    case today = "今天"
    case yesterday = "昨天"
    case thisWeek = "本周"
    case thisMonth = "本月"
    case earlier = "更早"
    
    /// 判断日期属于哪个分组
    static func section(for date: Date) -> DateSection {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) {
            return .today
        } else if calendar.isDateInYesterday(date) {
            return .yesterday
        } else if let weekAgo = calendar.date(byAdding: .weekOfYear, value: -1, to: now),
                  date >= weekAgo {
            return .thisWeek
        } else if let monthAgo = calendar.date(byAdding: .month, value: -1, to: now),
                  date >= monthAgo {
            return .thisMonth
        } else {
            return .earlier
        }
    }
}

/// 按日期分组笔记的工具函数
func groupNotesByDate<T>(_ items: [T], dateKeyPath: KeyPath<T, Date>) -> [(DateSection, [T])] {
    var grouped: [DateSection: [T]] = [:]
    
    for item in items {
        let date = item[keyPath: dateKeyPath]
        let section = DateSection.section(for: date)
        grouped[section, default: []].append(item)
    }
    
    // 按顺序返回
    return DateSection.allCases.compactMap { section in
        guard let items = grouped[section], !items.isEmpty else { return nil }
        return (section, items)
    }
}

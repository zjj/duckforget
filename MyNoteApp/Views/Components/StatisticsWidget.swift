import SwiftUI
import SwiftData
import Charts

struct StatisticsWidget: View {
    @Environment(NoteStore.self) var noteStore
    @Environment(\.appTheme) private var theme
    var size: WidgetSize
    
    @Environment(\.modelContext) private var modelContext

    /// Limited to recent 1000 notes for charts (heatmap = 84 days, calendar = 6 months)
    @Query(
        filter: #Predicate<NoteItem> { note in note.isDeleted == false },
        sort: \NoteItem.createdAt,
        order: .reverse
    ) var allNotes: [NoteItem]

    // MARK: - Computed Stats

    private var totalNotes: Int {
        let descriptor = FetchDescriptor<NoteItem>(predicate: #Predicate { !$0.isDeleted })
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    private var totalAttachments: Int {
        allNotes.reduce(0) { $0 + $1.attachments.count }
    }
    
    private var notesCreatedToday: Int {
        let calendar = Calendar.current
        return allNotes.filter { !$0.isDeleted && calendar.isDateInToday($0.createdAt) }.count
    }
    
    private var notesCreatedThisWeek: Int {
        let calendar = Calendar.current
        let today = Date()
        guard let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) else { return 0 }
        return allNotes.filter { !$0.isDeleted && $0.createdAt >= startOfWeek }.count
    }
    
    // MARK: - Views
    
    var body: some View {
        if size == .fullPage {
            fullPageView
                .navigationTitle("统计数据")
                .background(Color(.systemGroupedBackground))
        } else {
            Group {
                switch size {
                case .small:
                    smallView
                case .medium:
                    mediumView
                case .large:
                    largeView
                default:
                    EmptyView()
                }
            }
            .padding()
            .background(theme.colors.surface)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 3)
        }
    }
    
    // MARK: - Small View (Summary)
    private var smallView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("总笔记")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(totalNotes)")
                    .font(.system(.title, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("今日新增")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("+\(notesCreatedToday)")
                    .font(.headline)
                    .foregroundColor(theme.colors.accent)
            }
        }
    }
    
    // MARK: - Medium View (Weekly Trend)
    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("本周趋势", systemImage: "chart.bar.fill")
                    .font(.headline)
                    .foregroundColor(theme.colors.accent)
                Spacer()
                Text("\(notesCreatedThisWeek) 条")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            if #available(iOS 16.0, *) {
                Chart(getLast7DaysStats(), id: \.date) { item in
                    BarMark(
                        x: .value("Date", item.date, unit: .day),
                        y: .value("Count", item.count)
                    )
                    .foregroundStyle(theme.colors.accent.gradient)
                    .cornerRadius(4)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { value in
                        AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                    }
                }
                .chartYAxis(.hidden)
                .frame(maxHeight: .infinity)
            } else {
                Text("需 iOS 16+")
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Large View (Contribution Graph / Calendar Heatmap)
    private var largeView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("创作热力图", systemImage: "calendar")
                .font(.headline)
            
            // Contribution Graph
            // Last 12 weeks
            
            LazyHGrid(rows: Array(repeating: GridItem(.fixed(12), spacing: 4), count: 7), spacing: 4) {
                ForEach(getContributionData(), id: \.date) { item in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(colorForCount(item.count))
                        .frame(width: 12, height: 12)
                }
            }
            .frame(height: 120) // 7 rows * (12 + 4) roughly
            
            HStack {
                VStack(alignment: .leading) {
                    Text("附件总数")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(totalAttachments)")
                        .font(.headline)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("最活跃标签")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(mostActiveTag ?? "无")
                        .font(.headline)
                }
            }
        }
    }
    
    // MARK: - Full Page View
    private var fullPageView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Summary Cards
                HStack(spacing: 16) {
                    summaryCard(title: "总笔记", value: "\(totalNotes)", icon: "doc.text.fill", color: .blue)
                    summaryCard(title: "总附件", value: "\(totalAttachments)", icon: "paperclip", color: .orange)
                }
                
                // Contribution Heatmap (Calendar Style)
                VStack(alignment: .leading, spacing: 16) {
                    Text("创作日历")
                        .font(.headline)
                    
                    calendarContributionView
                }
                .padding()
                .background(theme.colors.cardSecondary)
                .cornerRadius(12)
                
                // Recent Trend
                VStack(alignment: .leading) {
                    Text("近期趋势")
                        .font(.headline)
                    
                    if #available(iOS 16.0, *) {
                        Chart(getLast7DaysStats(), id: \.date) { item in
                            BarMark(
                                x: .value("Date", item.date, unit: .day),
                                y: .value("Count", item.count)
                            )
                            .foregroundStyle(theme.colors.accent.gradient)
                            .cornerRadius(4)
                            .annotation(position: .top) {
                                if item.count > 0 {
                                    Text("\(item.count)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .day)) { value in
                                AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                            }
                        }
                        .frame(height: 200)
                    }
                }
                .padding()
                .background(theme.colors.cardSecondary)
                .cornerRadius(12)
                
                // Tag Distribution
                VStack(alignment: .leading) {
                    Text("标签分布")
                        .font(.headline)
                    
                    if #available(iOS 16.0, *) {
                        let tagStats = getTagStats()
                        if tagStats.isEmpty {
                            Text("暂无标签数据")
                                .foregroundColor(.secondary)
                                .padding()
                        } else {
                            Chart(tagStats, id: \.tagName) { item in
                                SectorMark(
                                    angle: .value("Count", item.count),
                                    innerRadius: .ratio(0.6),
                                    angularInset: 1.5
                                )
                                .foregroundStyle(by: .value("Tag", item.tagName))
                                .annotation(position: .overlay) {
                                    VStack(spacing: 0) {
                                        Text(item.tagName)
                                            .font(.caption2)
                                            .headerProminence(.increased)
                                        Text("\(item.count)")
                                            .font(.caption)
                                            .fontWeight(.bold)
                                    }
                                    .foregroundColor(.white)
                                    .shadow(radius: 1)
                                }
                            }
                            .frame(height: 250)
                        }
                    }
                }
                .padding()
                .background(theme.colors.cardSecondary)
                .cornerRadius(12)
            }
            .padding()
        }
    }
    
    private var calendarContributionView: some View {
        let calendar = Calendar.current
        let today = Date()
        
        // 生成最近 6 个月
        let months = (0..<6).compactMap { i in
            calendar.date(byAdding: .month, value: -i, to: today)
        }.reversed()
        let monthArray = Array(months)
        
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(monthArray, id: \.self) { month in
                        MonthCalendarView(month: month, allNotes: allNotes)
                            .frame(width: 300) // 设定固定宽度以确保日历显示正常
                            .padding()
                            .background(theme.colors.surface)
                            .cornerRadius(8)
                            .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                            .id(month)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 8) // 为阴影留出空间
            }
            .onAppear {
                // 默认滚动到当前月份（最后一个）
                if let lastMonth = monthArray.last {
                    proxy.scrollTo(lastMonth, anchor: .trailing)
                }
            }
        }
    }

    private func summaryCard(title: String, value: String, icon: String, color: Color) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.title2)
                    .bold()
            }
            Spacer()
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(color)
        }
        .padding()
        .background(theme.colors.cardSecondary)
        .cornerRadius(12)
    }
    
    // MARK: - Helpers
    
    struct DateStat {
        let date: Date
        let count: Int
    }
    
    private func getLast7DaysStats() -> [DateStat] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var stats: [DateStat] = []
        
        for i in 0..<7 {
            if let date = calendar.date(byAdding: .day, value: -i, to: today) {
                let count = allNotes.filter { !$0.isDeleted && calendar.isDate($0.createdAt, inSameDayAs: date) }.count
                stats.append(DateStat(date: date, count: count))
            }
        }
        return stats.reversed()
    }
    
    private func getLast15DaysStats() -> [DateStat] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var stats: [DateStat] = []
        
        for i in 0..<15 {
            if let date = calendar.date(byAdding: .day, value: -i, to: today) {
                let count = allNotes.filter { !$0.isDeleted && calendar.isDate($0.createdAt, inSameDayAs: date) }.count
                stats.append(DateStat(date: date, count: count))
            }
        }
        return stats.reversed()
    }

    private func getLast30DaysStats() -> [DateStat] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var stats: [DateStat] = []
        
        for i in 0..<30 {
            if let date = calendar.date(byAdding: .day, value: -i, to: today) {
                let count = allNotes.filter { !$0.isDeleted && calendar.isDate($0.createdAt, inSameDayAs: date) }.count
                stats.append(DateStat(date: date, count: count))
            }
        }
        return stats.reversed()
    }
    
    private func getContributionData() -> [DateStat] {
        // Last 12 weeks * 7 days = 84 days
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var stats: [DateStat] = []
        
        // Align to end of week
        // 简单起见，取最近 84 天
        for i in 0..<84 {
            if let date = calendar.date(byAdding: .day, value: -(83 - i), to: today) {
                let count = allNotes.filter { !$0.isDeleted && calendar.isDate($0.createdAt, inSameDayAs: date) }.count
                stats.append(DateStat(date: date, count: count))
            }
        }
        // Should sort by date? loop is already sorted
        return stats
    }
    
    private func colorForCount(_ count: Int) -> Color {
        if count == 0 { return Color.gray.opacity(0.2) }
        if count == 1 { return theme.colors.accent.opacity(0.3) }
        if count <= 3 { return theme.colors.accent.opacity(0.6) }
        return theme.colors.accent
    }
    
    struct TagStat {
        let tagName: String
        let count: Int
    }
    
    private func getTagStats() -> [TagStat] {
        var counts: [String: Int] = [:]
        for note in allNotes where !note.isDeleted {
            for tag in note.tags {
                counts[tag.name, default: 0] += 1
            }
        }
        return counts.map { TagStat(tagName: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
            .prefix(5)
            .map { $0 }
    }
    
    private var mostActiveTag: String? {
        getTagStats().first?.tagName
    }
}

struct MonthCalendarView: View {
    let month: Date
    let allNotes: [NoteItem]
    @Environment(\.appTheme) private var theme
    private let calendar = Calendar.current
    
    // Grid Setup
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    
    private var monthName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年 M月"
        return formatter.string(from: month)
    }
    
    private var days: [Date?] {
        // Build the calendar grid
        guard let monthInterval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let firstDay = monthInterval.start
        
        let range = calendar.range(of: .day, in: .month, for: firstDay)!
        let numDays = range.count
        
        // Sunday=1, Monday=2...
        let firstWeekday = calendar.component(.weekday, from: firstDay)
        
        var daysArray: [Date?] = []
        
        // Add placeholders for empty slots before the 1st of the month
        for _ in 1..<firstWeekday {
            daysArray.append(nil)
        }
        
        for day in 1...numDays {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstDay) {
                daysArray.append(date)
            }
        }
        
        // Pad to ensure 6 rows (42 days) for consistent height
        while daysArray.count < 42 {
            daysArray.append(nil)
        }
        
        return daysArray
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(monthName)
                .font(.headline)
                .padding(.bottom, 4)
            
            // Weekday Headers
            HStack {
                ForEach(["日", "一", "二", "三", "四", "五", "六"], id: \.self) { day in
                    Text(day)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            
            // Days Grid
            let gridDays = days
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(0..<gridDays.count, id: \.self) { index in
                    if let date = gridDays[index] {
                        let count = countForDate(date)
                        let dayNum = calendar.component(.day, from: date)
                        
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(colorForCount(count))
                                .aspectRatio(1, contentMode: .fit)
                            
                            Text("\(dayNum)")
                                .font(.caption2)
                                .foregroundColor(count > 0 ? .white : .primary)
                        }
                    } else {
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
    }
    
    private func countForDate(_ date: Date) -> Int {
        allNotes.filter { !$0.isDeleted && calendar.isDate($0.createdAt, inSameDayAs: date) }.count
    }
    
    private func colorForCount(_ count: Int) -> Color {
        if count == 0 { return Color(.secondarySystemFill) }
        if count == 1 { return theme.colors.accent.opacity(0.4) }
        if count <= 3 { return theme.colors.accent.opacity(0.7) }
        return theme.colors.accent
    }
}

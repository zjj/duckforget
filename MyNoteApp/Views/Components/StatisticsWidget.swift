import SwiftUI
import SwiftData
import Charts

struct StatisticsWidget: View {
    @Environment(NoteStore.self) var noteStore
    @Environment(\.appTheme) private var theme
    var size: WidgetSize
    
    @Environment(\.modelContext) private var modelContext

    // MARK: - Async-loaded state (replaces @Query to avoid loading all notes)
    @State private var totalNotes: Int = 0
    @State private var notesCountByDay: [String: Int] = [:]
    @State private var tagStats: [TagStat] = []

    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func dayKey(_ date: Date) -> String {
        Self.dayKeyFormatter.string(from: date)
    }

    private var notesCreatedToday: Int {
        let key = dayKey(Calendar.current.startOfDay(for: Date()))
        return notesCountByDay[key] ?? 0
    }
    
    private var notesCreatedThisWeek: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) else { return 0 }
        let daysCount = max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: startOfWeek), to: today).day ?? 0)
        return (0...daysCount)
            .compactMap { calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: startOfWeek)) }
            .reduce(0) { $0 + (notesCountByDay[dayKey($1)] ?? 0) }
    }
    
    // MARK: - Views
    
    var body: some View {
        Group {
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
        .onAppear { loadStatistics() }
    }

    // MARK: - Data Loading

    /// Fetches statistics using database-level fetchCount queries (no objects loaded).
    private func loadStatistics() {
        let calendar = Calendar.current
        
        // 1. Total count — fetchCount only, zero NoteItem objects loaded
        let countDesc = FetchDescriptor<NoteItem>(predicate: #Predicate { !$0.isDeleted })
        totalNotes = (try? modelContext.fetchCount(countDesc)) ?? 0

        // 2. Calendar (90 days ~3 months) — fetchCount per day with date range predicate
        var dayStats: [String: Int] = [:]
        for day in 0..<90 {
            guard let date = calendar.date(byAdding: .day, value: -day, to: Date()) else { continue }
            let startOfDay = calendar.startOfDay(for: date)
            guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { continue }
            
            let descriptor = FetchDescriptor<NoteItem>(
                predicate: #Predicate<NoteItem> { note in
                    !note.isDeleted && note.createdAt >= startOfDay && note.createdAt < endOfDay
                }
            )
            let count = (try? modelContext.fetchCount(descriptor)) ?? 0
            if count > 0 {
                dayStats[dayKey(startOfDay)] = count
            }
        }
        notesCountByDay = dayStats

        // 3. Tag distribution — use tag.notes relationship (loads notes but avoids N queries)
        let tagDesc = FetchDescriptor<TagItem>()
        let tags = (try? modelContext.fetch(tagDesc)) ?? []
        tagStats = tags
            .map { TagStat(tagName: $0.name, count: $0.notes.filter { !$0.isDeleted }.count) }
            .filter { $0.count > 0 }
            .sorted { $0.count > $1.count }
            .prefix(5)
            .map { $0 }
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
                    Text("最活跃标签")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(mostActiveTag ?? "无")
                        .font(.headline)
                }
                Spacer()
            }
        }
    }
    
    // MARK: - Full Page View
    private var fullPageView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Summary Cards
                HStack(spacing: 16) {
                    summaryCard(title: "总笔记", value: "\(totalNotes)", icon: "doc.text.fill", color: theme.colors.accent)
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
        
        // 生成最近 3 个月
        let months = (0..<3).compactMap { i in
            calendar.date(byAdding: .month, value: -i, to: today)
        }.reversed()
        let monthArray = Array(months)
        
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    let countByDay = notesCountByDay
                    ForEach(monthArray, id: \.self) { month in
                        MonthCalendarView(month: month, notesCountByDay: countByDay)
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
        buildDayStats(days: 7)
    }
    
    private func getLast15DaysStats() -> [DateStat] {
        buildDayStats(days: 15)
    }

    private func getLast30DaysStats() -> [DateStat] {
        buildDayStats(days: 30)
    }
    
    private func getContributionData() -> [DateStat] {
        buildDayStats(days: 84, reversed: false)
    }

    /// Builds per-day stats using a single O(N) dictionary lookup instead of
    /// repeating an O(N) filter for every day.
    private func buildDayStats(days: Int, reversed: Bool = true) -> [DateStat] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let countByDay = notesCountByDay
        let stats = (0..<days).compactMap { i -> DateStat? in
            let offset = reversed ? -i : -(days - 1 - i)
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            return DateStat(date: date, count: countByDay[dayKey(date)] ?? 0)
        }
        return reversed ? stats.reversed() : stats
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
        tagStats
    }
    
    private var mostActiveTag: String? {
        getTagStats().first?.tagName
    }
}

struct MonthCalendarView: View {
    let month: Date
    /// Pre-aggregated map of "yyyy-MM-dd" → note count, passed from parent.
    let notesCountByDay: [String: Int]
    @Environment(\.appTheme) private var theme
    private let calendar = Calendar.current

    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    
    // Grid Setup
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    
    private var monthName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年 M月"
        return formatter.string(from: month)
    }
    
    private var days: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let firstDay = monthInterval.start
        let numDays = calendar.range(of: .day, in: .month, for: firstDay)?.count ?? 0
        let firstWeekday = calendar.component(.weekday, from: firstDay)

        // Leading nil placeholders + actual dates + trailing nil padding (42 = 6 rows × 7 cols)
        let leadingNils = Array(repeating: nil as Date?, count: firstWeekday - 1)
        let monthDays: [Date?] = (0..<numDays).compactMap { calendar.date(byAdding: .day, value: $0, to: firstDay) }
        let trailingNils = Array(repeating: nil as Date?, count: max(0, 42 - leadingNils.count - monthDays.count))
        return leadingNils + monthDays + trailingNils
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
                        
                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(colorForCount(count))
                                .aspectRatio(1, contentMode: .fit)
                            
                            Text("\(dayNum)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(count > 0 ? .white.opacity(0.85) : .primary)
                                .padding([.top, .leading], 3)
                            
                            if count > 0 {
                                Text("\(count)")
                                    .font(.system(size: 11, weight: .black))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .padding(.bottom, 2)
                            }
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
        let key = Self.dayKeyFormatter.string(from: date)
        return notesCountByDay[key] ?? 0
    }
    
    private func colorForCount(_ count: Int) -> Color {
        if count == 0 { return Color(.secondarySystemFill) }
        if count == 1 { return theme.colors.accent.opacity(0.4) }
        if count <= 3 { return theme.colors.accent.opacity(0.7) }
        return theme.colors.accent
    }
}

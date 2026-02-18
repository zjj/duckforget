import SwiftUI
import SwiftData
import Charts

struct StatisticsWidget: View {
    @Environment(NoteStore.self) var noteStore
    var size: WidgetSize
    
    @Query(sort: \NoteItem.createdAt, order: .reverse) var allNotes: [NoteItem]
    
    // MARK: - Computed Stats
    
    private var totalNotes: Int {
        allNotes.filter { !$0.isDeleted }.count
    }
    
    private var totalAttachments: Int {
        allNotes.filter { !$0.isDeleted }.reduce(0) { $0 + $1.attachments.count }
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
        Group {
            switch size {
            case .small:
                smallView
            case .medium:
                mediumView
            case .large:
                largeView
            case .fullPage:
                fullPageView
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 3)
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
                    .foregroundColor(.accentColor)
            }
        }
    }
    
    // MARK: - Medium View (Weekly Trend)
    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("本周趋势", systemImage: "chart.bar.fill")
                    .font(.headline)
                    .foregroundColor(.accentColor)
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
                    .foregroundStyle(Color.accentColor.gradient)
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
            let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 12)
            
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
                
                // Weekly Chart
                VStack(alignment: .leading) {
                    Text("近期趋势")
                        .font(.headline)
                    
                    if #available(iOS 16.0, *) {
                        Chart(getLast30DaysStats(), id: \.date) { item in
                            BarMark(
                                x: .value("Date", item.date, unit: .day),
                                y: .value("Count", item.count)
                            )
                            .foregroundStyle(Color.accentColor)
                        }
                        .frame(height: 200)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
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
                            }
                            .frame(height: 200)
                        }
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
            }
            .padding()
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
        .background(Color(.secondarySystemBackground))
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
        if count == 1 { return Color.accentColor.opacity(0.3) }
        if count <= 3 { return Color.accentColor.opacity(0.6) }
        return Color.accentColor
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

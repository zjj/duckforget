import SwiftUI
import SwiftData

// MARK: - CalendarWidget

/// 月历组件：仅支持最近两个月，左右原生翻页（TabView.page）切换
/// 每天悬浮显示当天创建的笔记数量，点击跳转当日笔记页
struct CalendarWidget: View {
    @Environment(NoteStore.self) var noteStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var theme

    let size: WidgetSize
    let isEditing: Bool

    /// 0 = 上个月  1 = 本月（默认本月）
    @State private var pageIndex: Int = 1
    /// 点击日期后的目标（nil = 不导航）
    @State private var selectedDay: Date? = nil

    // ── 笔记缓存：key = "yyyy-MM"
    @State private var noteCache: [String: [Int: Int]] = [:]

    private let cal = Calendar.current

    // MARK: - Allowed months [上月, 本月]

    private var allowedMonths: [Date] {
        let now     = cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
        let prev    = cal.date(byAdding: .month, value: -1, to: now) ?? now
        return [prev, now]
    }

    // MARK: - Helpers

    private func monthStart(_ date: Date) -> Date {
        cal.date(from: cal.dateComponents([.year, .month], from: date)) ?? date
    }

    private func monthKey(_ date: Date) -> String {
        let s = monthStart(date)
        let y = cal.component(.year, from: s)
        let m = cal.component(.month, from: s)
        return "\(y)-\(m)"
    }

    private func calendarDays(for start: Date) -> [Date?] {
        let daysInMonth = cal.range(of: .day, in: .month, for: start)!.count
        let firstWeekday = cal.component(.weekday, from: start)
        let leading = (firstWeekday - cal.firstWeekday + 7) % 7
        var days: [Date?] = Array(repeating: nil, count: leading)
        for i in 0..<daysInMonth {
            days.append(cal.date(byAdding: .day, value: i, to: start))
        }
        while days.count % 7 != 0 { days.append(nil) }
        return days
    }

    private var weekdayHeaders: [String] {
        let symbols = cal.veryShortWeekdaySymbols
        let offset  = cal.firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }

    private func monthTitle(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.dateFormat = "yyyy年M月"
        return fmt.string(from: date)
    }

    /// 月历网格行数 → 动态高度
    private func gridRows(for start: Date) -> Int {
        calendarDays(for: start).count / 7
    }

    private func gridHeight(for start: Date) -> CGFloat {
        CGFloat(gridRows(for: start)) * 50 // 44 cell + 6 spacing
    }

    // MARK: - Body

    var body: some View {
        if size == .small {
            smallView
        } else {
            fullView
        }
    }

    // MARK: - Small

    private var smallView: some View {
        let month = allowedMonths[pageIndex]
        let count = noteCache[monthKey(month)]?.values.reduce(0, +) ?? 0
        return VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(theme.colors.accent.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: "calendar")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(theme.colors.accent)
                    .symbolRenderingMode(.hierarchical)
            }
            Text(monthTitle(month))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.colors.primaryText)
            Text("\(count) 条笔记")
                .font(.system(size: 11))
                .foregroundStyle(theme.colors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(theme.colors.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
        )
        .shadow(color: theme.colors.shadow, radius: 6, x: 0, y: 2)
        .onAppear { fetchAll() }
    }

    // MARK: - Full

    private var fullView: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── 月份标题 + 分页点 ──────────────────────────────────
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .foregroundStyle(theme.colors.accent)
                    .font(.system(size: 14, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                Text(monthTitle(allowedMonths[pageIndex]))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.colors.secondaryText)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.2), value: pageIndex)
                Spacer()
                HStack(spacing: 5) {
                    ForEach(0..<2, id: \.self) { idx in
                        Capsule()
                            .fill(idx == pageIndex
                                  ? theme.colors.accent
                                  : theme.colors.accent.opacity(0.2))
                            .frame(width: idx == pageIndex ? 16 : 5,
                                   height: 5)
                            .animation(.easeInOut(duration: 0.2), value: pageIndex)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)

            // ── 周标题（静态）────────────────────────────────────────
            HStack(spacing: 0) {
                ForEach(weekdayHeaders, id: \.self) { sym in
                    Text(sym)
                        .font(.caption2).fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 4)

            // ── 原生翻页 TabView ─────────────────────────────────────
            // 高度取两个月最大行数，保证切换时不跳变
            let maxHeight = allowedMonths.map { gridHeight(for: monthStart($0)) }.max() ?? 300

            TabView(selection: $pageIndex) {
                ForEach(Array(allowedMonths.enumerated()), id: \.offset) { idx, month in
                    let start = monthStart(month)
                    let counts = noteCache[monthKey(month)] ?? [:]
                    calendarGrid(for: start, counts: counts)
                        .tag(idx)
                        // TabView 子视图需要 frame 才能正确布局
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: maxHeight + 12) // +12 for bottom padding
            .disabled(isEditing)
        }
        .background(theme.colors.card)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(color: theme.colors.shadow, radius: 8, x: 0, y: 2)
        // 单一 navigationDestination：Button 设 selectedDay，这里统一 push
        .navigationDestination(item: $selectedDay) { day in
            DayNotesPage(date: day).environment(noteStore)
        }
        .onAppear { fetchAll() }
    }

    // MARK: - Calendar Grid

    @ViewBuilder
    private func calendarGrid(for start: Date, counts: [Int: Int]) -> some View {
        let days = calendarDays(for: start)
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7),
            spacing: 6
        ) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                if let date = date {
                    let day     = cal.component(.day, from: date)
                    let count   = counts[day] ?? 0
                    let isToday = cal.isDateInToday(date)
                    if isEditing {
                        CalendarDayCell(day: day, noteCount: count, isToday: isToday)
                    } else {
                        Button {
                            selectedDay = date
                        } label: {
                            CalendarDayCell(day: day, noteCount: count, isToday: isToday)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Color.clear.frame(height: 44)
                }
            }
        }
        .padding(.horizontal, 10)
    }

    // MARK: - Data

    private func fetchAll() {
        for month in allowedMonths {
            fetchMonth(month)
        }
    }

    private func fetchMonth(_ date: Date) {
        let start = monthStart(date)
        let end   = cal.date(byAdding: .month, value: 1, to: start) ?? start
        let key   = monthKey(date)
        let descriptor = FetchDescriptor<NoteItem>(
            predicate: #Predicate { note in
                !note.isDeleted && note.createdAt >= start && note.createdAt < end
            }
        )
        let notes = (try? modelContext.fetch(descriptor)) ?? []
        var counts: [Int: Int] = [:]
        for note in notes {
            let day = cal.component(.day, from: note.createdAt)
            counts[day, default: 0] += 1
        }
        noteCache[key] = counts
    }
}

// MARK: - CalendarDayCell

/// 单日格：数字 + 悬浮在 z 方向的笔记数量徽章
private struct CalendarDayCell: View {
    let day: Int
    let noteCount: Int
    let isToday: Bool

    @Environment(\.appTheme) private var theme

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // ── 日期圆圈 ──────────────────────────────────────────────
            Text("\(day)")
                .font(.system(size: 13, weight: isToday ? .bold : .regular))
                .foregroundColor(
                    isToday
                        ? .white
                        : (noteCount > 0 ? theme.colors.primaryText : theme.colors.secondaryText)
                )
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(
                            isToday
                                ? theme.colors.accent
                                : (noteCount > 0 ? theme.colors.accentSoft : Color.clear)
                        )
                )
                .frame(maxWidth: .infinity)

            // ── 悬浮笔记数量徽章（z 方向浮于日期格右上角）──────────────
            if noteCount > 0 {
                Text(noteCount > 99 ? "99+" : "\(noteCount)")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(isToday ? theme.colors.accent : .white)
                    .padding(.horizontal, 3.5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(isToday ? Color.white.opacity(0.95) : theme.colors.accent)
                    )
                    .offset(x: 2, y: -2)
                    .zIndex(1)
            }
        }
        .frame(height: 44)
    }
}

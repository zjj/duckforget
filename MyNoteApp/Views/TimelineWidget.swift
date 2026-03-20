import SwiftUI
import SwiftData

// MARK: - TimelineWidget

/// 时间轴组件 — 按创建时间倒序展示所有笔记，仅支持 fullPage 尺寸
struct TimelineWidget: View {
    let isEditing: Bool

    @Environment(NoteStore.self) private var noteStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var theme
    @Environment(FontManager.self) private var fontManager

    @State private var notes: [NoteItem] = []
    @State private var fetchLimit: Int = 50
    @State private var hasMore: Bool = true
    @State private var selectedNote: NoteItem?
    @State private var listID = UUID()

    private let pageSize = 50

    // MARK: - Day Groups

    private var dayGroups: [(label: String, id: String, notes: [NoteItem])] {
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.dateFormat = "yyyy年M月d日"
        let isoFmt = ISO8601DateFormatter()

        var result: [(label: String, id: String, notes: [NoteItem])] = []
        var seen: [Date: Int] = [:]

        for note in notes {
            let day = cal.startOfDay(for: note.createdAt)
            if let idx = seen[day] {
                result[idx].notes.append(note)
            } else {
                seen[day] = result.count
                let label: String
                if cal.isDateInToday(day) {
                    label = "今天"
                } else if cal.isDateInYesterday(day) {
                    label = "昨天"
                } else {
                    label = fmt.string(from: day)
                }
                let id = isoFmt.string(from: day)
                result.append((label: label, id: id, notes: [note]))
            }
        }
        return result
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                headerBar

                Divider()
                    .opacity(0.5)

                List {
                    ForEach(dayGroups, id: \.id) { group in
                        Section {
                            ForEach(group.notes) { note in
                                TimelineNoteRow(note: note, onSelect: { _ in selectedNote = note })
                                    .environment(noteStore)
                                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                            }
                        } header: {
                            daySectionHeader(label: group.label)
                        }
                        .listSectionSeparator(.hidden)
                    }

                    // Pagination sentinel at bottom
                    if hasMore {
                        Color.clear
                            .frame(height: 1)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .onAppear { loadMore() }
                    } else if !notes.isEmpty {
                        Text("没有更多记录了")
                            .font(.caption)
                            .foregroundColor(theme.colors.secondaryText.opacity(0.4))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }

                    if notes.isEmpty {
                        emptyState
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .id(listID)
                .frame(height: max(geo.size.height - 46, 100))
            }
            .background(theme.colors.card)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
            .shadow(color: theme.colors.shadow, radius: 8, x: 0, y: 2)
        }
        .onAppear { loadNotes() }
        .onChange(of: noteStore.contentRevision) {
            loadNotes()
            listID = UUID()
        }
        .navigationDestination(item: $selectedNote) { note in
            NoteView(note: note, startInEditMode: false)
                .environment(noteStore)
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar.day.timeline.left")
                .foregroundColor(theme.colors.accent)
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
            Text("时间轴")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(theme.colors.secondaryText)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(height: 46)
    }

    // MARK: - Day Section Header

    private func daySectionHeader(label: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(theme.colors.secondaryText.opacity(0.65))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(theme.colors.card)
        .textCase(nil)
        .listRowInsets(EdgeInsets())
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.day.timeline.left")
                .font(.system(size: 38))
                .foregroundColor(theme.colors.secondaryText.opacity(0.25))
            Text("还没有任何记录")
                .font(.subheadline)
                .foregroundColor(theme.colors.secondaryText.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Data Fetching

    private func loadNotes() {
        var descriptor = FetchDescriptor<NoteItem>(
            predicate: #Predicate { !$0.isDeleted }
        )
        descriptor.sortBy = [SortDescriptor(\.createdAt, order: .reverse)]
        descriptor.fetchLimit = fetchLimit
        let fetched = (try? modelContext.fetch(descriptor)) ?? []
        notes = fetched

        let countDesc = FetchDescriptor<NoteItem>(
            predicate: #Predicate { !$0.isDeleted }
        )
        let total = (try? modelContext.fetchCount(countDesc)) ?? 0
        hasMore = fetched.count >= fetchLimit && fetched.count < total
    }

    private func loadMore() {
        fetchLimit += pageSize
        loadNotes()
    }
}

// MARK: - TimelineNoteRow

private struct TimelineNoteRow: View {
    let note: NoteItem
    let onSelect: (NoteItem) -> Void

    @Environment(NoteStore.self) private var noteStore
    @Environment(\.appTheme) private var theme
    @Environment(FontManager.self) private var fontManager

    private var timeText: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: note.createdAt)
    }

    var body: some View {
        Button { onSelect(note) } label: {
            HStack(alignment: .top, spacing: 0) {
                // ── 时间列 ──────────────────────────
                Text(timeText)
                    .font(.system(size: 11.5, weight: .light, design: .monospaced))
                    .foregroundColor(theme.colors.secondaryText.opacity(0.6))
                    .frame(width: 42, alignment: .leading)
                    .padding(.top, 14)
                    .padding(.leading, 16)

                // ── 时间线竖脊 ────────────────────────
                timelineSpine

                // ── 笔记卡片（完整预览 + 附件马赛克）──────────
                NoteRowView(note: note, showDateFooter: false)
                    .environment(noteStore)
                    .padding(.leading, 8)
                    .padding(.trailing, 12)
                    .padding(.vertical, 8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // 点 + 竖线
    private var timelineSpine: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(theme.colors.border.opacity(0.45))
                .frame(width: 1)
                .frame(maxHeight: .infinity)
            Circle()
                .strokeBorder(theme.colors.border.opacity(0.9), lineWidth: 1)
                .background(Circle().fill(theme.colors.surface))
                .frame(width: 7, height: 7)
                .padding(.top, 14)
        }
        .frame(width: 14)
        .padding(.horizontal, 6)
    }
}

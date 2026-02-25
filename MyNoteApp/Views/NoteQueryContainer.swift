import NaturalLanguage
import SwiftData
import SwiftUI

// MARK: - NoteFilterMode

/// DB 层过滤模式（4 种基础组合 × 有/无 firstToken = 8 种 #Predicate 穷举）
enum NoteFilterMode {
    case all
    case byTag(name: String)
    case dateRange(start: Date, end: Date)
    case byTagAndDateRange(name: String, start: Date, end: Date)
}

// MARK: - NoteQueryContainer

/// 持有动态 @Query，在 DB 层完成 isDeleted / 标签 / 日期 / 第一个词预过滤；
/// 内存层仅对缩小后的结果集做完整多词匹配，再按 sortMode 排序，最终交给 NoteListContentView 渲染。
struct NoteQueryContainer: View {
    @Query var notes: [NoteItem]

    let searchText: String
    let viewMode: ViewMode
    let sortMode: SortMode
    let isEmbedded: Bool
    let onSearchTap: (() -> Void)?
    let filterTagName: String? // 用于 NoteListContentView 的空状态文案

    @Environment(NoteStore.self) var noteStore

    init(
        filterMode: NoteFilterMode,
        searchText: String,
        viewMode: ViewMode,
        sortMode: SortMode,
        isEmbedded: Bool = false,
        onSearchTap: (() -> Void)? = nil,
        filterTagName: String? = nil
    ) {
        self.searchText = searchText
        self.viewMode = viewMode
        self.sortMode = sortMode
        self.isEmbedded = isEmbedded
        self.onSearchTap = onSearchTap
        self.filterTagName = filterTagName

        let firstToken = NoteQueryContainer.extractFirstToken(from: searchText)

        // 穷举 8 种（4 基础模式 × 有/无 firstToken），绕过 #Predicate 不支持动态分支的限制
        let descriptor: FetchDescriptor<NoteItem>
        switch (filterMode, firstToken) {

        case (.all, nil):
            descriptor = FetchDescriptor<NoteItem>(
                predicate: #Predicate<NoteItem> { $0.isDeleted == false }
            )

        case (.all, let token?):
            descriptor = FetchDescriptor<NoteItem>(
                predicate: #Predicate<NoteItem> { note in
                    note.isDeleted == false
                        && note.content.localizedStandardContains(token)
                }
            )

        case (.byTag(let name), nil):
            descriptor = FetchDescriptor<NoteItem>(
                predicate: #Predicate<NoteItem> { note in
                    note.isDeleted == false
                        && note.tags.contains { $0.name == name }
                }
            )

        case (.byTag(let name), let token?):
            descriptor = FetchDescriptor<NoteItem>(
                predicate: #Predicate<NoteItem> { note in
                    note.isDeleted == false
                        && note.tags.contains { $0.name == name }
                        && note.content.localizedStandardContains(token)
                }
            )

        case (.dateRange(let start, let end), nil):
            descriptor = FetchDescriptor<NoteItem>(
                predicate: #Predicate<NoteItem> { note in
                    note.isDeleted == false
                        && note.updatedAt >= start
                        && note.updatedAt < end
                }
            )

        case (.dateRange(let start, let end), let token?):
            descriptor = FetchDescriptor<NoteItem>(
                predicate: #Predicate<NoteItem> { note in
                    note.isDeleted == false
                        && note.updatedAt >= start
                        && note.updatedAt < end
                        && note.content.localizedStandardContains(token)
                }
            )

        case (.byTagAndDateRange(let name, let start, let end), nil):
            descriptor = FetchDescriptor<NoteItem>(
                predicate: #Predicate<NoteItem> { note in
                    note.isDeleted == false
                        && note.tags.contains { $0.name == name }
                        && note.updatedAt >= start
                        && note.updatedAt < end
                }
            )

        case (.byTagAndDateRange(let name, let start, let end), let token?):
            descriptor = FetchDescriptor<NoteItem>(
                predicate: #Predicate<NoteItem> { note in
                    note.isDeleted == false
                        && note.tags.contains { $0.name == name }
                        && note.updatedAt >= start
                        && note.updatedAt < end
                        && note.content.localizedStandardContains(token)
                }
            )
        }

        _notes = Query(descriptor)
    }

    // MARK: - First-token extraction (DB pre-filter)

    /// 从查询字符串提取第一个词元，供 DB 层两阶段过滤使用（只取第一词缩量；完整多词匹配在内存层完成）
    static func extractFirstToken(from query: String) -> String? {
        guard !query.isEmpty else { return nil }
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = query
        var first: String?
        tokenizer.enumerateTokens(in: query.startIndex..<query.endIndex) { range, _ in
            first = String(query[range])
            return false // 只取第一个
        }
        return first
    }

    // MARK: - Memory sort + full multi-token filtering

    private var sortedNotes: [NoteItem] {
        switch sortMode {
        case .dateModified:
            return notes.sorted { $0.updatedAt > $1.updatedAt }
        case .dateCreated:
            return notes.sorted { $0.createdAt > $1.createdAt }
        case .title:
            return notes.sorted {
                $0.preview.localizedCaseInsensitiveCompare($1.preview) == .orderedAscending
            }
        }
    }

    /// Token Match：对查询字符串分词，要求所有词元均出现在笔记内容中
    private func noteMatchesQuery(_ note: NoteItem, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = query
        var tokens: [String] = []
        tokenizer.enumerateTokens(in: query.startIndex..<query.endIndex) { range, _ in
            tokens.append(String(query[range]))
            return true
        }
        guard !tokens.isEmpty else {
            return note.content.localizedCaseInsensitiveContains(query)
        }
        return tokens.allSatisfy { note.content.localizedCaseInsensitiveContains($0) }
    }

    /// DB 已过滤 → 内存完整多词匹配 → 排序后的最终展示列表
    var displayNotes: [NoteItem] {
        let sorted = sortedNotes
        guard !searchText.isEmpty else { return sorted }
        return sorted.filter { noteMatchesQuery($0, query: searchText) }
    }

    var body: some View {
        NoteListContentView(
            notes: displayNotes,
            viewMode: viewMode,
            sortMode: sortMode,
            isEmbedded: isEmbedded,
            onSearchTap: onSearchTap,
            filterTagName: filterTagName,
            searchText: searchText
        )
        .environment(noteStore)
    }
}

// MARK: - NoteListContentView

/// 纯渲染层：不持有 @Query，只渲染调用方传入的 notes 数组。
/// 支持列表 / 网格 / 嵌入预览 / 空状态四种展示模式。
struct NoteListContentView: View {
    let notes: [NoteItem]
    let viewMode: ViewMode
    let sortMode: SortMode
    var isEmbedded: Bool = false
    var onSearchTap: (() -> Void)? = nil
    var filterTagName: String? = nil  // 用于空状态文案
    var searchText: String = ""       // 用于空状态文案判断

    @Environment(NoteStore.self) var noteStore
    @State private var noteToDelete: NoteItem?
    @State private var showDeleteConfirmation = false

    // MARK: - Date Grouping

    private var groupedNotes: [(DateSection, [NoteItem])] {
        let kp: KeyPath<NoteItem, Date> = sortMode == .dateCreated ? \.createdAt : \.updatedAt
        return groupNotesByDate(notes, dateKeyPath: kp)
    }

    // MARK: - Body

    var body: some View {
        Group {
            if notes.isEmpty {
                emptyStateView
            } else if isEmbedded {
                embeddedListView
            } else {
                fullContentView
            }
        }
        .alert("确认删除", isPresented: $showDeleteConfirmation) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                if let note = noteToDelete {
                    noteStore.softDeleteNote(note)
                    noteToDelete = nil
                }
            }
        } message: {
            Text("确定要删除这条笔记吗？删除后将移至废纸篓。")
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyStateView: some View {
        ContentUnavailableView {
            if let tag = filterTagName {
                Label(
                    searchText.isEmpty ? "此标签下暂无记录" : "无匹配结果",
                    systemImage: "tag"
                )
            } else {
                Label(
                    searchText.isEmpty ? "暂无记录" : "无匹配结果",
                    systemImage: "note.text"
                )
            }
        } description: {
            if let tag = filterTagName, searchText.isEmpty {
                Text("创建记录并添加 \(tag) 标签")
            } else if !searchText.isEmpty {
                Text("尝试其他关键词")
            }
        }
    }

    // MARK: - Embedded Preview (≤20 rows + "查看更多")

    private var embeddedListView: some View {
        let displayLimit = 20
        let displayed = Array(notes.prefix(displayLimit))
        return LazyVStack(spacing: 0) {
            ForEach(displayed) { note in
                NavigationLink {
                    NoteView(note: note, startInEditMode: false)
                        .environment(noteStore)
                } label: {
                    VStack(spacing: 0) {
                        NoteRowView(note: note)
                            .environment(noteStore)
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                        Divider()
                            .padding(.leading)
                    }
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(role: .destructive) {
                        noteToDelete = note
                        showDeleteConfirmation = true
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
            if notes.count > displayLimit {
                Button("查看更多") {
                    onSearchTap?()
                }
                .padding()
                .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Full List / Grid

    @ViewBuilder
    private var fullContentView: some View {
        if viewMode == .list {
            listModeView
        } else {
            gridModeView
        }
    }

    private var listModeView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if sortMode == .dateModified || sortMode == .dateCreated {
                    ForEach(groupedNotes, id: \.0) { section, sectionNotes in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(section.rawValue)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 4)
                                .padding(.top, 8)
                            noteRows(sectionNotes)
                        }
                    }
                } else {
                    noteRows(notes)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private var gridModeView: some View {
        let columns = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                if sortMode == .dateModified || sortMode == .dateCreated {
                    ForEach(groupedNotes, id: \.0) { section, sectionNotes in
                        Text(section.rawValue)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.top, 8)
                            .gridCellColumns(2)
                        noteGridItems(sectionNotes)
                    }
                } else {
                    noteGridItems(notes)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func noteRows(_ rowNotes: [NoteItem]) -> some View {
        ForEach(rowNotes) { note in
            NavigationLink {
                NoteView(note: note, startInEditMode: false)
                    .environment(noteStore)
            } label: {
                NoteRowView(note: note)
                    .environment(noteStore)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(role: .destructive) {
                    noteToDelete = note
                    showDeleteConfirmation = true
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder
    private func noteGridItems(_ gridNotes: [NoteItem]) -> some View {
        ForEach(gridNotes) { note in
            NavigationLink {
                NoteView(note: note, startInEditMode: false)
                    .environment(noteStore)
            } label: {
                GridNoteCard(note: note)
                    .environment(noteStore)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(role: .destructive) {
                    noteToDelete = note
                    showDeleteConfirmation = true
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        }
    }
}

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
    /// 按 createdAt 精确日期范围过滤（用于月历点击某天）
    case createdDateRange(start: Date, end: Date)
}

// MARK: - NoteQueryContainer

/// 分页流式查询容器：每次从 DB 取 pageSize 条，滚动到底部自动加载下一页。
/// DB 层完成 isDeleted / 标签 / 日期 / 第一个词预过滤；内存层做完整多词匹配与排序。
struct NoteQueryContainer: View {
    // MARK: Inputs
    let filterMode: NoteFilterMode
    let searchText: String
    let viewMode: ViewMode
    let sortMode: SortMode
    let isEmbedded: Bool
    let onSearchTap: (() -> Void)?
    let filterTagName: String?
    let pageSize: Int

    // MARK: Pagination state
    @State private var fetchedNotes: [NoteItem] = []
    @State private var currentLimit: Int = 0     // grows by pageSize each page
    @State private var hasMore: Bool = true
    @State private var isLoadingMore: Bool = false

    @Environment(\.modelContext) private var modelContext
    @Environment(NoteStore.self) var noteStore

    init(
        filterMode: NoteFilterMode,
        searchText: String,
        viewMode: ViewMode,
        sortMode: SortMode,
        isEmbedded: Bool = false,
        onSearchTap: (() -> Void)? = nil,
        filterTagName: String? = nil,
        pageSize: Int = 100
    ) {
        self.filterMode = filterMode
        self.searchText = searchText
        self.viewMode = viewMode
        self.sortMode = sortMode
        self.isEmbedded = isEmbedded
        self.onSearchTap = onSearchTap
        self.filterTagName = filterTagName
        self.pageSize = pageSize
    }

    // MARK: - First-token extraction (DB pre-filter)

    /// 从查询字符串提取第一个词元，供 DB 层两阶段过滤使用
    static func extractFirstToken(from query: String) -> String? {
        guard !query.isEmpty else { return nil }
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = query
        var first: String?
        tokenizer.enumerateTokens(in: query.startIndex..<query.endIndex) { range, _ in
            first = String(query[range])
            return false
        }
        return first
    }

    // MARK: - Descriptor builder (called at fetch time, so Date() is always fresh)

    private func makeDescriptor(limit: Int, offset: Int = 0) -> FetchDescriptor<NoteItem> {
        let firstToken = NoteQueryContainer.extractFirstToken(from: searchText)

        // DB sort key matches the user's chosen sortMode so pagination fetches the
        // correct "next page" of notes. Title sort has no DB-level equivalent
        // (preview is computed), so fall back to updatedAt for the DB pass and
        // re-sort in memory.
        let dbSort: SortDescriptor<NoteItem>
        switch sortMode {
        case .dateModified: dbSort = SortDescriptor(\.updatedAt, order: .reverse)
        case .dateCreated:  dbSort = SortDescriptor(\.createdAt, order: .reverse)
        case .title:        dbSort = SortDescriptor(\.updatedAt, order: .reverse)
        }

        var descriptor: FetchDescriptor<NoteItem>
        switch (filterMode, firstToken) {
        case (.all, nil):
            descriptor = FetchDescriptor<NoteItem>(
                predicate: #Predicate { $0.isDeleted == false })

        case (.all, let token?):
            descriptor = FetchDescriptor<NoteItem>(
                predicate: #Predicate { note in
                    note.isDeleted == false && note.forSearch.localizedStandardContains(token)
                })

        case (.byTag(let name), nil):
            descriptor = FetchDescriptor<NoteItem>(
                predicate: #Predicate { note in
                    note.isDeleted == false && note.tags.contains { $0.name == name }
                })

        case (.byTag(let name), let token?):
            descriptor = FetchDescriptor<NoteItem>(
                predicate: #Predicate { note in
                    note.isDeleted == false
                        && note.tags.contains { $0.name == name }
                        && note.forSearch.localizedStandardContains(token)
                })

        case (.dateRange(let start, let end), nil):
            descriptor = FetchDescriptor<NoteItem>(
                predicate: #Predicate { note in
                    note.isDeleted == false && note.updatedAt >= start && note.updatedAt < end
                })

        case (.dateRange(let start, let end), let token?):
            descriptor = FetchDescriptor<NoteItem>(
                predicate: #Predicate { note in
                    note.isDeleted == false
                        && note.updatedAt >= start && note.updatedAt < end
                        && note.forSearch.localizedStandardContains(token)
                })

        case (.byTagAndDateRange(let name, let start, let end), nil):
            descriptor = FetchDescriptor<NoteItem>(
                predicate: #Predicate { note in
                    note.isDeleted == false
                        && note.tags.contains { $0.name == name }
                        && note.updatedAt >= start && note.updatedAt < end
                })

        case (.byTagAndDateRange(let name, let start, let end), let token?):
            descriptor = FetchDescriptor<NoteItem>(
                predicate: #Predicate { note in
                    note.isDeleted == false
                        && note.tags.contains { $0.name == name }
                        && note.updatedAt >= start && note.updatedAt < end
                        && note.forSearch.localizedStandardContains(token)
                })

        case (.createdDateRange(let start, let end), nil):
            descriptor = FetchDescriptor<NoteItem>(
                predicate: #Predicate { note in
                    note.isDeleted == false && note.createdAt >= start && note.createdAt < end
                })

        case (.createdDateRange(let start, let end), let token?):
            descriptor = FetchDescriptor<NoteItem>(
                predicate: #Predicate { note in
                    note.isDeleted == false
                        && note.createdAt >= start && note.createdAt < end
                        && note.forSearch.localizedStandardContains(token)
                })
        }

        descriptor.sortBy = [dbSort]
        descriptor.fetchLimit = limit
        descriptor.fetchOffset = offset
        return descriptor
    }

    // MARK: - Fetch helpers

    /// 重置并从头加载第一页
    private func resetAndFetch() {
        let desc = makeDescriptor(limit: pageSize, offset: 0)
        let result = (try? modelContext.fetch(desc)) ?? []
        fetchedNotes = result
        currentLimit = pageSize
        // 如果返回条数等于 pageSize，说明可能还有更多
        hasMore = result.count == pageSize
        isLoadingMore = false
    }

    /// 追加加载下一页（用 offset 方式，避免重新发起全量查询）
    private func loadNextPage() {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        let offset = fetchedNotes.count
        let desc = makeDescriptor(limit: pageSize, offset: offset)
        let next = (try? modelContext.fetch(desc)) ?? []
        fetchedNotes.append(contentsOf: next)
        hasMore = next.count == pageSize
        isLoadingMore = false
    }

    // MARK: - Memory sort + full multi-token filtering

    private var sortedNotes: [NoteItem] {
        switch sortMode {
        case .dateModified:
            return fetchedNotes.sorted { $0.updatedAt > $1.updatedAt }
        case .dateCreated:
            return fetchedNotes.sorted { $0.createdAt > $1.createdAt }
        case .title:
            return fetchedNotes.sorted {
                $0.preview.localizedCaseInsensitiveCompare($1.preview) == .orderedAscending
            }
        }
    }

    private func noteMatchesQuery(_ note: NoteItem, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = query
        var tokens: [String] = []
        tokenizer.enumerateTokens(in: query.startIndex..<query.endIndex) { range, _ in
            tokens.append(String(query[range]))
            return true
        }
        guard !tokens.isEmpty else { return note.forSearch.localizedCaseInsensitiveContains(query) }
        return tokens.allSatisfy { note.forSearch.localizedCaseInsensitiveContains($0) }
    }

    var displayNotes: [NoteItem] {
        let sorted = sortedNotes.filter { !$0.isDeleted }
        guard !searchText.isEmpty else { return sorted }
        return sorted.filter { noteMatchesQuery($0, query: searchText) }
    }

    // MARK: - Body

    // filterMode has no Equatable, so we track changes via a string key
    private var filterKey: String {
        switch filterMode {
        case .all: return "all|\(searchText)|\(sortMode)"
        case .byTag(let n): return "tag:\(n)|\(searchText)|\(sortMode)"
        case .dateRange(let s, _): return "date:\(s.timeIntervalSince1970)|\(searchText)|\(sortMode)"
        case .byTagAndDateRange(let n, let s, _): return "tagdate:\(n):\(s.timeIntervalSince1970)|\(searchText)|\(sortMode)"
        case .createdDateRange(let s, _): return "created:\(s.timeIntervalSince1970)|\(searchText)|\(sortMode)"
        }
    }

    var body: some View {
        NoteListContentView(
            notes: displayNotes,
            viewMode: viewMode,
            sortMode: sortMode,
            isEmbedded: isEmbedded,
            onSearchTap: onSearchTap,
            filterTagName: filterTagName,
            searchText: searchText,
            hasMore: hasMore,
            isLoadingMore: isLoadingMore,
            onLoadMore: loadNextPage,
            onNoteDeleted: { note in
                fetchedNotes.removeAll { $0.id == note.id }
            }
        )
        .environment(noteStore)
        .task(id: filterKey) {
            resetAndFetch()
        }
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
    var filterTagName: String? = nil
    var searchText: String = ""
    var hasMore: Bool = false
    var isLoadingMore: Bool = false
    var onLoadMore: (() -> Void)? = nil
    var onNoteDeleted: ((NoteItem) -> Void)? = nil

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
                    onNoteDeleted?(note)
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
                paginationFooter
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

            paginationFooter
                .padding(.horizontal, 16)
        }
    }

    /// 底部分页触发器：出现在视口即自动加载下一页
    @ViewBuilder
    private var paginationFooter: some View {
        if isLoadingMore {
            HStack {
                Spacer()
                ProgressView()
                    .padding(.vertical, 12)
                Spacer()
            }
        } else if hasMore {
            Color.clear
                .frame(height: 1)
                .onAppear { onLoadMore?() }
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

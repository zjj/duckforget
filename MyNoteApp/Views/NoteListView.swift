import SwiftData
import SwiftUI

/// 记录列表主页 - 模仿 iOS 记录
struct NoteListView: View {
    let showAllNotes: Bool
    var initialSearchText: String = ""
    var hideSearchBar: Bool = false
    var hideBottomBar: Bool = false
    var hideNavigationTitle: Bool = false
    var viewMode: ViewMode = .list
    var sortMode: SortMode = .dateModified
    var filterRecentDays: Int? = nil // 筛选最近几天的记录（nil表示不筛选）
    var customTitle: String? = nil // 自定义标题

    @Environment(NoteStore.self) var noteStore
    @Query(
        filter: #Predicate<NoteItem> { $0.isDeleted == false },
        sort: \NoteItem.updatedAt,
        order: .reverse
    ) var allActiveNotes: [NoteItem]
    @State private var searchText = ""
    @State private var isSearching = false
    @FocusState private var searchFocused: Bool

    /// 当前显示的活跃记录
    private var scopedNotes: [NoteItem] {
        var notes: [NoteItem] = allActiveNotes
        
        // 如果设置了日期筛选，只显示最近N天的记录
        if let days = filterRecentDays {
            let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
            notes = notes.filter { $0.updatedAt >= cutoffDate }
        }
        
        return notes
    }

    /// 搜索过滤和排序
    private var filteredNotes: [NoteItem] {
        let base = scopedNotes
        let filtered = searchText.isEmpty ? base : base.filter { $0.content.localizedCaseInsensitiveContains(searchText) }
        
        // 应用排序
        switch sortMode {
        case .dateModified:
            return filtered.sorted { $0.updatedAt > $1.updatedAt }
        case .dateCreated:
            return filtered.sorted { $0.createdAt > $1.createdAt }
        case .title:
            return filtered.sorted { $0.preview.localizedCompare($1.preview) == .orderedAscending }
        }
    }
    
    /// 按日期分组的记录（用于列表和网格视图）
    private var groupedNotes: [(DateSection, [NoteItem])] {
        // 根据排序模式选择日期字段
        let dateKeyPath: KeyPath<NoteItem, Date> = sortMode == .dateCreated ? \.createdAt : \.updatedAt
        return groupNotesByDate(filteredNotes, dateKeyPath: dateKeyPath)
    }

    private var navigationTitle: String {
        // 如果有自定义标题，优先使用
        if let title = customTitle {
            return title
        }
        return showAllNotes ? "所有记录" : "记录"
    }

    var body: some View {
        VStack(spacing: 0) {
            // 列表区域
            Group {
                if scopedNotes.isEmpty && searchText.isEmpty {
                    emptyStateView
                } else {
                    notesListView
                }
            }

            if !hideBottomBar {
                Divider()

                // 底部搜索栏 + 新建按钮
                bottomBar
            }
        }
        .if(!hideNavigationTitle) { view in
            view.navigationTitle(navigationTitle)
        }
        .onAppear {
            if !initialSearchText.isEmpty {
                searchText = initialSearchText
                isSearching = true
            }
        }
        .onChange(of: initialSearchText) { _, newValue in
            searchText = newValue
            if !newValue.isEmpty {
                isSearching = true
            }
        }
    }

    // MARK: - 底部栏：搜索 + 计数 + 新建

    private var bottomBar: some View {
        VStack(spacing: 0) {
            // 搜索栏（展开时显示）
            if isSearching && !hideSearchBar {
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                            .font(.subheadline)

                        TextField("搜索", text: $searchText)
                            .focused($searchFocused)
                            .font(.subheadline)

                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                    .font(.subheadline)
                            }
                        }
                    }
                    .padding(8)
                    .background(Color(.systemGray5))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    Button("取消") {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            searchText = ""
                            isSearching = false
                            searchFocused = false
                        }
                    }
                    .font(.subheadline)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // 工具栏行
            HStack {
                // 搜索按钮
                if !isSearching {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isSearching = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            searchFocused = true
                        }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 18))
                    }
                }

                Spacer()

                Text("\(scopedNotes.count) 个记录")
                    .font(.footnote)
                    .foregroundColor(.secondary)

                Spacer()

                NavigationLink {
                    NewNoteEditorView()
                        .environment(noteStore)
                } label: {
                    Image(systemName: "text.pad.header.badge.plus")
                        .font(.system(size: 22))
                        .fontWeight(.semibold)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color(.systemBackground))
    }

    // MARK: - 空状态

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "note.text")
                .font(.system(size: 64))
                .foregroundColor(.secondary.opacity(0.6))
            Text("没有记录")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("点击右下角按钮创建新记录")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.7))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 列表

    private var notesListView: some View {
        ScrollView {
            if viewMode == .list {
                LazyVStack(spacing: 8) {
                    // 按日期分组显示（仅在按日期排序时）
                    if sortMode == .dateModified || sortMode == .dateCreated {
                        ForEach(groupedNotes, id: \.0) { section, notes in
                            VStack(alignment: .leading, spacing: 8) {
                                // 日期段标题
                                Text(section.rawValue)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 4)
                                    .padding(.top, 8)
                                
                                // 该段的记录
                                noteRows(notes)
                            }
                        }
                    } else {
                        // 按标题排序时不分组
                        noteRows(filteredNotes)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            } else {
                let columns = [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ]
                LazyVGrid(columns: columns, spacing: 12) {
                    // 按日期分组显示（仅在按日期排序时）
                    if sortMode == .dateModified || sortMode == .dateCreated {
                        ForEach(groupedNotes, id: \.0) { section, notes in
                            // 日期段标题（占满两列）
                            Text(section.rawValue)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 4)
                                .padding(.top, 8)
                                .gridCellColumns(2)
                            
                            // 该段的记录
                            noteGridItems(notes)
                        }
                    } else {
                        // 按标题排序时不分组
                        noteGridItems(filteredNotes)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder
    private func noteRows(_ notes: [NoteItem]) -> some View {
        ForEach(notes) { note in
            NavigationLink {
                NoteEditorView(note: note)
                    .environment(noteStore)
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    // 第一行：标签 + 时间（右对齐）
                    HStack(spacing: 6) {
                        if !note.tags.isEmpty {
                            let maxTagsToShow = 5
                            let displayTags = Array(note.tags.prefix(maxTagsToShow))
                            let remainingCount = note.tags.count - maxTagsToShow
                            
                            HStack(spacing: 6) {
                                ForEach(displayTags) { tag in
                                    Text(tag.name)
                                        .font(.caption2)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.accentColor)
                                        .cornerRadius(4)
                                }
                                
                                if remainingCount > 0 {
                                    Text("+\(remainingCount)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        } else {
                            Spacer()
                                .frame(height: 24)
                        }
                        
                        Spacer()
                        
                        Text(note.createdAt.formattedAbsolute)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(height: 24)
                    
                    // 第二行：文字
                    Text(note.preview)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                        .foregroundColor(.primary)
                        .frame(height: 40, alignment: .leading)
                    
                    // 第三行：附件图标
                    if !note.attachments.isEmpty {
                        let noteAttachments = note.attachments.sorted { $0.createdAt < $1.createdAt }
                        HStack(spacing: 6) {
                            ForEach(noteAttachments.prefix(6)) { att in
                                AttachmentMiniIcon(type: att.type)
                            }
                            if noteAttachments.count > 6 {
                                Text("+\(noteAttachments.count - 6)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(height: 24)
                    } else {
                        Spacer()
                            .frame(height: 24)
                    }
                }
                .frame(height: 100)
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(role: .destructive) {
                    noteStore.softDeleteNote(note)
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        }
    }
    
    // MARK: - 网格视图项
    
    @ViewBuilder
    private func noteGridItems(_ notes: [NoteItem]) -> some View {
        ForEach(notes) { note in
            NavigationLink {
                NoteEditorView(note: note)
                    .environment(noteStore)
            } label: {
                GridNoteCard(note: note)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(role: .destructive) {
                    noteStore.softDeleteNote(note)
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        }
    }
}

// A helper to conditionally apply modifiers
extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}


/// 在 onAppear 时创建新记录，然后显示编辑器
struct NewNoteEditorView: View {
    @Environment(NoteStore.self) var noteStore
    @State private var note: NoteItem?

    var body: some View {
        Group {
            if let note {
                NoteEditorView(note: note)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if note == nil {
                note = noteStore.createNote()
            }
        }
    }
}

// MARK: - 网格记录卡片（带缩略图）
struct GridNoteCard: View {
    let note: NoteItem
    @Environment(NoteStore.self) var noteStore
    @State private var thumbnailImage: UIImage?
    
    // 获取第一个可显示缩略图的附件
    private var thumbnailAttachment: AttachmentItem? {
        note.attachments.first { att in
            switch att.type {
            case .photo, .video, .scannedDocument, .scannedText, .drawing, .location:
                return true
            default:
                return false
            }
        }
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // 背景：缩略图或纯色
            if let image = thumbnailImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .overlay(
                        LinearGradient(
                            colors: [.black.opacity(0.6), .clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            } else {
                Color(.systemGray6)
            }
            
            // 文本内容
            VStack(alignment: .leading, spacing: 8) {
                // 第一行：标签
                if !note.tags.isEmpty {
                    let maxTagsToShow = 3
                    let displayTags = Array(note.tags.prefix(maxTagsToShow))
                    let remainingCount = note.tags.count - maxTagsToShow
                    
                    HStack(spacing: 5) {
                        ForEach(displayTags) { tag in
                            Text(tag.name)
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.accentColor.opacity(0.85))
                                .cornerRadius(4)
                        }
                        
                        if remainingCount > 0 {
                            Text("+\(remainingCount)")
                                .font(.caption)
                                .foregroundColor(thumbnailImage != nil ? .white.opacity(0.9) : .secondary)
                        }
                    }
                    .frame(height: 20)
                } else {
                    Spacer()
                        .frame(height: 20)
                }
                
                // 第二行：标题
                Text(note.preview)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .foregroundColor(thumbnailImage != nil ? .white : .primary)
                    .frame(height: 36)
                
                Spacer()
                
                // 第三行：附件数量+时间
                HStack(alignment: .bottom) {
                    // 附件数量
                    if !note.attachments.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "paperclip")
                                .font(.caption2)
                            Text("\(note.attachments.count)")
                                .font(.caption2)
                        }
                        .foregroundColor(thumbnailImage != nil ? .white.opacity(0.9) : .secondary)
                    }
                    
                    Spacer()
                    
                    // 时间
                    Text(note.createdAt.formattedAbsolute)
                        .font(.caption2)
                        .foregroundColor(thumbnailImage != nil ? .white.opacity(0.9) : .secondary)
                }
                .frame(height: 20)
            }
            .padding(12)
        }
        .frame(height: 140)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .onAppear {
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        guard let attachment = thumbnailAttachment else { return }
        
        DispatchQueue.global(qos: .userInitiated).async {
            var image: UIImage?
            
            // 优先加载缩略图
            if let thumbURL = noteStore.thumbnailURL(for: attachment),
               let data = try? Data(contentsOf: thumbURL) {
                image = UIImage(data: data)
            }
            
            // 回退到原图
            if image == nil {
                let url = noteStore.attachmentURL(for: attachment)
                if let data = try? Data(contentsOf: url) {
                    image = UIImage(data: data)
                }
            }
            
            DispatchQueue.main.async {
                thumbnailImage = image
            }
        }
    }
}

import AVFoundation

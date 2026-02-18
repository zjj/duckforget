import SwiftUI
import SwiftData

/// 显示特定标签的所有记录（类似NoteSearchPage但筛选特定标签）
struct TagNotesListPage: View {
    @Environment(NoteStore.self) var noteStore
    @Environment(\.dismiss) private var dismiss
    
    let tagName: String
    var isEmbedded: Bool = false
    var onSearchTap: (() -> Void)? = nil
    
    // 优化：使用反向查询，从 TagItem 获取记录列表，利用数据库索引
    @Query(sort: \TagItem.sortOrder)
    var allTags: [TagItem]
    
    @State private var searchText = ""
    @State private var selectedNote: NoteItem?
    @State private var viewMode: ViewMode = .list
    @State private var sortMode: SortMode = .dateModified
    
    // 找到匹配的标签
    var tag: TagItem? {
        allTags.first { $0.name == tagName }
    }
    
    // 通过标签的 notes 关系获取记录，过滤已删除的记录
    var tagNotes: [NoteItem] {
        guard let tag = tag else { return [] }
        let filtered = tag.notes.filter { !$0.isDeleted }
        
        // 根据排序方式排序
        switch sortMode {
        case .dateModified:
            return filtered.sorted { $0.updatedAt > $1.updatedAt }
        case .dateCreated:
            return filtered.sorted { $0.createdAt > $1.createdAt }
        case .title:
            return filtered.sorted { $0.preview.localizedCaseInsensitiveCompare($1.preview) == .orderedAscending }
        }
    }
    
    // 搜索过滤
    var filteredNotes: [NoteItem] {
        if searchText.isEmpty {
            return tagNotes
        } else {
            return tagNotes.filter { note in
                note.content.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header for embedded mode
            if isEmbedded {
                HStack {
                    Image(systemName: "tag.fill")
                        .foregroundColor(.accentColor)
                        .font(.largeTitle)
                    Text(tagName)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 8)
            }

            // 搜索栏
            if let onSearchTap = onSearchTap {
                Button(action: onSearchTap) {
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        
                        Text("搜索 \(tagName) 标签")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(12)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding()
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("搜索 \(tagName) 标签", text: $searchText)
                        .textFieldStyle(.plain)
                    
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            
            Divider()
            
            // 记录列表
            if filteredNotes.isEmpty {
                ContentUnavailableView {
                    Label(searchText.isEmpty ? "此标签下暂无记录" : "无匹配结果", systemImage: "tag")
                } description: {
                    if searchText.isEmpty {
                        Text("创建记录并添加 \(tagName) 标签")
                    } else {
                        Text("尝试其他关键词")
                    }
                }
            } else if isEmbedded {
                // 嵌入模式下：只显示有限数量（例如20条），并提供"查看全部"按钮
                let displayLimit = 20
                let displayed = filteredNotes.prefix(displayLimit)
                
                LazyVStack(spacing: 0) {
                    ForEach(displayed) { note in
                        NavigationLink(destination: NoteEditorView(note: note).environment(noteStore)) {
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
                    }
                    
                    if filteredNotes.count > displayLimit {
                        Button("查看更多") {
                            onSearchTap?()
                        }
                        .padding()
                        .foregroundColor(.secondary)
                    }
                }
            } else if viewMode == .list {
                // 列表视图
                List {
                    ForEach(filteredNotes) { note in
                        NavigationLink(destination: NoteEditorView(note: note).environment(noteStore)) {
                            NoteRowView(note: note)
                                .environment(noteStore)
                        }
                    }
                }
                .listStyle(.plain)
            } else {
                // 网格视图
                ScrollView {
                    let columns = [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ]
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(filteredNotes) { note in
                            NavigationLink(destination: NoteEditorView(note: note).environment(noteStore)) {
                                GridNoteCard(note: note)
                                    .environment(noteStore)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
        }
        .navigationTitle(tagName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section("视图模式") {
                        Picker("视图", selection: $viewMode) {
                            ForEach(ViewMode.allCases, id: \.self) { mode in
                                Label(mode.rawValue, systemImage: mode.icon)
                                    .tag(mode)
                            }
                        }
                    }
                    
                    Section("排序方式") {
                        Picker("排序", selection: $sortMode) {
                            ForEach(SortMode.allCases, id: \.self) { mode in
                                Label(mode.rawValue, systemImage: mode.icon)
                                    .tag(mode)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
    }
}

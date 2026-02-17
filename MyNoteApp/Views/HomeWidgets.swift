import SwiftUI
import SwiftData

struct SearchWidget: View {
    @Environment(NoteStore.self) var noteStore
    let size: WidgetSize
    @State private var showSearch = false
    
    var body: some View {
        Group {
            if size == .fullPage {
                NoteSearchPage()
            } else {
                searchCard
            }
        }
        .navigationDestination(isPresented: $showSearch) {
            NoteSearchPage()
        }
    }
    
    private var searchCard: some View {
        Button {
            showSearch = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("搜索")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("输入进行搜索...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer() // 确保HStack填满宽度
            }
            .frame(maxWidth: .infinity) // 关键：让HStack填满父容器宽度
            .padding(16)
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }
}

struct FolderListWidget: View {
    @Environment(NoteStore.self) var noteStore
    @Query(sort: \FolderItem.sortOrder) var folders: [FolderItem]
    
    // widget size
    let size: WidgetSize
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("文件夹")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Spacer()
                NavigationLink(destination: NoteListView(folder: nil, showAllNotes: true).environment(noteStore)) {
                    Text("全部")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            
            if folders.isEmpty {
                Text("暂无文件夹")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ScrollView(size == .small ? .horizontal : .vertical, showsIndicators: false) {
                    if size == .small {
                        LazyHStack(spacing: 12) {
                            ForEach(folders) { folder in
                                FolderItemView(folder: folder)
                            }
                        }
                        .padding(.horizontal)
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(folders) { folder in
                                FolderItemView(folder: folder)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .frame(maxHeight: size == .fullPage ? .infinity : nil)
            }
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

struct FolderItemView: View {
    let folder: FolderItem
    @Environment(NoteStore.self) var noteStore

    var body: some View {
        NavigationLink(destination: NoteListView(folder: folder, showAllNotes: false).environment(noteStore)) {
            HStack {
                Image(systemName: folder.iconName)
                    .foregroundColor(.yellow)
                    .font(.title2)
                
                VStack(alignment: .leading) {
                    Text(folder.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("\(folder.notes.filter { !$0.isDeleted }.count) 个备忘录")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

struct RecentNotesWidget: View {
    @Environment(NoteStore.self) var noteStore
    @Query(
        filter: #Predicate<NoteItem> { $0.isDeleted == false },
        sort: \NoteItem.updatedAt,
        order: .reverse
    ) var notes: [NoteItem]
    
    let size: WidgetSize
    
    var displayedNotes: [NoteItem] {
        // 先筛选最近7天的笔记
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let recentNotes = notes.filter { $0.updatedAt >= sevenDaysAgo }
        
        // 再根据 size 限制数量
        switch size {
        case .small: return Array(recentNotes.prefix(3))
        case .medium: return Array(recentNotes.prefix(5))
        case .large: return Array(recentNotes.prefix(10))
        case .fullPage: return Array(recentNotes.prefix(20))
        }
    }
    
    var body: some View {
        if size == .fullPage {
            // fullPage 模式使用 NoteSearchPage，显示顶部搜索栏
            NoteSearchPage(
                pageTitle: "最近笔记",
                filterRecentDays: 7,
                hideSearchBar: false // 显示顶部搜索栏
            )
            .environment(noteStore)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                // 标题区域：点击跳转到完整列表
                NavigationLink(destination: NoteSearchPage(
                    pageTitle: "最近笔记",
                    filterRecentDays: 7,
                    hideSearchBar: false // 显示顶部搜索栏
                ).environment(noteStore)) {
                    HStack {
                        Text("最近笔记")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal)
                }
                .buttonStyle(.plain)
                
                if displayedNotes.isEmpty {
                    Text("暂无笔记")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    // 小组件模式：水平滚动展示，可点击进入编辑
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            ForEach(displayedNotes) { note in
                            NavigationLink(destination: NoteEditorView(note: note).environment(noteStore)) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(note.preview)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .lineLimit(2)
                                        .foregroundColor(.primary)
                                    
                                    Spacer()
                                    
                                    // 附件图标
                                    if !note.attachments.isEmpty {
                                        noteAttachmentIcons(note)
                                    }
                                    
                                    Text(note.createdAt.formattedAbsolute)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding()
                                .frame(width: 140, height: 100)
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        // “无其他内容”提示
                        VStack {
                            Spacer()
                            Text("无其他内容")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .frame(width: 140, height: 100)
                        .background(Color(.systemGray6).opacity(0.5))
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
        }
    }
    
    // 附件图标展示（复用 NoteRowView 的逻辑）
    @ViewBuilder
    private func noteAttachmentIcons(_ note: NoteItem) -> some View {
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
    }
}

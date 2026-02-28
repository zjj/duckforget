import SwiftUI
import SwiftData

struct TagWidget: View {
    @Environment(NoteStore.self) var noteStore
    @Environment(\.modelContext) private var modelContext
    let tagName: String
    let size: WidgetSize
    let isEditing: Bool
    @Binding var showTagDetail: Bool
    @State private var totalNotesCount: Int = 0
    @Environment(\.appTheme) private var theme
    
    // 使用 Query 直接查询符合条件的 NoteItem，限制前100条（仅用于展示）
    @Query var notes: [NoteItem]
    
    init(tagName: String, size: WidgetSize, isEditing: Bool = false, showTagDetail: Binding<Bool>) {
        self.tagName = tagName
        self.size = size
        self.isEditing = isEditing
        self._showTagDetail = showTagDetail
        
        let filter = #Predicate<NoteItem> { note in
            !note.isDeleted && note.tags.contains { $0.name == tagName }
        }
        var descriptor = FetchDescriptor<NoteItem>(predicate: filter)
        descriptor.sortBy = [SortDescriptor(\.updatedAt, order: .reverse)]
        descriptor.fetchLimit = 50
        _notes = Query(descriptor)
    }
    
    var displayedNotes: [NoteItem] {
        switch size {
        case .small:    return Array(notes.prefix(8))
        case .medium:   return Array(notes.prefix(12))
        case .large:    return Array(notes.prefix(20))
        case .fullPage: return Array(notes.prefix(50))
        }
    }

    private var cardWidth:  CGFloat { size == .small ? 105 : size == .medium ? 145 : 160 }
    private var cardHeight: CGFloat { size == .small ?  50 : size == .medium ?  95 : 128 }

    var body: some View {
        if size == .fullPage {
            // 全屏嵌入模式：显示记录列表预览（前100条），点击跳转到完整列表页
            TagFullPagePreview(tagName: tagName, displayedNotes: displayedNotes, isEditing: isEditing)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                // 标题区域：点击跳转到完整列表
                NavigationLink(destination: NoteSearchPage(pageTitle: tagName, filterTagName: tagName, headerIcon: "tag.fill").environment(noteStore)) {
                    HStack {
                        Image(systemName: "tag.fill")
                            .foregroundColor(theme.colors.accent)
                            .font(.subheadline)
                        Text(tagName)
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal)
                }
                .buttonStyle(.plain)
                .disabled(isEditing)
                
                if displayedNotes.isEmpty {
                    Text("暂无记录")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    // 小组件模式：水平滚动展示
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 10) {
                            ForEach(displayedNotes) { note in
                                NavigationLink(destination: NoteView(note: note, startInEditMode: false).environment(noteStore)) {
                                    WidgetNoteCard(note: note, size: size)
                                        .environment(noteStore)
                                }
                                .buttonStyle(.plain)
                                .disabled(isEditing)
                            }

                            // 查看更多
                            NavigationLink(destination: NoteSearchPage(pageTitle: tagName, filterTagName: tagName, headerIcon: "tag.fill").environment(noteStore)) {
                                VStack(spacing: 4) {
                                    Spacer()
                                    let remaining = totalNotesCount - displayedNotes.count
                                    if remaining > 0 {
                                        Text("+\(remaining)")
                                            .font(.headline)
                                            .foregroundColor(theme.colors.accent)
                                        Text("查看更多")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    } else {
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(theme.colors.accent.opacity(0.7))
                                    }
                                    Spacer()
                                }
                                .frame(width: cardWidth, height: cardHeight)
                                .background(theme.colors.card.opacity(0.5))
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                            .disabled(isEditing)
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical, 8)
            .background(theme.colors.surface)
            .cornerRadius(16)
            .shadow(color: theme.colors.shadow, radius: 5, x: 0, y: 2)
            .task { fetchTotalCount() }
        }
    }
    
    private func fetchTotalCount() {
        let name = tagName
        let filter = #Predicate<NoteItem> { note in
            !note.isDeleted && note.tags.contains { $0.name == name }
        }
        let descriptor = FetchDescriptor<NoteItem>(predicate: filter)
        totalNotesCount = (try? modelContext.fetchCount(descriptor)) ?? 0
    }
    
    // 附件图标展示
    @ViewBuilder
    private func noteAttachmentIcons(_ note: NoteItem) -> some View {
        let noteAttachments = note.attachments.sorted { $0.createdAt < $1.createdAt }
        HStack(spacing: 6) {
            ForEach(noteAttachments.prefix(6)) { att in
                WidgetAttachmentThumbnail(attachment: att)
            }
            if noteAttachments.count > 6 {
                Text("+\(noteAttachments.count - 6)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Full Page Previews

/// 标签组件的全屏预览（嵌入模式）
struct TagFullPagePreview: View {
    @Environment(NoteStore.self) var noteStore
    @Environment(\.appTheme) private var theme
    let tagName: String
    let displayedNotes: [NoteItem]
    var isEditing: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 标题
            HStack {
                Image(systemName: "tag.fill")
                    .foregroundColor(theme.colors.accent)
                    .font(.subheadline)
                Text(tagName)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 16)
            
            // 搜索框（伪）→ 直接 NavigationLink 跳转
            NavigationLink(destination: NoteSearchPage(pageTitle: tagName, filterTagName: tagName, headerIcon: "tag.fill").environment(noteStore)) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    Text("搜索 \(tagName) 标签")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(12)
                .background(theme.colors.card)
                .cornerRadius(12)
                .padding(.horizontal)
            }
            .buttonStyle(.plain)
            .disabled(isEditing)
            
            //Divider()
            //    .padding(.top, 8)
            
            // 记录预览（最多显示100条）
            if displayedNotes.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tag")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    Text("此标签下暂无记录")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("点击查看详情")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(displayedNotes.prefix(100)) { note in
                            NavigationLink(destination: NoteView(note: note, startInEditMode: false).environment(noteStore)) {
                                NoteRowView(note: note)
                                    .environment(noteStore)
                            }
                            .buttonStyle(.plain)
                            .disabled(isEditing)
                        }
                        
                        if displayedNotes.count > 100 {
                            NavigationLink(destination: NoteSearchPage(pageTitle: tagName, filterTagName: tagName, headerIcon: "tag.fill").environment(noteStore)) {
                                HStack {
                                    Spacer()
                                    Text("查看全部 \(displayedNotes.count) 条记录")
                                        .font(.subheadline)
                                        .foregroundColor(theme.colors.accent)
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(theme.colors.accent)
                                    Spacer()
                                }
                                .padding()
                            }
                            .buttonStyle(.plain)
                            .disabled(isEditing)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
            
            Spacer()
        }
        .background(theme.colors.surface)
    }
}

/// 标签组件的静态全屏预览（不查询数据，避免卡死）
struct TagFullPagePreviewStatic: View {
    let tagName: String
    let onTap: () -> Void
    @Environment(\.appTheme) private var theme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 标题
            HStack {
                Image(systemName: "tag.fill")
                    .foregroundColor(theme.colors.accent)
                    .font(.largeTitle)
                Text(tagName)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 16)
            
            // 搜索框（伪）
            Button(action: onTap) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    Text("搜索 \(tagName) 标签")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(12)
                .background(theme.colors.card)
                .cornerRadius(12)
                .padding(.horizontal)
            }
            .buttonStyle(.plain)
            
            // 静态提示文本（不查询数据）
            VStack(spacing: 12) {
                Image(systemName: "tag.circle")
                    .font(.system(size: 64))
                    .foregroundColor(.secondary.opacity(0.5))
                
                Text("点击查看 \(tagName) 标签下的记录")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text("或使用搜索功能")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
            
            Spacer()
        }
        .background(theme.colors.surface)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

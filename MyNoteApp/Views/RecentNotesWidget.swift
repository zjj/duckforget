import SwiftUI
import SwiftData

struct RecentNotesWidget: View {
    @Environment(NoteStore.self) var noteStore
    @Environment(\.modelContext) private var modelContext
    @Query var notes: [NoteItem]
    @State private var totalNotesCount: Int = 0
    @Environment(\.appTheme) private var theme
    
    let size: WidgetSize
    let isEditing: Bool
    @Binding var showRecentNotes: Bool
    
    init(size: WidgetSize, isEditing: Bool, showRecentNotes: Binding<Bool>) {
        self.size = size
        self.isEditing = isEditing
        self._showRecentNotes = showRecentNotes
        
        let fortyEightHoursAgo = Calendar.current.date(byAdding: .hour, value: -48, to: Date()) ?? Date()
        let filter = #Predicate<NoteItem> { note in
            !note.isDeleted && note.updatedAt >= fortyEightHoursAgo
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
            // 全屏嵌入模式：显示预览界面，点击跳转到完整列表页
            RecentNotesFullPagePreview(displayedNotes: displayedNotes, isEditing: isEditing)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                // 标题区域：点击跳转到完整列表
                NavigationLink(destination: NoteSearchPage(
                    pageTitle: "最近记录",
                    filterRecentDays: 2,
                    hideSearchBar: false // 显示顶部搜索栏
                ).environment(noteStore)) {
                    HStack {
                        Image(systemName: "clock.fill")
                            .foregroundColor(theme.colors.accent)
                            .font(.subheadline)
                        Text("最近记录")
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
                            NavigationLink(destination: NoteSearchPage(
                                pageTitle: "最近记录",
                                filterRecentDays: 2,
                                hideSearchBar: false
                            ).environment(noteStore)) {
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
        let fortyEightHoursAgo = Calendar.current.date(byAdding: .hour, value: -48, to: Date()) ?? Date()
        let filter = #Predicate<NoteItem> { note in
            !note.isDeleted && note.updatedAt >= fortyEightHoursAgo
        }
        let descriptor = FetchDescriptor<NoteItem>(predicate: filter)
        totalNotesCount = (try? modelContext.fetchCount(descriptor)) ?? 0
    }
    
    // 附件图标展示（复用 NoteRowView 的逻辑）
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

// MARK: - Full Page Preview

/// 最近记录组件的全屏预览（嵌入模式）
struct RecentNotesFullPagePreview: View {
    @Environment(NoteStore.self) var noteStore
    @Environment(\.appTheme) private var theme
    let displayedNotes: [NoteItem]
    var isEditing: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 标题
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundColor(theme.colors.accent)
                    .font(.subheadline)
                Text("最近记录")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 16)
            
            // 搜索框（伪）→ 直接 NavigationLink 跳转
            NavigationLink(destination: NoteSearchPage(
                pageTitle: "最近记录",
                filterRecentDays: 2,
                hideSearchBar: false
            ).environment(noteStore)) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    Text("输入进行搜索...")
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
                .padding(10)
                .background(theme.colors.card)
                .cornerRadius(10)
                .padding(.horizontal)
            }
            .buttonStyle(.plain)
            .disabled(isEditing)
            
            //Divider()
            //    .padding(.top, 8)
            
            // 记录预览（最多显示100条）
            if displayedNotes.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    Text("最近48小时无记录")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("点击查看全部记录")
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
                            NavigationLink(destination: NoteSearchPage(
                                pageTitle: "最近记录",
                                filterRecentDays: 2,
                                hideSearchBar: false
                            ).environment(noteStore)) {
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

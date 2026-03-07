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
        } else if size == .large {
            // 大尺寸：垂直网格展示，可纵向滚动
            VStack(alignment: .leading, spacing: 10) {
                // 标题区域
                ZStack(alignment: .leading) {
                    NavigationLink(destination: NoteSearchPage(
                        pageTitle: "最近记录",
                        filterRecentDays: 2,
                        hideSearchBar: false
                    ).environment(noteStore)) {
                        EmptyView()
                    }
                    .opacity(0)
                    .disabled(isEditing)

                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .foregroundColor(theme.colors.accent)
                            .font(.system(size: 14, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                        Text("最近记录")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(theme.colors.secondaryText)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.45))
                    }
                    .padding(.horizontal, 14)
                    .allowsHitTesting(!isEditing)
                }

                if displayedNotes.isEmpty {
                    Text("暂无记录")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    ScrollView(.vertical, showsIndicators: true) {
                        let columns = [
                            GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10)
                        ]
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(displayedNotes) { note in
                                NavigationLink(destination: NoteView(note: note, startInEditMode: false).environment(noteStore)) {
                                    WidgetNoteCard(note: note, size: size, gridMode: true)
                                        .environment(noteStore)
                                }
                                .buttonStyle(.plain)
                                .disabled(isEditing)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .padding(.vertical, 8)
            .frame(height: size.height)
            .background(theme.colors.surface)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
            .shadow(color: theme.colors.shadow, radius: 8, x: 0, y: 2)
            .task { fetchTotalCount() }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                // 标题区域：点击跳转到完整列表
                ZStack(alignment: .leading) {
                    NavigationLink(destination: NoteSearchPage(
                        pageTitle: "最近记录",
                        filterRecentDays: 2,
                        hideSearchBar: false
                    ).environment(noteStore)) {
                        EmptyView()
                    }
                    .opacity(0)
                    .disabled(isEditing)

                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .foregroundColor(theme.colors.accent)
                            .font(.system(size: 14, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                        Text("最近记录")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(theme.colors.secondaryText)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.45))
                    }
                    .padding(.horizontal, 14)
                    .allowsHitTesting(!isEditing)
                }
                
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
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(theme.colors.accent)
                                        Text("更多")
                                            .font(.system(size: 10))
                                            .foregroundColor(theme.colors.secondaryText.opacity(0.7))
                                    } else {
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(theme.colors.accent.opacity(0.6))
                                    }
                                    Spacer()
                                }
                                .frame(width: cardWidth, height: cardHeight)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(theme.colors.card.opacity(0.6))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(Color.primary.opacity(0.05), lineWidth: 0.5)
                                        )
                                )
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
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
            .shadow(color: theme.colors.shadow, radius: 8, x: 0, y: 2)
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
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .foregroundColor(theme.colors.accent)
                    .font(.system(size: 14, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                Text("最近记录")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(theme.colors.secondaryText)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            
            // Apple-style search bar (fake) → NavigationLink
            NavigationLink(destination: NoteSearchPage(
                pageTitle: "最近记录",
                filterRecentDays: 2,
                hideSearchBar: false
            ).environment(noteStore)) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(theme.colors.secondaryText)
                        .font(.system(size: 16, weight: .medium))
                    
                    Text("搜索...")
                        .foregroundColor(theme.colors.secondaryText)
                        .font(.system(size: 17))
                    
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(theme.colors.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                        )
                )
                .padding(.horizontal, 14)
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

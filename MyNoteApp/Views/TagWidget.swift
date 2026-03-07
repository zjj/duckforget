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

    var body: some View {
        NoteCardListWidget(
            title: tagName,
            icon: "tag",
            notes: displayedNotes,
            totalCount: totalNotesCount,
            size: size,
            isEditing: isEditing,
            destination: NoteSearchPage(
                pageTitle: tagName,
                filterTagName: tagName,
                headerIcon: "tag.fill"
            )
        )
        .environment(noteStore)
        .task { fetchTotalCount() }
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

// MARK: - Tag Static Preview

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

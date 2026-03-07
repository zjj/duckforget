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

    var body: some View {
        NoteCardListWidget(
            title: "最近记录",
            icon: "clock",
            notes: displayedNotes,
            totalCount: totalNotesCount,
            size: size,
            isEditing: isEditing,
            destination: NoteSearchPage(
                pageTitle: "最近记录",
                filterRecentDays: 2,
                hideSearchBar: false
            )
        )
        .environment(noteStore)
        .task { fetchTotalCount() }
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



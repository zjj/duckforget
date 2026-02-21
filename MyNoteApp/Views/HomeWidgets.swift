import SwiftUI
import SwiftData

struct SearchWidget: View {
    @Environment(NoteStore.self) var noteStore
    let size: WidgetSize
    @Binding var showSearch: Bool
    
    var body: some View {
        Group {
            if size == .fullPage {
                // 全屏嵌入模式：显示预览界面，点击跳转到完整搜索页
                SearchFullPagePreview(onTap: { showSearch = true })
            } else {
                searchCard
            }
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
                        .foregroundColor(.secondary)
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

struct TagWidget: View {
    @Environment(NoteStore.self) var noteStore
    @Environment(\.modelContext) private var modelContext
    let tagName: String
    let size: WidgetSize
    let isEditing: Bool
    @Binding var showTagDetail: Bool
    @State private var totalNotesCount: Int = 0
    
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
        descriptor.fetchLimit = 100
        _notes = Query(descriptor)
    }
    
    var displayedNotes: [NoteItem] {
        switch size {
        case .small: return Array(notes.prefix(15))
        case .medium: return Array(notes.prefix(15))
        case .large: return Array(notes.prefix(15))
        case .fullPage: return Array(notes.prefix(100)) // 全屏模式显示前100条
        }
    }
    
    var body: some View {
        if size == .fullPage {
            // 全屏嵌入模式：显示记录列表预览（前100条），点击跳转到完整列表页
            TagFullPagePreview(tagName: tagName, displayedNotes: displayedNotes, isEditing: isEditing)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                // 标题区域：点击跳转到完整列表
                NavigationLink(destination: TagNotesListPage(tagName: tagName).environment(noteStore)) {
                    HStack {
                        Image(systemName: "tag.fill")
                            .foregroundColor(.accentColor)
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
                        LazyHStack(spacing: 12) {
                            ForEach(displayedNotes) { note in
                                NavigationLink(destination: NoteView(note: note, startInEditMode: false).environment(noteStore)) {
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
                                .disabled(isEditing)
                            }
                            
                            // “+xxx”按钮或查看全部
                            NavigationLink(destination: TagNotesListPage(tagName: tagName).environment(noteStore)) {
                                VStack(spacing: 4) {
                                    Spacer()
                                    let remaining = totalNotesCount - displayedNotes.count
                                    if remaining > 0 {
                                        Text("+\(remaining)")
                                            .font(.headline)
                                            .foregroundColor(.accentColor)
                                        Text("查看更多")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    } 
                                    Spacer()
                                }
                                .padding()
                                .frame(width: 140, height: 100)
                                .background(Color(.systemGray6).opacity(0.5))
                                .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                            .disabled(isEditing)
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
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

struct RecentNotesWidget: View {
    @Environment(NoteStore.self) var noteStore
    @Environment(\.modelContext) private var modelContext
    @Query var notes: [NoteItem]
    @State private var totalNotesCount: Int = 0
    
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
        descriptor.fetchLimit = 100
        _notes = Query(descriptor)
    }
    
    var displayedNotes: [NoteItem] {
        // 根据 size 限制数量
        switch size {
        case .small: return Array(notes.prefix(15))
        case .medium: return Array(notes.prefix(15))
        case .large: return Array(notes.prefix(15))
        case .fullPage: return Array(notes.prefix(100))
        }
    }
    
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
                            .foregroundColor(.accentColor)
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
                    // 小组件模式：水平滚动展示，可点击进如只读预览，进一步点击进入编辑页
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            ForEach(displayedNotes) { note in
                            NavigationLink(destination: NoteView(note: note, startInEditMode: false).environment(noteStore)) {
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
                        
                        // “+xxx”按钮或查看全部
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
                                        .foregroundColor(.accentColor)
                                    Text("查看更多")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                } 

                                Spacer()
                            }
                            .padding()
                            .frame(width: 140, height: 100)
                            .background(Color(.systemGray6).opacity(0.5))
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                        .disabled(isEditing)
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
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
// MARK: - 废纸篓组件

struct TrashWidget: View {
    @Environment(NoteStore.self) var noteStore
    @Query(
        filter: #Predicate<NoteItem> { $0.isDeleted == true },
        sort: \NoteItem.deletedAt,
        order: .reverse
    ) var trashedNotes: [NoteItem]
    
    let size: WidgetSize
    let appSettings = AppSettings.shared
    
    var displayedNotes: [NoteItem] {
        switch size {
        case .small: return Array(trashedNotes.prefix(3))
        case .medium: return Array(trashedNotes.prefix(5))
        case .large: return Array(trashedNotes.prefix(10))
        case .fullPage: return trashedNotes
        }
    }
    
    var body: some View {
        if size == .fullPage {
            // 全屏模式显示完整的废纸篓页面
            TrashDetailPage()
                .environment(noteStore)
        } else {
            // 小组件模式：简单卡片，点击跳转
            NavigationLink(destination: TrashDetailPage().environment(noteStore)) {
                HStack(spacing: 12) {
                    Image(systemName: "trash")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.orange)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("废纸篓")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("废纸篓（\(trashedNotes.count)条）")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 3)
            }
            .buttonStyle(.plain)
        }
    }
    
    private func daysRemaining(_ note: NoteItem) -> String {
        guard let deletedAt = note.deletedAt else { return "" }
        let calendar = Calendar.current
        let expiryDate = calendar.date(byAdding: .day, value: appSettings.trashRetentionDays, to: deletedAt) ?? deletedAt
        let remaining = calendar.dateComponents([.day], from: Date(), to: expiryDate).day ?? 0
        if remaining <= 0 {
            return "即将删除"
        }
        return "剩余 \(remaining) 天"
    }
}

// MARK: - 废纸篓卡片按钮（无 chevron）

struct TrashCardButton: View {
    let trashedCount: Int
    @Binding var showTrashDetail: Bool
    
    var body: some View {
        Button {
            showTrashDetail = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "trash")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.orange)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("废纸篓")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("废纸篓（\(trashedCount)条）")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 废纸篓详情页面（只读查看）

struct TrashDetailPage: View {
    @Environment(NoteStore.self) var noteStore
    @Query(
        filter: #Predicate<NoteItem> { $0.isDeleted == true },
        sort: \NoteItem.deletedAt,
        order: .reverse
    ) var trashedNotes: [NoteItem]
    
    let appSettings = AppSettings.shared
    
    @State private var noteToDelete: NoteItem?
    @State private var showDeleteConfirmation = false
    @State private var showEmptyTrashConfirmation = false
    
    var body: some View {
        Group {
            if trashedNotes.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "trash")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text("废纸篓是空的")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("删除的记录将保留 \(appSettings.trashRetentionDays) 天")
                        .font(.subheadline)
                        .foregroundColor(.secondary.opacity(0.7))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(trashedNotes) { note in
                        NavigationLink(destination: TrashNoteDetailView(note: note).environment(noteStore)) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(note.preview)
                                    .font(.headline)
                                    .lineLimit(1)
                                HStack(spacing: 8) {
                                    if let deletedAt = note.deletedAt {
                                        Text("删除于 \(deletedAt.formattedShort)")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                    Text(daysRemaining(note))
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                noteToDelete = note
                                showDeleteConfirmation = true
                            } label: {
                                Label("永久删除", systemImage: "trash.slash")
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                withAnimation {
                                    noteStore.restoreNote(note)
                                }
                            } label: {
                                Label("恢复", systemImage: "arrow.uturn.backward")
                            }
                            .tint(.blue)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("废纸篓")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !trashedNotes.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            withAnimation {
                                for note in trashedNotes {
                                    noteStore.restoreNote(note)
                                }
                            }
                        } label: {
                            Label("恢复全部", systemImage: "arrow.uturn.backward")
                        }

                        Button(role: .destructive) {
                            showEmptyTrashConfirmation = true
                        } label: {
                            Label("清空废纸篓", systemImage: "trash.slash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
        }
        .alert("确认永久删除", isPresented: $showDeleteConfirmation) {
            Button("取消", role: .cancel) { }
            Button("永久删除", role: .destructive) {
                if let note = noteToDelete {
                    withAnimation {
                        noteStore.permanentlyDeleteNote(note)
                    }
                    noteToDelete = nil
                }
            }
        } message: {
            Text("确定要永久删除这条笔记吗？此操作无法撤销！")
        }
        .alert("确认清空废纸篓", isPresented: $showEmptyTrashConfirmation) {
            Button("取消", role: .cancel) { }
            Button("永久删除全部", role: .destructive) {
                withAnimation {
                    noteStore.emptyTrash()
                }
            }
        } message: {
            Text("确定要清空废纸篓吗？所有已删除的笔记将被永久删除，此操作无法撤销！")
        }
    }
    
    private func daysRemaining(_ note: NoteItem) -> String {
        guard let deletedAt = note.deletedAt else { return "" }
        let calendar = Calendar.current
        let expiryDate = calendar.date(byAdding: .day, value: appSettings.trashRetentionDays, to: deletedAt) ?? deletedAt
        let remaining = calendar.dateComponents([.day], from: Date(), to: expiryDate).day ?? 0
        if remaining <= 0 {
            return "即将删除"
        }
        return "剩余 \(remaining) 天"
    }
}

// MARK: - 废纸篓记录只读查看页面

struct TrashNoteDetailView: View {
    @Environment(NoteStore.self) var noteStore
    @Environment(\.dismiss) var dismiss
    let note: NoteItem
    
    @State private var showRestoreConfirm = false
    @State private var showDeleteConfirm = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 元数据信息
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("创建时间：\(note.createdAt.formattedAbsolute)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    if let deletedAt = note.deletedAt {
                        HStack(spacing: 8) {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundColor(.orange)
                            Text("删除时间：\(deletedAt.formattedAbsolute)")
                                .font(.subheadline)
                                .foregroundColor(.orange)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                
                Divider()
                    .padding(.horizontal)
                
                // 内容区域（只读）
                Text(note.content.isEmpty ? "（无内容）" : note.content)
                    .font(.body)
                    .foregroundColor(note.content.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // 附件区域（只读展示）
                if !note.attachments.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("附件")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 12) {
                            ForEach(note.attachments.sorted(by: { $0.createdAt < $1.createdAt })) { attachment in
                                ReadOnlyAttachmentView(attachment: attachment)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                
                Spacer()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showRestoreConfirm = true
                    } label: {
                        Label("恢复", systemImage: "arrow.uturn.backward")
                    }
                    
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("永久删除", systemImage: "trash.slash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .alert("恢复", isPresented: $showRestoreConfirm) {
            Button("取消", role: .cancel) {}
            Button("恢复") {
                withAnimation {
                    noteStore.restoreNote(note)
                }
                dismiss()
            }
        } message: {
            Text("要恢复吗？")
        }
        .alert("永久删除", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                withAnimation {
                    noteStore.permanentlyDeleteNote(note)
                }
                dismiss()
            }
        } message: {
            Text("永久删除后无法恢复，确定要删除吗？")
        }
    }
}

// MARK: - 只读附件视图

/// 用于废纸篓的只读附件展示（不显示删除按钮）
struct ReadOnlyAttachmentView: View {
    let attachment: AttachmentItem
    @State private var thumbnailImage: UIImage?
    @Environment(NoteStore.self) var noteStore
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
            
            content
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray4), lineWidth: 0.5)
        )
        .onAppear { loadThumbnail() }
    }
    
    @ViewBuilder
    private var content: some View {
        switch attachment.type {
        case .photo, .scannedDocument, .scannedText, .drawing:
            if let image = thumbnailImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ProgressView()
            }
            
        case .video:
            ZStack {
                if let image = thumbnailImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
                Image(systemName: "play.circle.fill")
                    .font(.largeTitle)
                    .foregroundColor(.white)
                    .shadow(radius: 3)
            }
            
        case .audio:
            VStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.largeTitle)
                    .foregroundColor(.accentColor)
                Text("音频")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
        case .file:
            VStack(spacing: 8) {
                Image(systemName: "doc.fill")
                    .font(.largeTitle)
                    .foregroundColor(.blue)
                Text(attachment.fileName)
                    .font(.caption2)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
            }
            
        case .location:
            ZStack {
                if let image = thumbnailImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(.systemGray5)
                }
                
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: 32, height: 32)
                        .shadow(radius: 2)
                    
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 16))
                        .foregroundColor(.red)
                }
            }
        }
    }
    
    private func loadThumbnail() {
        guard
            attachment.type == .photo
                || attachment.type == .video
                || attachment.type == .scannedDocument
                || attachment.type == .scannedText
                || attachment.type == .drawing
                || attachment.type == .location
        else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            var image: UIImage?

            // 优先加载缩略图
            if let thumbURL = noteStore.thumbnailURL(for: attachment),
                let data = try? Data(contentsOf: thumbURL)
            {
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

// MARK: - Full Page Preview Components for Embedded Mode

/// 搜索组件的全屏预览（嵌入模式）
struct SearchFullPagePreview: View {
    let onTap: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 标题
            Text("搜索")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.horizontal)
                .padding(.top, 16)
            
            // 搜索框（伪）
            Button(action: onTap) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    Text("输入进行搜索...")
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
                .padding(10)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal)
            }
            .buttonStyle(.plain)
            
            // 提示文本
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass.circle")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary.opacity(0.5))
                
                Text("点击搜索框开始搜索")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
            
            Spacer()
        }
        .background(Color(.systemBackground))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

/// 标签组件的全屏预览（嵌入模式）
struct TagFullPagePreview: View {
    @Environment(NoteStore.self) var noteStore
    let tagName: String
    let displayedNotes: [NoteItem]
    var isEditing: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 标题
            HStack {
                Image(systemName: "tag.fill")
                    .foregroundColor(.accentColor)
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
            NavigationLink(destination: TagNotesListPage(tagName: tagName).environment(noteStore)) {
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
                .padding(.horizontal)
            }
            .buttonStyle(.plain)
            .disabled(isEditing)
            
            Divider()
                .padding(.top, 8)
            
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
                            NavigationLink(destination: TagNotesListPage(tagName: tagName).environment(noteStore)) {
                                HStack {
                                    Spacer()
                                    Text("查看全部 \(displayedNotes.count) 条记录")
                                        .font(.subheadline)
                                        .foregroundColor(.accentColor)
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.accentColor)
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
        .background(Color(.systemBackground))
    }
}

/// 最近记录组件的全屏预览（嵌入模式）
struct RecentNotesFullPagePreview: View {
    @Environment(NoteStore.self) var noteStore
    let displayedNotes: [NoteItem]
    var isEditing: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 标题
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundColor(.accentColor)
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
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal)
            }
            .buttonStyle(.plain)
            .disabled(isEditing)
            
            Divider()
                .padding(.top, 8)
            
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
                                filterRecentDays: 7,
                                hideSearchBar: false
                            ).environment(noteStore)) {
                                HStack {
                                    Spacer()
                                    Text("查看全部 \(displayedNotes.count) 条记录")
                                        .font(.subheadline)
                                        .foregroundColor(.accentColor)
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.accentColor)
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
        .background(Color(.systemBackground))
    }
}

/// 标签组件的静态全屏预览（不查询数据，避免卡死）
struct TagFullPagePreviewStatic: View {
    let tagName: String
    let onTap: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 标题
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
                .background(Color(.systemGray6))
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
        .background(Color(.systemBackground))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

// MARK: - 附件缩略图组件 (复用 NoteRowView 的逻辑)

private struct WidgetAttachmentThumbnail: View {
    let attachment: AttachmentItem
    @Environment(NoteStore.self) var noteStore
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                AttachmentMiniIcon(type: attachment.type)
            }
        }
        .onAppear {
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        guard [.photo, .video, .scannedDocument, .scannedText, .drawing, .location].contains(attachment.type) else { return }
        
        DispatchQueue.global(qos: .userInitiated).async {
            var loadedImage: UIImage?
            
            // 优先加载缩略图
            if let thumbURL = noteStore.thumbnailURL(for: attachment),
               let data = try? Data(contentsOf: thumbURL) {
                loadedImage = UIImage(data: data)
            }
            
            // 回退到原图
            if loadedImage == nil {
                let url = noteStore.attachmentURL(for: attachment)
                if let data = try? Data(contentsOf: url) {
                    loadedImage = UIImage(data: data)
                }
            }
            
            if let result = loadedImage {
                DispatchQueue.main.async {
                    self.image = result
                }
            }
        }
    }
}


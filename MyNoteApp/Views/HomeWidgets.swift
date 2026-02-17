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

struct TagWidget: View {
    @Environment(NoteStore.self) var noteStore
    let tagName: String
    let size: WidgetSize
    @Binding var showTagDetail: Bool
    
    // 优化：使用反向查询，从 TagItem 获取笔记列表，利用数据库索引
    @Query(sort: \TagItem.sortOrder)
    var allTags: [TagItem]
    
    // 找到匹配的标签
    var tag: TagItem? {
        allTags.first { $0.name == tagName }
    }
    
    // 通过标签的 notes 关系获取笔记，过滤已删除的笔记
    var tagNotes: [NoteItem] {
        guard let tag = tag else { return [] }
        return tag.notes
            .filter { !$0.isDeleted }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
    
    var displayedNotes: [NoteItem] {
        switch size {
        case .small: return Array(tagNotes.prefix(3))
        case .medium: return Array(tagNotes.prefix(5))
        case .large: return Array(tagNotes.prefix(10))
        case .fullPage: return Array(tagNotes.prefix(100)) // 全屏模式显示前100条
        }
    }
    
    var body: some View {
        if size == .fullPage {
            // 全屏嵌入模式：显示笔记列表预览（前100条），点击跳转到完整列表页
            TagFullPagePreview(tagName: tagName, displayedNotes: displayedNotes, onTap: { showTagDetail = true })
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
                
                if displayedNotes.isEmpty {
                    Text("暂无笔记")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    // 小组件模式：水平滚动展示
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
                            
                            // "无其他内容"提示
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
    
    // 附件图标展示
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

struct RecentNotesWidget: View {
    @Environment(NoteStore.self) var noteStore
    @Query(
        filter: #Predicate<NoteItem> { $0.isDeleted == false },
        sort: \NoteItem.updatedAt,
        order: .reverse
    ) var notes: [NoteItem]
    
    let size: WidgetSize
    @Binding var showRecentNotes: Bool
    
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
            // 全屏嵌入模式：显示预览界面，点击跳转到完整列表页
            RecentNotesFullPagePreview(displayedNotes: displayedNotes, onTap: { showRecentNotes = true })
        } else {
            VStack(alignment: .leading, spacing: 12) {
                // 标题区域：点击跳转到完整列表
                NavigationLink(destination: NoteSearchPage(
                    pageTitle: "最近笔记",
                    filterRecentDays: 7,
                    hideSearchBar: false // 显示顶部搜索栏
                ).environment(noteStore)) {
                    HStack {
                        Image(systemName: "clock.fill")
                            .foregroundColor(.accentColor)
                            .font(.subheadline)
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
// MARK: - 回收站组件

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
            // 全屏模式显示完整的回收站页面
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
                        Text("回收站")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("回收站（\(trashedNotes.count)条）")
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

// MARK: - 回收站详情页面（只读查看）

struct TrashDetailPage: View {
    @Environment(NoteStore.self) var noteStore
    @Query(
        filter: #Predicate<NoteItem> { $0.isDeleted == true },
        sort: \NoteItem.deletedAt,
        order: .reverse
    ) var trashedNotes: [NoteItem]
    
    let appSettings = AppSettings.shared
    
    var body: some View {
        Group {
            if trashedNotes.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "trash")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text("回收站是空的")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("删除的备忘录将保留 \(appSettings.trashRetentionDays) 天")
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
                                withAnimation {
                                    noteStore.permanentlyDeleteNote(note)
                                }
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
        .navigationTitle("回收站")
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
                            withAnimation {
                                noteStore.emptyTrash()
                            }
                        } label: {
                            Label("清空回收站", systemImage: "trash.slash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
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

// MARK: - 回收站笔记只读查看页面

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
                    Image(systemName: "ellipsis.circle")
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

/// 用于回收站的只读附件展示（不显示删除按钮）
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
    let onTap: () -> Void
    
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
            
            Divider()
                .padding(.top, 8)
            
            // 笔记预览（最多显示100条）
            if displayedNotes.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tag")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    Text("此标签下暂无笔记")
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
                    VStack(spacing: 0) {
                        ForEach(displayedNotes.prefix(100)) { note in
                            NavigationLink(destination: NoteEditorView(note: note).environment(noteStore)) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(note.preview)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .lineLimit(2)
                                        .foregroundColor(.primary)
                                    
                                    HStack {
                                        if !note.attachments.isEmpty {
                                            HStack(spacing: 4) {
                                                ForEach(note.attachments.prefix(3)) { att in
                                                    AttachmentMiniIcon(type: att.type)
                                                }
                                                if note.attachments.count > 3 {
                                                    Text("+\(note.attachments.count - 3)")
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                        }
                                        
                                        Spacer()
                                        
                                        Text(note.createdAt.formattedAbsolute)
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .padding()
                            }
                            .buttonStyle(.plain)
                            
                            Divider()
                                .padding(.leading)
                        }
                        
                        if displayedNotes.count > 100 {
                            Button(action: onTap) {
                                HStack {
                                    Spacer()
                                    Text("查看全部 \(displayedNotes.count) 条笔记")
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
                        }
                    }
                }
            }
            
            Spacer()
        }
        .background(Color(.systemBackground))
    }
}

/// 最近笔记组件的全屏预览（嵌入模式）
struct RecentNotesFullPagePreview: View {
    @Environment(NoteStore.self) var noteStore
    let displayedNotes: [NoteItem]
    let onTap: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 标题
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundColor(.accentColor)
                    .font(.subheadline)
                Text("最近笔记")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
            }
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
            
            Divider()
                .padding(.top, 8)
            
            // 笔记预览（最多显示100条）
            if displayedNotes.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    Text("最近7天无笔记")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("点击查看全部笔记")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(displayedNotes.prefix(100)) { note in
                            NavigationLink(destination: NoteEditorView(note: note).environment(noteStore)) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(note.preview)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .lineLimit(2)
                                        .foregroundColor(.primary)
                                    
                                    HStack {
                                        if !note.attachments.isEmpty {
                                            HStack(spacing: 4) {
                                                ForEach(note.attachments.prefix(3)) { att in
                                                    AttachmentMiniIcon(type: att.type)
                                                }
                                                if note.attachments.count > 3 {
                                                    Text("+\(note.attachments.count - 3)")
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                        }
                                        
                                        Spacer()
                                        
                                        Text(note.createdAt.formattedAbsolute)
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .padding()
                            }
                            .buttonStyle(.plain)
                            
                            Divider()
                                .padding(.leading)
                        }
                        
                        if displayedNotes.count > 100 {
                            Button(action: onTap) {
                                HStack {
                                    Spacer()
                                    Text("查看全部 \(displayedNotes.count) 条笔记")
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
                        }
                    }
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
                
                Text("点击查看 \(tagName) 标签下的笔记")
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

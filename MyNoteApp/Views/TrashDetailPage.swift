import SwiftUI
import SwiftData

// MARK: - 废纸篓详情页面（只读查看）

struct TrashDetailPage: View {
    @Environment(NoteStore.self) var noteStore
    @Environment(\.appTheme) private var theme
    @Query var trashedNotes: [NoteItem]
    
    let appSettings = AppSettings.shared
    
    init() {
        var descriptor = FetchDescriptor<NoteItem>(
            predicate: #Predicate { $0.isDeleted == true }
        )
        descriptor.sortBy = [SortDescriptor(\.deletedAt, order: .reverse)]
        descriptor.fetchLimit = 500  // Limit to most recent 500 trashed notes
        _trashedNotes = Query(descriptor)
    }
    
    @State private var noteToDelete: NoteItem?
    @State private var showDeleteConfirmation = false
    @State private var showEmptyTrashConfirmation = false
    @State private var showTrashActionsDialog = false
    
    var body: some View {
        Group {
            if trashedNotes.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "trash")
                        .font(.system(size: 64))
                        .foregroundColor(theme.colors.secondaryText.opacity(0.6))
                    Text("废纸篓是空的")
                        .font(.title2)
                        .foregroundColor(theme.colors.secondaryText)
                    Text("删除的记录将保留 \(appSettings.trashRetentionDays) 天")
                        .font(.subheadline)
                        .foregroundColor(theme.colors.secondaryText.opacity(0.7))
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
                                            .foregroundColor(theme.colors.secondaryText)
                                    }
                                    Text(daysRemaining(note))
                                        .font(.caption)
                                        .foregroundColor(theme.colors.accent)
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
                            .tint(theme.colors.accent)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(theme.colors.background.ignoresSafeArea())
        .tint(theme.colors.accent)
        .navigationTitle("废纸篓")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(theme.colors.surface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            if !trashedNotes.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showTrashActionsDialog = true
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 20))
                    }
                    .buttonStyle(.plain)
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
        .confirmationDialog("废纸篓", isPresented: $showTrashActionsDialog) {
            Button("恢复全部记录") {
                withAnimation {
                    for note in trashedNotes {
                        noteStore.restoreNote(note)
                    }
                }
            }

            Button("清空废纸篓", role: .destructive) {
                showEmptyTrashConfirmation = true
            }

            Button("取消", role: .cancel) {}
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
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) var dismiss
    let note: NoteItem
    
    @State private var showRestoreConfirm = false
    @State private var showDeleteConfirm = false
    @State private var showActionsDialog = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 元数据信息
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar")
                            .font(.caption)
                            .foregroundColor(theme.colors.secondaryText)
                        Text("创建时间：\(note.createdAt.formattedAbsolute)")
                            .font(.subheadline)
                            .foregroundColor(theme.colors.secondaryText)
                    }
                    
                    if let deletedAt = note.deletedAt {
                        HStack(spacing: 8) {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundColor(theme.colors.accent)
                            Text("删除时间：\(deletedAt.formattedAbsolute)")
                                .font(.subheadline)
                                .foregroundColor(theme.colors.accent)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                
                //Divider()
                //    .padding(.horizontal)
                
                // 内容区域（只读）
                Text(note.content.isEmpty ? "（无内容）" : note.content)
                    .font(.body)
                    .foregroundColor(note.content.isEmpty ? theme.colors.secondaryText : theme.colors.primaryText)
                    .textSelection(.enabled)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // 附件区域（只读展示）
                if !note.attachments.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("附件")
                            .font(.headline)
                            .foregroundColor(theme.colors.secondaryText)
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
                Button {
                    showActionsDialog = true
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 20))
                }
                .buttonStyle(.plain)
            }
        }
        .confirmationDialog("这条记录", isPresented: $showActionsDialog) {
            Button("恢复这条记录") {
                showRestoreConfirm = true
            }

            Button("永久删除这条记录", role: .destructive) {
                showDeleteConfirm = true
            }

            Button("取消", role: .cancel) {}
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
    @Environment(\.appTheme) private var theme
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.colors.card)
            
            content
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(theme.colors.border, lineWidth: 0.5)
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
                    .foregroundColor(theme.colors.accent)
                Text("音频")
                    .font(.caption)
                    .foregroundColor(theme.colors.secondaryText)
            }
            
        case .file:
            VStack(spacing: 8) {
                Image(systemName: "doc.fill")
                    .font(.largeTitle)
                    .foregroundColor(theme.colors.accent)
                Text(attachment.fileName)
                    .font(.caption2)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundColor(theme.colors.secondaryText)
                    .padding(.horizontal, 4)
            }
            
        case .location:
            ZStack {
                if let image = thumbnailImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    theme.colors.cardSecondary
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

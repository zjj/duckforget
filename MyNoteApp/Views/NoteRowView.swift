import SwiftUI

/// 记录列表行视图
struct NoteRowView: View {
    let note: NoteItem
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 第一行：标签（如果有）
            if !note.tags.isEmpty {
                tagsView
            }
            
            // 第二行：内容预览
            Text(note.preview)
                .font(.subheadline)
                //.fontWeight(.semibold)
                .lineLimit(2)
                .foregroundColor(theme.colors.primaryText)
            
            Spacer()
            
            // 最后一行：附件（如果有）+ 时间
            HStack(alignment: .bottom, spacing: 8) {
                // 附件缩略图
                if !note.attachments.isEmpty {
                    attachmentIcons
                }
            }
                
            Spacer()

            // 时间
            HStack {    
                Spacer()
                Text(note.createdAt.formattedAbsolute)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(minHeight: 100)
        .padding(12)
        .background(theme.colors.card)
        .cornerRadius(12)
    }

    // MARK: - 标签

    @ViewBuilder
    private var tagsView: some View {
        let maxTagsToShow = 5
        let displayTags = Array(note.tags.prefix(maxTagsToShow))
        let remainingCount = note.tags.count - maxTagsToShow
        
        HStack(spacing: 4) {
            ForEach(displayTags) { tag in
                HStack(spacing: 2) {
                    Image(systemName: "tag")
                        .font(.caption2)
                    Text(tag.name)
                        .font(.caption2)
                }
            }
            
            if remainingCount > 0 {
                Text("+\(remainingCount)")
                    .font(.caption2)
            }
        }
    }

    // MARK: - 附件图标

    @ViewBuilder
    private var attachmentIcons: some View {
        let noteAttachments = note.attachments.sorted { $0.createdAt < $1.createdAt }
        HStack(spacing: 6) {
            ForEach(noteAttachments.prefix(3)) { att in
                AttachmentRowThumbnail(attachment: att)
            }
            if noteAttachments.count > 3 {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(theme.colors.cardSecondary)
                        .frame(width: 60, height: 60)
                    Text("+\(noteAttachments.count - 3)")
                        .font(.headline)
                        .foregroundColor(theme.colors.secondaryText)
                }
            }
        }
    }
}

// MARK: - 列表缩略图组件

private struct AttachmentRowThumbnail: View {
    let attachment: AttachmentItem
    @Environment(NoteStore.self) var noteStore
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                AttachmentMiniIcon(type: attachment.type)
                    .frame(width: 60, height: 60)
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

// MARK: - 附件小图标

struct AttachmentMiniIcon: View {
    let type: AttachmentType
    @Environment(\.appTheme) private var theme

    var body: some View {
        Image(systemName: type.iconName)
            .font(.system(size: 10))
            .foregroundColor(.secondary)
            .frame(width: 22, height: 22)
            .background(theme.colors.cardSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

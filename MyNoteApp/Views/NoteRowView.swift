import SwiftUI

/// 记录列表行视图
struct NoteRowView: View {
    let note: NoteItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 第一行：标签 + 时间（右对齐）
            HStack(spacing: 8) {
                if !note.tags.isEmpty {
                    tagsView
                        .frame(height: 24)
                } else {
                    Spacer()
                        .frame(height: 24)
                }
                
                Spacer()
                
                Text(note.createdAt.formattedShort)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(height: 24)
            
            // 第二行：文字
            Text(note.preview)
                .font(.headline)
                .lineLimit(1)
                .frame(height: 20, alignment: .leading)

            // 第三行：附件小图标预览
            if !note.attachments.isEmpty {
                attachmentIcons
                    .frame(height: 24)
            } else {
                Spacer()
                    .frame(height: 24)
            }
        }
        .frame(height: 80)
        .padding(.vertical, 8)
    }

    // MARK: - 标签

    @ViewBuilder
    private var tagsView: some View {
        let maxTagsToShow = 5
        let displayTags = Array(note.tags.prefix(maxTagsToShow))
        let remainingCount = note.tags.count - maxTagsToShow
        
        HStack(spacing: 4) {
            ForEach(displayTags) { tag in
                Text(tag.name)
                    .font(.caption2)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor)
                    .cornerRadius(4)
            }
            
            if remainingCount > 0 {
                Text("+\(remainingCount)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - 附件图标

    @ViewBuilder
    private var attachmentIcons: some View {
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

// MARK: - 附件小图标

struct AttachmentMiniIcon: View {
    let type: AttachmentType

    var body: some View {
        Image(systemName: type.iconName)
            .font(.system(size: 10))
            .foregroundColor(.secondary)
            .frame(width: 22, height: 22)
            .background(Color(.systemGray5))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

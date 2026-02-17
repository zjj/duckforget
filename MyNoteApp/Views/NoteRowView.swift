import SwiftUI

/// 备忘录列表行视图
struct NoteRowView: View {
    let note: NoteItem

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // 内容预览
            Text(note.preview)
                .font(.headline)
                .lineLimit(1)

            // 日期
            HStack(spacing: 8) {
                Text(note.createdAt.formattedShort)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // 附件小图标预览
            if !note.attachments.isEmpty {
                attachmentIcons
            }
        }
        .padding(.vertical, 3)
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

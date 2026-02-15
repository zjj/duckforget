import SwiftUI

/// 附件缩略图视图 - 根据附件类型显示不同的预览样式
struct AttachmentThumbnailView: View {
    let attachment: AttachmentItem
    @Environment(NoteStore.self) var noteStore
    @State private var thumbnailImage: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))

            content
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray4), lineWidth: 0.5)
        )
        .overlay(alignment: .topTrailing) {
            deleteButton
        }
        .onAppear { loadThumbnail() }
    }

    // MARK: - 内容

    @ViewBuilder
    private var deleteButton: some View {
        Button {
            withAnimation {
                noteStore.deleteAttachment(attachment)
            }
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 22))
                .foregroundColor(.red)
                .background(Circle().fill(Color.white))
                .shadow(color: .black.opacity(0.1), radius: 2)
        }
        .padding(4)
    }

    @ViewBuilder
    private var content: some View {
        switch attachment.type {
        case .photo, .scannedDocument, .scannedText, .drawing:
            imageContent

        case .video:
            videoContent

        case .audio:
            audioContent

        case .file:
            fileContent
        }
    }

    // MARK: - 图片类型

    @ViewBuilder
    private var imageContent: some View {
        if let image = thumbnailImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .clipped()
        } else {
            ProgressView()
                .scaleEffect(0.8)
        }
    }

    // MARK: - 视频类型

    private var videoContent: some View {
        ZStack {
            if let image = thumbnailImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipped()
            } else {
                Color(.systemGray5)
            }

            // 播放图标
            Image(systemName: "play.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
        }
    }

    // MARK: - 音频类型

    private var audioContent: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 48, height: 48)

                Image(systemName: "waveform")
                    .font(.system(size: 22))
                    .foregroundColor(.orange)
            }

            Text("录音")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - 文件类型

    private var fileContent: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 48, height: 48)

                Image(systemName: "doc.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.blue)
            }

            Text(fileExtension)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: - Helpers

    private var fileExtension: String {
        let ext = attachment.fileName.components(separatedBy: ".").last ?? ""
        return ext.isEmpty ? "文件" : ext.uppercased()
    }

    private func loadThumbnail() {
        guard
            attachment.type == .photo
                || attachment.type == .video
                || attachment.type == .scannedDocument
                || attachment.type == .scannedText
                || attachment.type == .drawing
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

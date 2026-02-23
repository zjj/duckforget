import SwiftUI

// MARK: - 可导航的附件查看器

/// 支持左右切换的附件查看器
struct NavigableAttachmentViewerSheet: View {
    let attachments: [AttachmentItem]
    @Binding var currentIndex: Int
    @Environment(NoteStore.self) var noteStore
    @Environment(\.dismiss) private var dismiss
    
    private var currentAttachment: AttachmentItem {
        attachments[safe: currentIndex] ?? attachments.first!
    }
    
    private var canGoBack: Bool {
        currentIndex > 0
    }
    
    private var canGoForward: Bool {
        currentIndex < attachments.count - 1
    }
    
    private var isLocationAttachment: Bool {
        currentAttachment.type == .location
    }
    
    var body: some View {
        ZStack {
            // 主要内容
            TabView(selection: $currentIndex) {
                ForEach(Array(attachments.enumerated()), id: \.element.id) { index, attachment in
                    VStack(spacing: 0) {
                        attachmentContentView(for: attachment)
                            .frame(maxHeight: .infinity)
                        
                        // 页面指示器（在每个附件内容下方）
                        if attachments.count > 1 {
                            HStack(spacing: 8) {
                                ForEach(0..<attachments.count, id: \.self) { idx in
                                    Circle()
                                        .fill(idx == currentIndex ? Color.primary : Color.primary.opacity(0.3))
                                        .frame(width: 8, height: 8)
                                }
                            }
                            .padding(.vertical, 16)
                            .padding(.bottom, 8)
                        }
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color(.systemBackground))
            
            // 关闭按钮（左上角）
            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.primary.opacity(0.7))
                            .padding(12)
                            .background(
                                Circle()
                                    .fill(Color(.systemBackground).opacity(0.8))
                            )
                            .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                    }
                    .padding(.leading, 16)
                    .padding(.top, 16)
                    
                    Spacer()
                }
                Spacer()
            }
            
            // 左右导航按钮（仅地图类型显示）
            if isLocationAttachment && attachments.count > 1 {
                HStack {
                    // 左侧按钮
                    if canGoBack {
                        Button {
                            withAnimation {
                                currentIndex -= 1
                            }
                        } label: {
                            Image(systemName: "chevron.left.circle.fill")
                                .font(.system(size: 44))
                                .foregroundColor(.primary.opacity(0.6))
                                .shadow(radius: 4)
                        }
                        .padding(.leading, 20)
                    }
                    
                    Spacer()
                    
                    // 右侧按钮
                    if canGoForward {
                        Button {
                            withAnimation {
                                currentIndex += 1
                            }
                        } label: {
                            Image(systemName: "chevron.right.circle.fill")
                                .font(.system(size: 44))
                                .foregroundColor(.primary.opacity(0.6))
                                .shadow(radius: 4)
                        }
                        .padding(.trailing, 20)
                    }
                }
            }
        }
        .onTapGesture(count: 2) {
            dismiss()
        }
    }
    
    @ViewBuilder
    private func attachmentContentView(for attachment: AttachmentItem) -> some View {
        switch attachment.type {
        case .photo, .scannedDocument, .scannedText, .drawing:
            ImageViewer(attachment: attachment)
        case .video:
            VideoViewer(attachment: attachment)
        case .audio:
            AudioPlayerView(attachment: attachment)
        case .file:
            FilePreviewView(attachment: attachment)
        case .location:
            LocationViewer(attachment: attachment)
        }
    }
}

// 安全数组访问扩展
extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// MARK: - 原图附件视图

/// 原图模式下显示附件的视图
struct FullSizeAttachmentView: View {
    let attachment: AttachmentItem
    let noteStore: NoteStore
    @State private var image: UIImage?
    @State private var isLoading = true
    
    var body: some View {
        Group {
            switch attachment.type {
            case .photo, .scannedDocument, .scannedText, .drawing:
                imageView
            case .video:
                videoThumbnailView
            case .audio:
                audioPlaceholderView
            case .file:
                filePlaceholderView
            case .location:
                locationThumbnailView
            }
        }
    }
    
    private var imageView: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
            } else if isLoading {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                        .aspectRatio(4/3, contentMode: .fit)
                    
                    ProgressView()
                }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                        .aspectRatio(4/3, contentMode: .fit)
                    
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                }
            }
        }
        .onAppear { loadImage() }
    }
    
    private var videoThumbnailView: some View {
        ZStack {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
                    .aspectRatio(16/9, contentMode: .fit)
            }
            
            Image(systemName: "play.circle.fill")
                .font(.system(size: 50))
                .foregroundColor(.white)
                .shadow(radius: 4)
        }
        .onAppear { loadThumbnail() }
    }
    
    private var audioPlaceholderView: some View {
        HStack {
            Image(systemName: "waveform")
                .font(.title)
                .foregroundColor(.orange)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("音频文件")
                    .font(.headline)
                Text(attachment.type.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var filePlaceholderView: some View {
        HStack {
            Image(systemName: "doc.fill")
                .font(.title)
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("文件")
                    .font(.headline)
                Text((attachment.fileName as NSString).pathExtension.uppercased().isEmpty ? "FILE" : (attachment.fileName as NSString).pathExtension.uppercased())
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var locationThumbnailView: some View {
        ZStack {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
                    .aspectRatio(16/9, contentMode: .fit)
            }
            
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(.red)
                .shadow(radius: 4)
        }
        .onAppear { loadThumbnail() }
    }
    
    private func loadImage() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let url = noteStore.attachmentURL(for: attachment)
            if let data = try? Data(contentsOf: url),
               let loaded = UIImage(data: data) {
                DispatchQueue.main.async {
                    image = loaded
                    isLoading = false
                }
            } else {
                DispatchQueue.main.async {
                    isLoading = false
                }
            }
        }
    }
    
    private func loadThumbnail() {
        guard let thumbnailURL = noteStore.thumbnailURL(for: attachment),
              let thumbnailData = try? Data(contentsOf: thumbnailURL),
              let thumbnailImage = UIImage(data: thumbnailData) else { return }
        image = thumbnailImage
    }
}

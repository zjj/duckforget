import AVFoundation
import CoreLocation
import SwiftUI

// MARK: - 附件管理

extension NoteView {

    // MARK: 附件缩略图条

    var attachmentStripSection: some View {
        VStack(spacing: 0) {
            // 顶部模式切换按钮
            if !isEditMode && currentAttachments.count > 0 {
                HStack {
                    Spacer()
                    
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            toggleAttachmentDisplayMode()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: attachmentDisplayMode == .grid ? "square.grid.2x2" : "photo.on.rectangle")
                                .font(.system(size: 16))
                        }
                        .foregroundColor(theme.colors.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(theme.colors.accent.opacity(0.1))
                        .cornerRadius(8)
                        .contentShape(Rectangle())
                    }
                    .accessibilityLabel(attachmentDisplayMode == .grid ? "切换到全尺寸视图" : "切换到网格视图")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(theme.colors.surface)
                .zIndex(1)
            }

            // 编辑模式：收起/展开按钮
            if isEditMode && currentAttachments.count > 0 {
                HStack {
                    Text("附件 (\(currentAttachments.count))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            isAttachmentBarCollapsed.toggle()
                        }
                    } label: {
                        Image(systemName: isAttachmentBarCollapsed ? "chevron.down" : "chevron.up")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(theme.colors.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(theme.colors.accent.opacity(0.1))
                            .cornerRadius(6)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(isAttachmentBarCollapsed ? "展开附件栏" : "收起附件栏")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(theme.colors.surface)
                .zIndex(1)
            }
            
            // 附件显示区域
            if !isEditMode {
                // 预览模式：根据模式显示
                if attachmentDisplayMode == .grid {
                    // 网格布局
                    gridAttachmentView
                } else {
                    // 原图模式
                    fullSizeAttachmentView
                }
            } else if !isAttachmentBarCollapsed {
                // 编辑模式：横向滚动（未收起时显示）
                horizontalAttachmentView
            }
        }
        .background(theme.colors.surface)
    }
    
    // 网格布局
    var gridAttachmentView: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
            ForEach(Array(currentAttachments.enumerated()), id: \.element.id) { index, attachment in
                AttachmentThumbnailView(
                    attachment: attachment,
                    shouldSaveOnDelete: false,
                    showDeleteButton: false,
                    onDelete: {}
                )
                .frame(width: 100, height: 100)
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedAttachmentIndex = index
                    showAttachmentViewer = true
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    // 原图模式（垂直列表）
    var fullSizeAttachmentView: some View {
        VStack(spacing: 16) {
            ForEach(Array(currentAttachments.enumerated()), id: \.element.id) { index, attachment in
                FullSizeAttachmentView(
                    attachment: attachment,
                    noteStore: noteStore
                )
                .onTapGesture {
                    selectedAttachmentIndex = index
                    showAttachmentViewer = true
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    // 横向滚动（编辑模式）
    var horizontalAttachmentView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(Array(currentAttachments.enumerated()), id: \.element.id) { index, attachment in
                    AttachmentThumbnailView(
                        attachment: attachment,
                        shouldSaveOnDelete: false,
                        showDeleteButton: isEditMode,
                        onDelete: {
                            withAnimation {
                                _ = deletedAttachmentIDs.insert(attachment.id)
                            }
                            undoRedoManager.recordAction(.attachmentDeleted(attachmentID: attachment.id))
                            saveContentInEditMode()
                        }
                    )
                    .frame(width: 100, height: 100)
                    .onTapGesture {
                        selectedAttachmentIndex = index
                        showAttachmentViewer = true
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
    
    // 切换附件显示模式
    func toggleAttachmentDisplayMode() {
        attachmentDisplayMode = attachmentDisplayMode == .grid ? .fullSize : .grid
    }

    // MARK: 处理扫描结果

    func handleScannedImages(_ images: [UIImage], mode: ScanMode) {
        print("📷 Handling scanned images. Mode: \(mode)")
        switch mode {
        case .textExtraction:
            print("📝 Starting text recognition for \(images.count) images...")
            TextRecognizer.recognizeText(from: images) { text in
                print("✅ Recognized text length: \(text.count)")
                if text.isEmpty {
                    print("⚠️ No text recognized")
                }
                guard !text.isEmpty else { return }
                
                // 确保在主线程更新 UI
                if !content.isEmpty { content += "\n" }
                content += text
                
                // 触发保存
                wasEdited = true
            }
            
        case .documentScan:
            print("📄 Saving \(images.count) document images...")
            for image in images {
                saveImage(image, type: .scannedDocument)
            }
        }
    }

    // MARK: 处理文件选择

    func handlePickedFiles(_ urls: [URL]) {
        for url in urls {
            guard let data = try? Data(contentsOf: url) else { continue }
            let attachment = noteStore.addAttachment(
                to: note,
                type: .file,
                data: data,
                fileExtension: url.pathExtension,
                shouldSave: false
            )
            
            // 记录到undo管理器
            if let attachmentID = attachment?.id {
                undoRedoManager.recordAction(.attachmentAdded(attachmentID: attachmentID))
                previousAttachmentIDs.insert(attachmentID)
                saveContentInEditMode()
            }
        }
        wasEdited = true
    }

    // MARK: 保存位置附件
    
    func saveLocation(coordinate: CLLocationCoordinate2D, snapshot: UIImage) {
        let locationData: [String: Any] = [
            "latitude": coordinate.latitude,
            "longitude": coordinate.longitude
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: locationData),
              let snapshotData = snapshot.jpegData(compressionQuality: 0.8) else { return }
        
        let attachment = noteStore.addAttachmentWithThumbnail(
            to: note,
            type: .location,
            data: jsonData,
            thumbnailData: snapshotData,
            fileExtension: "json",
            shouldSave: false
        )
        
        // 记录到undo管理器
        if let attachmentID = attachment?.id {
            undoRedoManager.recordAction(.attachmentAdded(attachmentID: attachmentID))
            previousAttachmentIDs.insert(attachmentID)
            saveContentInEditMode()
        }
        
        wasEdited = true
    }

    // MARK: 保存图片附件

    func saveImage(_ image: UIImage, type: AttachmentType) {
        Task { @MainActor in
            // 图片压缩和缩略图渲染在后台线程执行，避免高分辨率图片阻塞主线程
            let result: (Data, Data?)? = await Task.detached(priority: .userInitiated) {
                guard let imageData = image.jpegData(compressionQuality: 0.8) else { return nil }
                let thumbSize = CGSize(width: 200, height: 200)
                let renderer = UIGraphicsImageRenderer(size: thumbSize)
                let thumbImage = renderer.image { _ in
                    // 等比缩放（aspect fill）+ 居中裁切，不拉伸图片
                    let sz = image.size
                    guard sz.width > 0, sz.height > 0 else { return }
                    let scale = max(thumbSize.width / sz.width, thumbSize.height / sz.height)
                    let scaledW = sz.width * scale
                    let scaledH = sz.height * scale
                    let x = (thumbSize.width  - scaledW) / 2
                    let y = (thumbSize.height - scaledH) / 2
                    image.draw(in: CGRect(x: x, y: y, width: scaledW, height: scaledH))
                }
                return (imageData, thumbImage.jpegData(compressionQuality: 0.6))
            }.value

            guard let (imageData, thumbnailData) = result else { return }

            // SwiftData 写入和 UI 状态更新回到主线程
            let attachment = noteStore.addAttachmentWithThumbnail(
                to: note,
                type: type,
                data: imageData,
                thumbnailData: thumbnailData,
                fileExtension: "jpg",
                shouldSave: false
            )

            // 记録到undo管理器
            if let attachmentID = attachment?.id {
                undoRedoManager.recordAction(.attachmentAdded(attachmentID: attachmentID))
                previousAttachmentIDs.insert(attachmentID)
                saveContentInEditMode()
            }

            wasEdited = true
        }
    }

    // MARK: 保存视频附件

    func saveVideo(_ url: URL) {
        Task { @MainActor in
            guard let videoData = try? Data(contentsOf: url) else { return }

            let thumbnailData = await Self.generateVideoThumbnail(from: url)
            let ext = url.pathExtension.isEmpty ? "mp4" : url.pathExtension

            let attachment = noteStore.addAttachmentWithThumbnail(
                to: note,
                type: .video,
                data: videoData,
                thumbnailData: thumbnailData,
                fileExtension: ext,
                shouldSave: false
            )

            // 记录到undo管理器
            if let attachmentID = attachment?.id {
                undoRedoManager.recordAction(.attachmentAdded(attachmentID: attachmentID))
                previousAttachmentIDs.insert(attachmentID)
                saveContentInEditMode()
            }

            wasEdited = true
        }
    }

    /// 从视频生成缩略图（async，不阻塞线程）
    static func generateVideoThumbnail(from url: URL) async -> Data? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 200, height: 200)

        return await withCheckedContinuation { continuation in
            generator.generateCGImageAsynchronously(for: .zero) { cgImage, _, _ in
                if let cgImage {
                    continuation.resume(returning: UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.6))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

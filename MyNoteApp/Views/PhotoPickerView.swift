import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// 照片/视频选择器 - 使用 PHPickerViewController
struct PhotoPickerView: UIViewControllerRepresentable {
    let onPickImage: (UIImage) -> Void
    let onPickVideo: (URL) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = 0  // 不限制数量
        config.filter = .any(of: [.images, .videos])
        config.preferredAssetRepresentationMode = .current
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPickerView
        
        init(_ parent: PhotoPickerView) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            
            for result in results {
                let provider = result.itemProvider
                
                // 处理图片
                if provider.canLoadObject(ofClass: UIImage.self) {
                    provider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
                        if let image = object as? UIImage {
                            DispatchQueue.main.async {
                                self?.parent.onPickImage(image)
                            }
                        }
                    }
                }
                // 处理视频
                else if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                    provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [weak self] url, error in
                        guard let url = url else { return }
                        
                        // 复制到临时目录（原始 URL 是临时的，会被系统清理）
                        let tempURL = FileManager.default.temporaryDirectory
                            .appendingPathComponent(UUID().uuidString)
                            .appendingPathExtension(url.pathExtension)
                        
                        do {
                            try FileManager.default.copyItem(at: url, to: tempURL)
                            DispatchQueue.main.async {
                                self?.parent.onPickVideo(tempURL)
                            }
                        } catch {
                            print("❌ 复制视频失败: \(error)")
                        }
                    }
                }
            }
        }
    }
}

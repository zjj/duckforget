import SwiftUI
import PencilKit

struct PaintingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var canvasView = PKCanvasView()
    @State private var toolPicker = PKToolPicker()
    
    var onSave: (Data) -> Void
    
    var body: some View {
        NavigationView {
            CanvasViewControllerRepresentable(canvasView: $canvasView, toolPicker: $toolPicker)
                .navigationTitle("涂鸦")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") {
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") {
                            saveDrawing()
                        }
                    }
                }
        }
    }
    
    private func saveDrawing() {
        // 获取绘制区域的内容
        let drawing = canvasView.drawing
        let bounds = drawing.bounds
        
        // 如果有绘制内容
        if !bounds.isEmpty && bounds.size.width > 0 && bounds.size.height > 0 {
            // 生成图片
            let image = drawing.image(from: bounds, scale: 1.0)
            if let imageData = image.pngData() {
                onSave(imageData)
            }
        }
        dismiss()
    }
}

struct CanvasViewControllerRepresentable: UIViewControllerRepresentable {
    @Binding var canvasView: PKCanvasView
    @Binding var toolPicker: PKToolPicker

    func makeUIViewController(context: Context) -> CanvasViewController {
        let controller = CanvasViewController()
        controller.canvasView = canvasView
        controller.toolPicker = toolPicker
        return controller
    }

    func updateUIViewController(_ uiViewController: CanvasViewController, context: Context) {
        // 更新逻辑不需要特别处理
    }
}

class CanvasViewController: UIViewController {
    var canvasView: PKCanvasView!
    var toolPicker: PKToolPicker!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        canvasView.drawingPolicy = .anyInput // 支持手指和 Apple Pencil
        canvasView.backgroundColor = .systemBackground
        view.addSubview(canvasView)
        
        canvasView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            canvasView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            canvasView.topAnchor.constraint(equalTo: view.topAnchor),
            canvasView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        // 设置工具栏
        toolPicker.setVisible(true, forFirstResponder: canvasView)
        toolPicker.addObserver(canvasView)
        canvasView.becomeFirstResponder()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
    }
}

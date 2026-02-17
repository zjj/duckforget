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
            // 生成带白色背景的图片
            // 1. 获取透明背景的绘制图片
            let drawingImage = drawing.image(from: bounds, scale: 1.0)
            
            // 2. 创建一个同等大小的白色背景图片上下文
            let format = UIGraphicsImageRendererFormat()
            format.scale = drawingImage.scale
            let renderer = UIGraphicsImageRenderer(size: bounds.size, format: format)
            
            let finalImage = renderer.image { context in
                // 填充白色背景
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: bounds.size))
                
                // 绘制涂鸦内容
                drawingImage.draw(in: CGRect(origin: .zero, size: bounds.size))
            }
            
            if let imageData = finalImage.pngData() {
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
        
        // 强制使用浅色模式，确保背景为白色，笔迹为深色
        overrideUserInterfaceStyle = .light
        
        canvasView.drawingPolicy = .anyInput // 支持手指和 Apple Pencil
        canvasView.backgroundColor = .white // 明确设置为白色
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

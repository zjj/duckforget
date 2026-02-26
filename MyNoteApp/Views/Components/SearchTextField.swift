import SwiftUI
import UIKit

/// 搜索专用输入框
///
/// SwiftUI 原生 TextField 在每次 IME 键入（如拼音字母）时都会更新 binding，
/// 导致拼音组字过程中触发大量无效查询。
/// 该组件封装 UITextField，仅在 markedTextRange == nil（即没有正在组字的标记文本）
/// 时才向 binding 写入，从而避免拼音/日文等输入法中间态污染搜索结果。
struct SearchTextField: UIViewRepresentable {

    let placeholder: String
    @Binding var text: String
    @Binding var isFocused: Bool
    var onSubmit: (() -> Void)? = nil

    // 读取 SwiftUI 颜色方案，使 UITextField 的文字 / 占位符颜色随深色模式自动适配
    @Environment(\.colorScheme) private var colorScheme

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        // ── 外观：与 SwiftUI TextField 保持一致 ──
        tf.borderStyle = .none
        tf.backgroundColor = .clear
        tf.font = UIFont.preferredFont(forTextStyle: .body)
        tf.adjustsFontForContentSizeCategory = true  // 支持 Dynamic Type
        tf.textColor = .label

        // ── 行为 ──
        tf.returnKeyType = .search
        tf.clearButtonMode = .never
        tf.autocorrectionType = .no
        tf.spellCheckingType = .no
        tf.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tf.setContentHuggingPriority(.required, for: .vertical)
        tf.delegate = context.coordinator
        tf.addTarget(
            context.coordinator,
            action: #selector(Coordinator.editingChanged(_:)),
            for: .editingChanged
        )
        return tf
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        // 只在没有组字状态时同步外部 text，避免覆盖 IME 标记区域
        if uiView.markedTextRange == nil, uiView.text != text {
            uiView.text = text
        }

        // 占位符颜色随深色模式变化
        uiView.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor.placeholderText]
        )

        // 由 SwiftUI 状态驱动焦点
        if isFocused, !uiView.isFirstResponder {
            DispatchQueue.main.async { uiView.becomeFirstResponder() }
        } else if !isFocused, uiView.isFirstResponder {
            DispatchQueue.main.async { uiView.resignFirstResponder() }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: SearchTextField

        init(_ parent: SearchTextField) {
            self.parent = parent
        }

        /// 每次文字变化时，仅在无 markedText 时提交给 binding
        @objc func editingChanged(_ tf: UITextField) {
            guard tf.markedTextRange == nil else { return }
            parent.text = tf.text ?? ""
        }

        /// IME 确认后（markedTextRange 变为 nil）同步最终文本
        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            return true // 让 UITextField 自行处理，editingChanged 会在之后触发
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.isFocused = true
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            // 确认最终文本（用户完成输入后）
            if let t = textField.text {
                parent.text = t
            }
            parent.isFocused = false
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onSubmit?()
            textField.resignFirstResponder()
            return true
        }
    }
}

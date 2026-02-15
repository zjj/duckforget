import SwiftUI
import UIKit

/// 可追踪光标位置的 UITextView 包装
struct CursorTrackingTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var cursorPosition: Int
    var onFocusChange: ((Bool) -> Void)?
    var onUndoStateChange: ((Bool, Bool) -> Void)?
    var onCoordinatorReady: ((Coordinator) -> Void)?
    var font: UIFont = .preferredFont(forTextStyle: .body)

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.font = font
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        // 确保 allowsUndo 开启
        textView.allowsEditingTextAttributes = false
        context.coordinator.textView = textView
        // 通知外部 coordinator 已就绪
        DispatchQueue.main.async {
            onCoordinatorReady?(context.coordinator)
        }
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.parent = self

        // 仅在外部修改时更新（避免循环）
        guard uiView.text != text else {
            // 文本相同，只同步光标
            if uiView.selectedRange.location != cursorPosition {
                let maxPos = (text as NSString).length
                let targetPos = min(cursorPosition, maxPos)
                uiView.selectedRange = NSRange(location: targetPos, length: 0)
            }
            return
        }

        // 标记正在做程序化更新，避免 delegate 中写回触发循环
        context.coordinator.isUpdatingFromBinding = true

        // 使用 UITextView 的 replace 方法来保留 undo 栈
        // 选中全部文本，然后替换
        uiView.selectedRange = NSRange(location: 0, length: (uiView.text as NSString).length)
        uiView.insertText(text)

        // 恢复光标位置
        let maxPos = (text as NSString).length
        let targetPos = min(cursorPosition, maxPos)
        uiView.selectedRange = NSRange(location: targetPos, length: 0)

        context.coordinator.isUpdatingFromBinding = false

        // 自动滚动到光标位置
        DispatchQueue.main.async {
            if let range = uiView.selectedTextRange {
                let caretRect = uiView.caretRect(for: range.start)
                uiView.scrollRectToVisible(caretRect, animated: false)
            }
            // 更新 undo 状态
            context.coordinator.notifyUndoState()
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: CursorTrackingTextView
        weak var textView: UITextView?
        var isUpdatingFromBinding = false

        init(_ parent: CursorTrackingTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isUpdatingFromBinding else { return }
            parent.text = textView.text
            parent.cursorPosition = textView.selectedRange.location
            notifyUndoState()
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isUpdatingFromBinding else { return }
            parent.cursorPosition = textView.selectedRange.location
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.onFocusChange?(true)
            notifyUndoState()
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.onFocusChange?(false)
        }

        func notifyUndoState() {
            let canUndo = textView?.undoManager?.canUndo ?? false
            let canRedo = textView?.undoManager?.canRedo ?? false
            parent.onUndoStateChange?(canUndo, canRedo)
        }

        /// 外部调用：将光标移到指定位置
        func setCursor(to position: Int) {
            guard let tv = textView else { return }
            let maxPos = (tv.text as NSString).length
            let safe = min(position, maxPos)
            tv.selectedRange = NSRange(location: safe, length: 0)
            parent.cursorPosition = safe
        }

        /// 外部调用：聚焦
        func focus() {
            textView?.becomeFirstResponder()
        }

        /// 外部调用：取消聚焦
        func blur() {
            textView?.resignFirstResponder()
        }

        /// 外部调用：撤销
        func undo() {
            guard let tv = textView, let mgr = tv.undoManager, mgr.canUndo else { return }
            mgr.undo()
            syncAfterUndoRedo()
        }

        /// 外部调用：重做
        func redo() {
            guard let tv = textView, let mgr = tv.undoManager, mgr.canRedo else { return }
            mgr.redo()
            syncAfterUndoRedo()
        }

        /// 获取当前选中范围
        func getSelectedRange() -> NSRange? {
            return textView?.selectedRange
        }

        /// 获取完整文本
        func getText() -> String? {
            return textView?.text
        }

        /// 替换指定范围的文本（保留 undo 栈）
        func replaceRange(_ range: NSRange, with replacement: String) {
            guard let tv = textView else { return }
            guard
                let textRange = tv.textRange(
                    from: tv.position(from: tv.beginningOfDocument, offset: range.location)!,
                    to: tv.position(
                        from: tv.beginningOfDocument, offset: range.location + range.length)!
                )
            else { return }
            tv.replace(textRange, withText: replacement)
            parent.text = tv.text
            parent.cursorPosition = tv.selectedRange.location
            notifyUndoState()
        }

        /// 在当前光标位置插入文本
        func insertAtCursor(_ text: String) {
            guard let tv = textView else { return }
            tv.insertText(text)
            parent.text = tv.text
            parent.cursorPosition = tv.selectedRange.location
            notifyUndoState()
        }

        /// 清除 undo/redo 栈（用于初始加载后）
        func clearUndoStack() {
            guard let tv = textView else { return }
            tv.undoManager?.removeAllActions()
            notifyUndoState()
        }

        private func syncAfterUndoRedo() {
            guard let tv = textView else { return }
            parent.text = tv.text
            parent.cursorPosition = tv.selectedRange.location
            notifyUndoState()
        }
    }
}

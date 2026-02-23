import SwiftUI

// MARK: - 富文本格式

extension NoteView {

    /// 应用 Markdown 格式（加粗/斜体），插入到内容末尾
    func applyTextFormat(_ format: TextFormat) {
        switch format {
        case .bold: applyFormatAction(.bold)
        case .italic: applyFormatAction(.italic)
        }
    }

    /// 在当前行开头插入前缀（标题、列表等）
    func insertPrefix(_ prefix: String) {
        switch prefix {
        case "• ", "- ": applyFormatAction(.bullet)
        case "1. ": applyFormatAction(.numbered)
        default:
            if let coord = markdownCoordinator {
                coord.insertBlockAtCursor(prefix)
            } else {
                if !content.isEmpty && !content.hasSuffix("\n") { content += "\n" }
                content += prefix
            }
        }
    }

    /// 切换当前行的待办复选框
    func toggleTodoCheckbox() {
        guard currentLineIsTodo else { return }
        
        // 触发按压动画
        withAnimation(.easeInOut(duration: 0.15)) {
            todoToggleButtonPressed = true
        }
        
        // 触发震动反馈
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        // 执行切换
        markdownCoordinator?.toggleTodoOnCurrentLine()
        
        // 延迟更新状态和恢复按钮
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            updateCurrentLineTodoStatus()
            withAnimation(.easeInOut(duration: 0.15)) {
                todoToggleButtonPressed = false
            }
        }
    }
    
    /// 更新当前行的待办状态
    func updateCurrentLineTodoStatus() {
        guard let coord = markdownCoordinator else {
            currentLineIsTodo = false
            currentLineIsTodoChecked = false
            return
        }
        
        let lineText = coord.getCurrentLineText()
        currentLineIsTodo = lineText.hasPrefix("- [ ] ") || lineText.hasPrefix("- [x] ") || lineText.hasPrefix("- [X] ")
        currentLineIsTodoChecked = lineText.hasPrefix("- [x] ") || lineText.hasPrefix("- [X] ")
    }

    /// 应用格式操作（支持选中文本时包裹、无选中时插入）
    func applyFormatAction(_ action: FormatMenuSheet.FormatAction) {
        guard let coord = markdownCoordinator else {
            // Fallback: append to end
            let text = action.rawMarkdown
            if !content.isEmpty && !content.hasSuffix("\n") { content += "\n" }
            content += text
            return
        }

        switch action {
        // Inline formats: wrap selection or insert with placeholder
        case .bold:
            coord.applyInlineFormat(prefix: "**", suffix: "**", placeholder: "粗体文本")
        case .italic:
            coord.applyInlineFormat(prefix: "*", suffix: "*", placeholder: "斜体文本")
        case .strikethrough:
            coord.applyInlineFormat(prefix: "~~", suffix: "~~", placeholder: "删除线文本")
        case .code:
            coord.applyInlineFormat(prefix: "`", suffix: "`", placeholder: "代码")
        case .link:
            coord.applyInlineFormat(prefix: "[", suffix: "]()", placeholder: "链接文本")
        case .image:
            coord.applyInlineFormat(prefix: "![", suffix: "]()", placeholder: "图片描述")

        // Block formats: add prefix to line or toggle
        case .h1:
            coord.applyBlockFormat(prefix: "# ")
        case .h2:
            coord.applyBlockFormat(prefix: "## ")
        case .h3:
            coord.applyBlockFormat(prefix: "### ")
        case .quote:
            coord.applyBlockFormat(prefix: "> ")
        case .bullet:
            coord.applyBlockFormat(prefix: "- ")
        case .numbered:
            coord.applyBlockFormat(prefix: "1. ")
        case .checkbox:
            coord.applyBlockFormat(prefix: "- [ ] ")

        // Special blocks: insert as-is
        case .codeBlock:
            coord.insertBlockAtCursor("```\n代码块\n```")
        case .divider:
            coord.insertBlockAtCursor("---\n")
        }
    }
}

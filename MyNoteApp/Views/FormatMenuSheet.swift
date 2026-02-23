import SwiftUI

// MARK: - 格式菜单

struct FormatMenuSheet: View {
    let onSelect: (FormatAction) -> Void

    enum FormatAction: String, CaseIterable, Identifiable {
        case h1, h2, h3
        case bold, italic, strikethrough
        case code, codeBlock
        case quote, bullet, numbered, checkbox
        case divider
        case link, image

        var id: String { rawValue }

        var title: String {
            switch self {
            case .h1: return "h1"
            case .h2: return "h2"
            case .h3: return "h3"
            case .bold: return "粗体"
            case .italic: return "斜体"
            case .strikethrough: return "删除线"
            case .code: return "内联代码"
            case .codeBlock: return "代码块"
            case .quote: return "引用"
            case .bullet: return "无序列表"
            case .numbered: return "有序列表"
            case .checkbox: return "待办事项"
            case .divider: return "分割线"
            case .link: return "链接"
            case .image: return "图片"
            }
        }

        var icon: String {
            switch self {
            case .h1: return "textformat.size.larger"
            case .h2: return "textformat.size"
            case .h3: return "textformat.size.smaller"
            case .bold: return "bold"
            case .italic: return "italic"
            case .strikethrough: return "strikethrough"
            case .code: return "chevron.left.forwardslash.chevron.right"
            case .codeBlock: return "terminal"
            case .quote: return "text.quote"
            case .bullet: return "list.bullet"
            case .numbered: return "list.number"
            case .checkbox: return "checklist"
            case .divider: return "minus"
            case .link: return "link"
            case .image: return "photo"
            }
        }

        /// 自定义文字标签（侄先于 SF Symbol 图标）
        var customLabel: String? {
            switch self {
            case .h1: return "#"
            case .h2: return "##"
            case .h3: return "###"
            default: return nil
            }
        }

        var preview: String {
            switch self {
            case .h1: return "# 标题"
            case .h2: return "## 标题"
            case .h3: return "### 标题"
            case .bold: return "**文本**"
            case .italic: return "*文本*"
            case .strikethrough: return "~~文本~~"
            case .code: return "`代码`"
            case .codeBlock: return "```代码块```"
            case .quote: return "> 引用文本"
            case .bullet: return "- 列表项"
            case .numbered: return "1. 列表项"
            case .checkbox: return "- [ ] 待办"
            case .divider: return "---"
            case .link: return "[文本](url)"
            case .image: return "![图片](url)"
            }
        }

        /// Returns the raw markdown string for fallback insertion
        var rawMarkdown: String {
            switch self {
            case .h1: return "# 标题\n"
            case .h2: return "## 标题\n"
            case .h3: return "### 标题\n"
            case .bold: return "**粗体文字**"
            case .italic: return "*斜体文字*"
            case .strikethrough: return "~~删除线~~"
            case .code: return "`代码`"
            case .codeBlock: return "```\n代码块\n```\n"
            case .quote: return "> 引用文本\n"
            case .bullet: return "- 列表项\n"
            case .numbered: return "1. 列表项\n"
            case .checkbox: return "- [ ] 待办事项\n"
            case .divider: return "\n---\n"
            case .link: return "[链接文本]()"
            case .image: return "![图片描述]()"
            }
        }

        var color: Color {
            switch self {
            case .h1, .h2, .h3: return .purple
            case .bold, .italic, .strikethrough: return .blue
            case .code, .codeBlock: return .orange
            case .quote: return .green
            case .bullet, .numbered, .checkbox: return .teal
            case .divider: return .gray
            case .link: return .indigo
            case .image: return .pink
            }
        }
    }

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        VStack(spacing: 0) {
            // 标题
            HStack {
                Text("插入格式")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                Text("长按文字区域唤起")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(FormatAction.allCases.filter { $0 != .image }) { action in
                        Button {
                            onSelect(action)
                        } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(action.color.opacity(0.12))
                                        .frame(height: 44)

                                    if let label = action.customLabel {
                                        Text(label)
                                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                                            .foregroundColor(action.color)
                                    } else {
                                        Image(systemName: action.icon)
                                            .font(.system(size: 20, weight: .medium))
                                            .foregroundColor(action.color)
                                    }
                                }

                                Text(action.title)
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)

                                Text(action.preview)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 6)
                            .background(Color(.systemBackground))
                            .cornerRadius(12)
                            .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
    }
}

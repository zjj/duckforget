import SwiftUI

/// 浮动上下文菜单 - 悬浮显示 Markdown 快捷操作
/// 包含：Todo切换｜Markdown图标网格
struct FloatingContextMenu: View {
    let isTodoLine: Bool
    let isTodoChecked: Bool

    let onToggleTodo: () -> Void
    let onFormatAction: (FormatMenuSheet.FormatAction) -> Void
    let onDismiss: () -> Void

    private static let quickFormats: [FormatMenuSheet.FormatAction] = [
        .h1, .h2, .h3,
        .bold, .italic, .strikethrough,
        .code, .codeBlock,
        .quote, .bullet, .numbered, .checkbox, .divider
    ]

    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Todo 切换
            if isTodoLine {
                Button {
                    onToggleTodo(); onDismiss()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isTodoChecked ? "square" : "checkmark.square.fill")
                            .font(.system(size: 16))
                        Text(isTodoChecked ? "标记未完成" : "标记已完成")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .foregroundColor(isTodoChecked ? .orange : .green)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                Divider().padding(.horizontal, 10)
            }

            // MARK: - Markdown 格式图标网格
            LazyVGrid(columns: gridColumns, spacing: 6) {
                ForEach(Self.quickFormats) { action in
                    Button {
                        onFormatAction(action); onDismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: action.icon)
                                .font(.system(size: 14))
                                .foregroundColor(action.color)
                            
                            Text(action.title)
                                .font(.system(size: 12))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                        .background(action.color.opacity(0.08))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
        }
        .frame(width: 310)
        .background(.thinMaterial)
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.15), radius: 14, x: 0, y: 4)
    }
}

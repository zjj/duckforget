import SwiftUI
import UIKit

/// 富文本编辑器 - 支持粗体、斜体、列表、标题
struct RichTextToolbar: View {
    let onBold: () -> Void
    let onItalic: () -> Void
    let onBulletList: () -> Void
    let onNumberedList: () -> Void
    let onDismissKeyboard: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                formatButton(icon: "bold", action: onBold)
                formatButton(icon: "italic", action: onItalic)

                Divider()
                    .frame(height: 24)
                    .padding(.horizontal, 4)

                Divider()
                    .frame(height: 24)
                    .padding(.horizontal, 4)

                formatButton(icon: "list.bullet", action: onBulletList)
                formatButton(icon: "list.number", action: onNumberedList)

                Spacer()

                // 收起键盘按钮
                Button(action: onDismissKeyboard) {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 16))
                        .foregroundColor(.accentColor)
                        .frame(width: 36, height: 36)
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 40)
        .background(Color(.systemGray6))
    }

    private func formatButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.primary)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
    }
}

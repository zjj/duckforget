import SwiftUI

/// 快捷输入组件 - 直接在 Dashboard 内输入文字并保存为记录，无需跳转页面
/// 右上角展开按钮可跳转到完整的富文本编辑器（支持附件等）
struct InlineInputWidget: View {
    let size: WidgetSize
    var onFocused: (() -> Void)? = nil
    @Environment(NoteStore.self) var noteStore
    @Environment(\.appTheme) private var theme
    @Environment(FontManager.self) private var fontManager

    @State private var inputText = ""
    @State private var showSavedFeedback = false
    @State private var feedbackTask: Task<Void, Never>?
    @State private var fullEditorRequest: FullEditorRequest? = nil
    @FocusState private var isFocused: Bool

    /// 用于传递内容到全屏编辑器的包装类型
    private struct FullEditorRequest: Identifiable {
        let id = UUID()
        let content: String
    }

    var body: some View {
        Group {
            switch size {
            case .small:
                smallLayout
            case .medium:
                mediumLayout
            case .large, .fullPage:
                largeLayout
            }
        }
        .onChange(of: isFocused) { _, focused in
            if focused {
                // 延迟一点让键盘动画开始后再滚动，确保 List 已调整 contentInset
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    onFocused?()
                }
            }
        }
        .fullScreenCover(item: $fullEditorRequest) { request in
            NewNoteModalView(
                isPresented: Binding(
                    get: { fullEditorRequest != nil },
                    set: { if !$0 { fullEditorRequest = nil } }
                ),
                initialContent: request.content,
                deleteOnCancel: true
            )
            .onDisappear { inputText = "" }
        }
    }

    // MARK: - Small Layout

    private var smallLayout: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.colors.accent)

            TextField("快捷输入...", text: $inputText)
                .font(Font(fontManager.bodyFont(size: 14)))
                .foregroundColor(theme.colors.primaryText)
                .focused($isFocused)

            if !inputText.isEmpty {
                publishButton(compact: true)
            }

            expandButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, minHeight: size.height)
        .background(cardBackground(cornerRadius: 12))
        .shadow(color: theme.colors.shadow, radius: 6, x: 0, y: 2)
        .overlay(savedOverlay(cornerRadius: 12))
    }

    // MARK: - Medium Layout

    private var mediumLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow

            ZStack(alignment: .topLeading) {
                if inputText.isEmpty {
                    Text("有什么想法，直接输入...")
                        .font(Font(fontManager.bodyFont(size: 15)))
                        .foregroundColor(theme.colors.secondaryText.opacity(0.4))
                        .padding(.top, 8)
                        .padding(.horizontal, 4)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $inputText)
                    .font(Font(fontManager.bodyFont(size: 15)))
                    .foregroundColor(theme.colors.primaryText)
                    .scrollContentBackground(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                    .focused($isFocused)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { isFocused = true }

            if !inputText.isEmpty {
                HStack {
                    Spacer()
                    publishButton(compact: false)
                }
            }
        }
        .padding(16)
        .frame(minHeight: size.height)
        .background(cardBackground(cornerRadius: 16))
        .shadow(color: theme.colors.shadow, radius: 8, x: 0, y: 2)
        .overlay(savedOverlay(cornerRadius: 16))
    }

    // MARK: - Large / FullPage Layout

    private var largeLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow

            ZStack(alignment: .topLeading) {
                if inputText.isEmpty {
                    Text("有什么想法，直接输入...")
                        .font(Font(fontManager.bodyFont(size: 16)))
                        .foregroundColor(theme.colors.secondaryText.opacity(0.4))
                        .padding(.top, 8)
                        .padding(.horizontal, 4)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $inputText)
                    .font(Font(fontManager.bodyFont(size: 16)))
                    .foregroundColor(theme.colors.primaryText)
                    .scrollContentBackground(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                    .focused($isFocused)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { isFocused = true }

            if !inputText.isEmpty {
                HStack {
                    clearButton
                    Spacer()
                    publishButton(compact: false)
                }
            }
        }
        .padding(16)
        .frame(minHeight: size.height)
        .background(cardBackground(cornerRadius: 16))
        .shadow(color: theme.colors.shadow, radius: 8, x: 0, y: 2)
        .overlay(savedOverlay(cornerRadius: 16))
    }

    // MARK: - Shared Components

    private var headerRow: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(theme.colors.accent.opacity(0.12))
                    .frame(width: 30, height: 30)
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.colors.accent)
            }
            Text("快捷输入")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(theme.colors.primaryText)
            Spacer()
            expandButton
        }
    }

    /// 展开按钮 - 跳转到完整富文本编辑器
    private var expandButton: some View {
        Button {
            isFocused = false
            fullEditorRequest = FullEditorRequest(content: inputText)
        } label: {
            Image(systemName: "rectangle.expand.diagonal")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.colors.secondaryText.opacity(0.5))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func publishButton(compact: Bool) -> some View {
        Button {
            saveNote()
        } label: {
            if compact {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(theme.colors.accent)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(theme.colors.accent)
            }
        }
        .buttonStyle(.plain)
    }

    private var clearButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) {
                inputText = ""
            }
        } label: {
            Text("清空")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(theme.colors.secondaryText)
        }
        .buttonStyle(.plain)
    }


    private func cardBackground(cornerRadius: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(theme.colors.card)
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        }
    }

    private func savedOverlay(cornerRadius: CGFloat) -> some View {
        Group {
            if showSavedFeedback {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(theme.colors.accent.opacity(0.12))
                    VStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(theme.colors.accent)
                        Text("已保存")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(theme.colors.accent)
                    }
                }
                .transition(.opacity)
            }
        }
    }

    // MARK: - Actions

    private func saveNote() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // 创建新记录并保存
        let note = noteStore.createNote()
        note.content = trimmed
        noteStore.updateNote(note)

        // 触觉反馈
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        // 显示保存成功
        withAnimation(.easeInOut(duration: 0.25)) {
            showSavedFeedback = true
        }

        // 重置输入
        isFocused = false
        feedbackTask?.cancel()
        feedbackTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                showSavedFeedback = false
                inputText = ""
            }
        }
    }
}

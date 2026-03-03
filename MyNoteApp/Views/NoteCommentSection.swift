import SwiftUI

// MARK: - 评论区 (Preview 模式下内嵌)

struct NoteCommentSection: View {
    let note: NoteItem
    /// 由父视图 (NoteView) 传入：外部可通过将此值设为 true 来触发"添加评论"输入框
    @Binding var addCommentTrigger: Bool

    @Environment(NoteStore.self) private var noteStore
    @Environment(\.appTheme) private var theme

    @State private var showCommentInput = false
    @State private var editingComment: CommentItem? = nil
    @State private var commentInputText = ""

    private var comments: [CommentItem] {
        noteStore.getComments(for: note)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── 标题行 ──
            HStack(spacing: 4) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("评论")
                    .font(.subheadline.bold())
                if !comments.isEmpty {
                    Text("(\(comments.count))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)

            Divider()

            // ── 评论列表 ──
            ForEach(comments) { comment in
               CommentRowView(comment: comment) {
                      // 编辑
                    editingComment = comment
                    commentInputText = comment.content
                    showCommentInput = true
                } onDelete: {
                    withAnimation {
                        noteStore.deleteComment(comment)
                    }
                }

                if comment.id != comments.last?.id {
                    Divider()
                        .padding(.leading, 16)
                  }
            }

           Divider()

            // ── 添加评论按钮 ──
            Button {
                openAddComment()
            } label: {
                Label("添加评论", systemImage: "plus.bubble")
                    .font(.subheadline)
                    .foregroundStyle(theme.colors.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .accessibilityLabel("添加评论")
        }
        // ── 评论输入 Sheet ──
        .sheet(isPresented: $showCommentInput, onDismiss: resetInputState) {
            CommentInputSheet(
                initialText: commentInputText,
                isEditing: editingComment != nil
            ) { submittedText in
                if let existing = editingComment {
                    noteStore.updateComment(existing, content: submittedText)
                } else {
                    noteStore.addComment(to: note, content: submittedText)
                }
                resetInputState()
                showCommentInput = false
            } onCancel: {
                resetInputState()
                showCommentInput = false
            }
            .presentationDetents([.height(220)])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(20)
        }
        // 外部触发（来自 "..." 菜单）
        .onChange(of: addCommentTrigger) { _, triggered in
            if triggered {
                addCommentTrigger = false
                openAddComment()
            }
        }
    }

    // MARK: - Helpers

    private func openAddComment() {
        editingComment = nil
        commentInputText = ""
        showCommentInput = true
    }

    private func resetInputState() {
        editingComment = nil
        commentInputText = ""
    }
}

// MARK: - 单条评论行

private struct CommentRowView: View {
    let comment: CommentItem
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(comment.content)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                Text(comment.createdAt.formattedFull)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                if comment.updatedAt > comment.createdAt.addingTimeInterval(1) {
                    Text("· 已编辑")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                onEdit()
            } label: {
                Label("编辑", systemImage: "pencil")
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }
}

// MARK: - 评论输入 Sheet

struct CommentInputSheet: View {
    let initialText: String
    let isEditing: Bool
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Button("取消") { onCancel() }
                    .foregroundStyle(.secondary)

                Spacer()

                Text(isEditing ? "编辑评论" : "添加评论")
                    .font(.headline)

                Spacer()

                Button("发送") {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    onSubmit(trimmed)
                }
                .fontWeight(.semibold)
                .foregroundStyle(
                    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? Color.secondary
                        : theme.colors.accent
                )
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            TextField("写下你的评论…", text: $text, axis: .vertical)
                .lineLimit(4...)
                .font(.body)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .focused($isFocused)
        }
        .background(.background)
        .onAppear {
            text = initialText
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                isFocused = true
            }
        }
    }
}

import SwiftUI

/// 通用笔记卡片列表组件，用于 medium（水平滚动卡片）和 large（垂直网格）展示。
/// TagWidget 和 RecentNotesWidget 的 medium/large 模式共用此组件。
struct NoteCardListWidget: View {
    @Environment(NoteStore.self) var noteStore
    @Environment(\.appTheme) private var theme

    let title: String
    let icon: String
    let notes: [NoteItem]
    let totalCount: Int
    let size: WidgetSize
    let isEditing: Bool
    let destination: NoteSearchPage

    private var cardWidth:  CGFloat { size == .small ? 105 : size == .medium ? 145 : 160 }
    private var cardHeight: CGFloat { size == .small ?  50 : size == .medium ?  95 : 128 }

    var body: some View {
        if size == .large {
            largeLayout
        } else {
            mediumLayout
        }
    }

    // MARK: - Title Bar (shared)

    private var titleBar: some View {
        ZStack(alignment: .leading) {
            NavigationLink(destination: destination.environment(noteStore)) {
                EmptyView()
            }
            .opacity(0)
            .disabled(isEditing)

            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(theme.colors.accent)
                    .font(.system(size: icon == "clock" ? 14 : 13, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(theme.colors.secondaryText)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.45))
            }
            .padding(.horizontal, 14)
            .allowsHitTesting(!isEditing)
        }
    }

    // MARK: - Large: 垂直网格

    private var largeLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            titleBar

            if notes.isEmpty {
                Text("暂无记录")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    let columns = [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ]
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(notes) { note in
                            NavigationLink(destination: NoteView(note: note, startInEditMode: false).environment(noteStore)) {
                                WidgetNoteCard(note: note, size: size, gridMode: true)
                                    .environment(noteStore)
                            }
                            .buttonStyle(.plain)
                            .disabled(isEditing)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .padding(.vertical, 8)
        .frame(height: size.height)
        .background(theme.colors.surface)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(color: theme.colors.shadow, radius: 8, x: 0, y: 2)
    }

    // MARK: - Medium/Small: 水平滚动卡片

    private var mediumLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            titleBar

            if notes.isEmpty {
                Text("暂无记录")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(notes) { note in
                            NavigationLink(destination: NoteView(note: note, startInEditMode: false).environment(noteStore)) {
                                WidgetNoteCard(note: note, size: size)
                                    .environment(noteStore)
                            }
                            .buttonStyle(.plain)
                            .disabled(isEditing)
                        }

                        // 查看更多
                        NavigationLink(destination: destination.environment(noteStore)) {
                            VStack(spacing: 4) {
                                Spacer()
                                let remaining = totalCount - notes.count
                                if remaining > 0 {
                                    Text("+\(remaining)")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(theme.colors.accent)
                                    Text("更多")
                                        .font(.system(size: 10))
                                        .foregroundColor(theme.colors.secondaryText.opacity(0.7))
                                } else {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(theme.colors.accent.opacity(0.6))
                                }
                                Spacer()
                            }
                            .frame(width: cardWidth, height: cardHeight)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(theme.colors.card.opacity(0.6))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.primary.opacity(0.05), lineWidth: 0.5)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isEditing)
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding(.vertical, 8)
        .background(theme.colors.surface)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(color: theme.colors.shadow, radius: 8, x: 0, y: 2)
    }
}

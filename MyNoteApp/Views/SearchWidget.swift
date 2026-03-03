import SwiftUI
import SwiftData

struct SearchWidget: View {
    @Environment(NoteStore.self) var noteStore
    let size: WidgetSize
    @Binding var showSearch: Bool
    @Environment(\.appTheme) private var theme
    
    var body: some View {
        Group {
            if size == .fullPage {
                // 全屏嵌入模式：显示预览界面，点击跳转到完整搜索页
                SearchFullPagePreview(onTap: { showSearch = true })
            } else {
                searchCard
            }
        }
    }
    
    private var searchCard: some View {
        Button {
            showSearch = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(theme.colors.secondaryText)

                Text("搜索")
                    .font(.system(size: 17))
                    .foregroundColor(theme.colors.secondaryText)

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(theme.colors.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
            .shadow(color: theme.colors.shadow, radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Full Page Preview

/// 搜索组件的全屏预览（嵌入模式）
struct SearchFullPagePreview: View {
    let onTap: () -> Void
    @Environment(\.appTheme) private var theme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Title
            Text("搜索")
                .font(.system(size: 28, weight: .bold))
                .padding(.horizontal, 16)
                .padding(.top, 16)

            // Apple-style search bar
            Button(action: onTap) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(theme.colors.secondaryText)
                        .font(.system(size: 16, weight: .medium))

                    Text("搜索...")
                        .foregroundColor(theme.colors.secondaryText)
                        .font(.system(size: 17))

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(theme.colors.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                        )
                )
                .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)

            // Placeholder hint
            VStack(spacing: 12) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 44))
                    .foregroundStyle(theme.colors.secondaryText.opacity(0.35))
                    .symbolRenderingMode(.hierarchical)

                Text("点击即可开始搜索")
                    .font(.subheadline)
                    .foregroundColor(theme.colors.secondaryText.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 32)

            Spacer()
        }
        .background(theme.colors.surface)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

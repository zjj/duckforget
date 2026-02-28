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
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(theme.colors.accent)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("搜索")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("输入进行搜索...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer() // 确保HStack填满宽度
            }
            .frame(maxWidth: .infinity) // 关键：让HStack填满父容器宽度
            .padding(16)
            .background(theme.colors.surface)
            .cornerRadius(16)
            .shadow(color: theme.colors.shadow, radius: 6, x: 0, y: 3)
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
        VStack(alignment: .leading, spacing: 16) {
            // 标题
            Text("搜索")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.horizontal)
                .padding(.top, 16)
            
            // 搜索框（伪）
            Button(action: onTap) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    Text("输入进行搜索...")
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
                .padding(10)
                .background(theme.colors.card)
                .cornerRadius(10)
                .padding(.horizontal)
            }
            .buttonStyle(.plain)
            
            // 提示文本
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass.circle")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary.opacity(0.5))
                
                Text("点击搜索框开始搜索")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
            
            Spacer()
        }
        .background(theme.colors.surface)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

import SwiftUI

// MARK: - 主题选择页面

struct ThemeSettingsView: View {
    @Environment(AppSettings.self) private var appSettings
    @Environment(\.appTheme) private var currentTheme

    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(AppTheme.allCases) { theme in
                    ThemePreviewCard(
                        theme: theme,
                        currentTheme: currentTheme,
                        isSelected: appSettings.currentTheme == theme
                    ) {
                        withAnimation(.easeInOut(duration: 0.4)) {
                            appSettings.currentTheme = theme
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
            }
            .padding(16)
        }
        .background(currentTheme.colors.background.ignoresSafeArea())
        .navigationTitle("外观主题")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 主题预览卡片

private struct ThemePreviewCard: View {
    let theme: AppTheme
    let currentTheme: AppTheme
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 10) {
                // 色板预览区
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(theme.colors.background)
                        .frame(height: 80)
                        .overlay(
                            HStack(spacing: 6) {
                                // 卡片色
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(theme.colors.card)
                                    .frame(width: 28, height: 44)
                                // 强调色
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(theme.colors.accent)
                                    .frame(width: 20, height: 44)
                                // 主文字色
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(theme.colors.primaryText)
                                    .frame(width: 14, height: 44)
                            }
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    isSelected ? theme.colors.accent : theme.colors.border,
                                    lineWidth: isSelected ? 2.5 : 0.5
                                )
                        )

                    // 选中对勾徽章
                    if isSelected {
                        ZStack {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 22, height: 22)
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(theme.colors.accent)
                        }
                        .offset(x: -6, y: 6)
                    }
                }

                // 主题名 + 描述
                VStack(spacing: 3) {
                    HStack(spacing: 5) {
                        Image(systemName: theme.symbolName)
                            .font(.system(size: 12))
                            .foregroundColor(theme.colors.accent)
                        Text(theme.displayName)
                            .font(.subheadline)
                            .fontWeight(isSelected ? .semibold : .regular)
                            .foregroundColor(currentTheme.colors.primaryText)
                    }
                    Text(theme.description)
                        .font(.caption2)
                        .foregroundColor(currentTheme.colors.secondaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

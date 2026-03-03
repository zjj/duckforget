import SwiftUI

struct EncouragementWidget: View {
    let content: String
    let size: WidgetSize
    var onTap: (() -> Void)?
    @Environment(\.appTheme) private var theme
    
    var body: some View {
        Button {
            onTap?()
        } label: {
            ZStack(alignment: .center) {
                // Card background
                RoundedRectangle(cornerRadius: 16)
                    .fill(theme.colors.card)
                // Subtle Apple-style border
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)

                // Content with decorative quote marks
                VStack(spacing: 0) {
                    HStack(alignment: .top) {
                        Text("\u{201C}")
                            .font(.system(size: 52, weight: .bold, design: .serif))
                            .foregroundColor(theme.colors.accent.opacity(0.2))
                            .offset(x: -2, y: 10)
                        Spacer()
                    }

                    Text(content)
                        .font(.system(size: fontSize, weight: .medium, design: .serif))
                        .italic()
                        .lineSpacing(6)
                        .multilineTextAlignment(.center)
                        .foregroundColor(theme.colors.primaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)

                    HStack(alignment: .bottom) {
                        Spacer()
                        Text("\u{201D}")
                            .font(.system(size: 52, weight: .bold, design: .serif))
                            .foregroundColor(theme.colors.accent.opacity(0.2))
                            .offset(x: 2, y: -10)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .shadow(color: theme.colors.shadow, radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
    
    private var fontSize: CGFloat {
        switch size {
        case .small: return 13
        case .medium: return 16
        case .large: return 20
        case .fullPage: return 26
        }
    }
}

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
            if size == .small {
                smallBanner
            } else {
                quotedCard
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Small: single-line compact banner

    private var smallBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "heart.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.colors.accent.opacity(0.7))
            Text(content)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(theme.colors.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(theme.colors.card)
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
            }
        )
        .shadow(color: theme.colors.shadow, radius: 6, x: 0, y: 2)
    }

    // MARK: - Medium / Large / FullPage: decorative quote card

    private var quotedCard: some View {
        ZStack(alignment: .center) {
            RoundedRectangle(cornerRadius: 16)
                .fill(theme.colors.card)
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)

            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    Text("\u{201C}")
                        .font(.system(size: 52, weight: .bold, design: .serif))
                        .foregroundColor(theme.colors.accent.opacity(0.2))
                        .offset(x: -2, y: 10)
                    Spacer()
                }

                Text(content)
                    .font(.system(size: quoteFontSize, weight: .medium, design: .serif))
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

    private var quoteFontSize: CGFloat {
        switch size {
        case .small:    return 14  // unused — handled by smallBanner
        case .medium:   return 16
        case .large:    return 20
        case .fullPage: return 26
        }
    }
}

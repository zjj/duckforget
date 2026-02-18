import SwiftUI

struct EncouragementWidget: View {
    let content: String
    let size: WidgetSize
    var onTap: (() -> Void)?
    
    var body: some View {
        Button {
            onTap?()
        } label: {
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 3)
                
                // Content
                Text(content)
                    .font(.system(size: fontSize, weight: .medium, design: .serif))
                    .italic()
                    .lineSpacing(6)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.primary)
                    .padding(24)
            }
        }
        .buttonStyle(.plain)
    }
    
    private var fontSize: CGFloat {
        switch size {
        case .small: return 14
        case .medium: return 18
        case .large: return 24
        case .fullPage: return 32
        }
    }
}

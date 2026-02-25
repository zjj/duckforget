import SwiftUI

// Helper to wrap EditButton with custom appearance
struct EditButtonWrapper: View {
    @Environment(\.editMode) private var editMode
    @Environment(\.appTheme) private var theme

    var body: some View {
        Button {
            withAnimation {
                if editMode?.wrappedValue == .active {
                    editMode?.wrappedValue = .inactive
                } else {
                    editMode?.wrappedValue = .active
                }
            }
        } label: {
            if editMode?.wrappedValue == .active {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(theme.colors.accent)
            } else {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 20))
                    .foregroundColor(theme.colors.accent)
            }
        }
    }
}

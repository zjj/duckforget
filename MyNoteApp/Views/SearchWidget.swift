import SwiftUI
import SwiftData

struct SearchWidget: View {
    @Environment(NoteStore.self) var noteStore
    @Environment(\.modelContext) private var modelContext
    let size: WidgetSize
    @Binding var showSearch: Bool
    @Environment(\.appTheme) private var theme

    // small 模式搜索状态
    @State private var searchText = ""
    @State private var navigateToSearch = false
    @FocusState private var isFocused: Bool
    var onFocused: (() -> Void)? = nil
    var isEditing: Bool = false

    var body: some View {
        smallSearchBar
        .onChange(of: isFocused) { _, focused in
            if focused {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    onFocused?()
                }
            }
        }
    }

    // MARK: - Small: 嵌入搜索栏，确认后跳转

    private var smallSearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(theme.colors.secondaryText.opacity(0.6))

            TextField("搜索...", text: $searchText)
                .font(.system(size: 16))
                .foregroundColor(theme.colors.primaryText)
                .focused($isFocused)
                .submitLabel(.search)
                .onSubmit {
                    isFocused = false
                    navigateToSearch = true
                }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(theme.colors.secondaryText.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.colors.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(color: theme.colors.shadow, radius: 6, x: 0, y: 2)
        .navigationDestination(isPresented: $navigateToSearch) {
            NoteSearchPage(pageTitle: "搜索", initialSearchText: searchText)
                .environment(noteStore)
                .onDisappear { searchText = "" }
        }
    }

}


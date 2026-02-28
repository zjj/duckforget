import SwiftUI
import SwiftData

/// 某一天的笔记页面
/// 按 createdAt >= dayStart AND createdAt < dayEnd 过滤，行为同搜索页
struct DayNotesPage: View {
    let date: Date

    @Environment(NoteStore.self) var noteStore
    @Environment(\.appTheme) private var theme

    @State private var searchText = ""
    @State private var viewMode: ViewMode = .list
    @State private var sortMode: SortMode = .dateCreated
    @State private var isSearchFocused: Bool = false

    // MARK: - Computed

    private var dayStart: Date {
        Calendar.current.startOfDay(for: date)
    }

    private var dayEnd: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
    }

    private var pageTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: date)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // ── 搜索栏 ──────────────────────────────────────────────────
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)

                    SearchTextField(
                        placeholder: "搜索当日笔记...",
                        text: $searchText,
                        isFocused: $isSearchFocused
                    )

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(theme.colors.card)
                .cornerRadius(10)

                if isSearchFocused {
                    Button("取消") {
                        isSearchFocused = false
                    }
                    .font(.subheadline)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isSearchFocused)
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .background(theme.colors.surface)
            .shadow(color: Color.black.opacity(0.05), radius: 2, y: 1)

            // ── 笔记列表 ─────────────────────────────────────────────────
            NoteQueryContainer(
                filterMode: .createdDateRange(start: dayStart, end: dayEnd),
                searchText: searchText,
                viewMode: viewMode,
                sortMode: sortMode,
                pageSize: 100
            )
            .environment(noteStore)
            .scrollDismissesKeyboard(.interactively)
        }
        .onTapGesture {
            isSearchFocused = false
        }
        .navigationTitle(pageTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section("视图模式") {
                        Picker("视图", selection: $viewMode) {
                            ForEach(ViewMode.allCases, id: \.self) { mode in
                                Label(mode.rawValue, systemImage: mode.icon)
                                    .tag(mode)
                            }
                        }
                    }
                    Section("排序方式") {
                        Picker("排序", selection: $sortMode) {
                            ForEach(SortMode.allCases, id: \.self) { mode in
                                Label(mode.rawValue, systemImage: mode.icon)
                                    .tag(mode)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
    }
}

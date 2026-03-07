import SwiftUI
import SwiftData

/// 某个月的笔记页面
/// 按 createdAt >= monthStart AND createdAt < monthEnd 过滤
struct MonthNotesPage: View {
    let date: Date

    @Environment(NoteStore.self) var noteStore
    @Environment(\.appTheme) private var theme

    @State private var searchText = ""
    @State private var viewMode: ViewMode = .list
    @State private var sortMode: SortMode = .dateCreated
    @State private var isSearchFocused: Bool = false
    @State private var selectedTag: TagItem? = nil

    @Query(sort: \TagItem.sortOrder) private var allTags: [TagItem]

    // MARK: - Computed

    private var monthStart: Date {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: date)) ?? date
    }

    private var monthEnd: Date {
        Calendar.current.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
    }

    private var pageTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: date)
    }

    private var computedFilterMode: NoteFilterMode {
        if let tagName = selectedTag?.name {
            return .byTagAndDateRange(name: tagName, start: monthStart, end: monthEnd)
        }
        return .createdDateRange(start: monthStart, end: monthEnd)
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
                        placeholder: "搜索本月笔记...",
                        text: $searchText,
                        isFocused: $isSearchFocused
                    )

                    // 标签选择
                    if let tag = selectedTag {
                        // 已选中状态：显示标签名，点击清空
                        Button {
                            selectedTag = nil
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: "tag.fill")
                                    .font(.system(size: 10))
                                Text(tag.name)
                                    .font(.system(size: 10))
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(theme.colors.accentSoft)
                            .cornerRadius(6)
                            .foregroundColor(theme.colors.accent)
                            .overlay(alignment: .topTrailing) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.red)
                                    .offset(x: 4, y: -4)
                            }
                        }
                        .padding(.horizontal, 4)
                    } else {
                        // 未选中状态：显示标签图标，点击弹出选择
                        Menu {
                            ForEach(allTags) { tag in
                                Button {
                                    selectedTag = tag
                                } label: {
                                    Text(tag.name)
                                }
                            }
                        } label: {
                            Image(systemName: allTags.isEmpty ? "tag.slash" : "tag")
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 4)
                        }
                    }

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
                filterMode: computedFilterMode,
                searchText: searchText,
                viewMode: viewMode,
                sortMode: sortMode,
                filterTagName: selectedTag?.name,
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

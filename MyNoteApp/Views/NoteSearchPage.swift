import SwiftUI
import SwiftData

struct NoteSearchPage: View {
    @Environment(NoteStore.self) var noteStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    
    var pageTitle: String = "搜索" // 页面标题
    var filterRecentDays: Int? = nil // 筛选最近几天的记录（nil表示不筛选）
    var hideSearchBar: Bool = false // 是否隐藏搜索栏
    var isEmbedded: Bool = false // 是否嵌入在Dashboard中
    var onSearchTap: (() -> Void)? = nil // 点击搜索框的回调（用于跳转）
    var filterTagName: String? = nil     // 固定过滤的标签名（非 nil 时锁定为 .byTag 模式）
    var filterStartDate: Date? = nil     // 固定过滤的起始日期（与 filterRecentDays 互斥）
    var headerIcon: String? = nil        // 嵌入 header 左侧图标（如 "tag.fill"）
    var initialSearchText: String = ""   // 初始搜索文本（从嵌入搜索栏传入）
    
    @State private var searchText = ""
    @State private var viewMode: ViewMode = .list
    @State private var sortMode: SortMode = .dateModified
    @State private var selectedTag: TagItem? = nil // 新增：当前选中的标签
    @State private var isSearchFocused: Bool = false
    
    @Query(sort: \TagItem.sortOrder) private var allTags: [TagItem]

    // MARK: - Filter Mode Computation

    private var effectiveFilterStartDate: Date? {
        if let days = filterRecentDays {
            return Calendar.current.date(byAdding: .day, value: -days, to: Date())
        }
        return filterStartDate
    }

    private var effectiveFilterTagName: String? {
        filterTagName ?? selectedTag?.name
    }

    private var computedFilterMode: NoteFilterMode {
        switch (effectiveFilterTagName, effectiveFilterStartDate) {
        case (let name?, let start?):
            return .byTagAndDateRange(name: name, start: start, end: Date())
        case (let name?, nil):
            return .byTag(name: name)
        case (nil, let start?):
            return .dateRange(start: start, end: Date())
        case (nil, nil):
            return .all
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header for embedded mode
            if isEmbedded {
                HStack {
                    if let icon = headerIcon {
                        Image(systemName: icon)
                            .foregroundColor(theme.colors.accent)
                            .font(.largeTitle)
                    }
                    Text(pageTitle)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 8)
            }

            // Search Bar Area
            if !hideSearchBar {
                if let onSearchTap = onSearchTap {
                    // 嵌入模式下的伪搜索框（按钮）
                    Button(action: onSearchTap) {
                        HStack(spacing: 12) {
                            HStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(theme.colors.secondaryText)
                                
                                Text(filterTagName != nil ? "搜索 \(filterTagName!) 标签" : "输入进行搜索...")
                                    .foregroundColor(theme.colors.secondaryText)
                                Spacer()
                            }
                            .padding(10)
                            .background(theme.colors.card)
                            .cornerRadius(10)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(theme.colors.surface)
                        .shadow(color: Color.black.opacity(0.05), radius: 2, y: 1)
                    }
                    .buttonStyle(.plain)
                } else {
                    // 正常模式下的真搜索框
                    HStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(theme.colors.secondaryText)
                            
                            SearchTextField(
                                placeholder: filterTagName != nil ? "搜索 \(filterTagName!) 标签" : "输入进行搜索...",
                                text: $searchText,
                                isFocused: $isSearchFocused
                            )

                            // 标签选择（固定标签模式下不显示，标签已由 filterTagName 锁定）
                            if filterTagName == nil {
                                if let tag = selectedTag {
                                    // 已选中状态：显示带右上角红色小x的标签，直接点击清空
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
                                    // 未选中状态：只显示标签图标，点击选择
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
                                            .foregroundColor(theme.colors.secondaryText)
                                            .padding(.horizontal, 4)
                                    }
                                }
                            }
                            
                            if !searchText.isEmpty {
                                Button {
                                    searchText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(theme.colors.secondaryText)
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
                }
            }
            
            // Search Results
            NoteQueryContainer(
                filterMode: computedFilterMode,
                searchText: searchText,
                viewMode: viewMode,
                sortMode: sortMode,
                isEmbedded: false,
                onSearchTap: nil,
                filterTagName: effectiveFilterTagName,
                pageSize: 100
            )
            .environment(noteStore)
            .scrollDismissesKeyboard(.interactively)
        }
        .background(theme.colors.surface)
        .onTapGesture {
            isSearchFocused = false
        }
        .tint(theme.colors.accent)
        .if(!isEmbedded) { view in
            view
                .navigationTitle(pageTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(theme.colors.surface, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .displaySortOptionsToolbar(
                    viewMode: $viewMode,
                    sortMode: $sortMode
                )
        }
        .onAppear {
            // 如果有初始搜索文本，填入搜索框
            if !initialSearchText.isEmpty && searchText.isEmpty {
                searchText = initialSearchText
            }
            // 只在通用搜索页自动聚焦（固定标签/日期过滤页不需要键盘弹出）
            guard filterTagName == nil && filterRecentDays == nil && filterStartDate == nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isSearchFocused = true
            }
        }
    }
}

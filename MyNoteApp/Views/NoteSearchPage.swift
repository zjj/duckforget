import SwiftUI
import SwiftData

enum ViewMode: String, CaseIterable {
    case list = "列表"
    case grid = "网格"
    
    var icon: String {
        switch self {
        case .list: return "list.bullet"
        case .grid: return "square.grid.2x2"
        }
    }
}

enum SortMode: String, CaseIterable {
    case dateModified = "修改日期"
    case dateCreated = "创建日期"
    case title = "标题"
    
    var icon: String {
        switch self {
        case .dateModified: return "clock"
        case .dateCreated: return "calendar"
        case .title: return "textformat"
        }
    }
}

struct NoteSearchPage: View {
    @Environment(NoteStore.self) var noteStore
    @Environment(\.dismiss) private var dismiss
    
    var pageTitle: String = "搜索" // 页面标题
    var filterRecentDays: Int? = nil // 筛选最近几天的笔记（nil表示不筛选）
    var hideSearchBar: Bool = false // 是否隐藏搜索栏
    var isEmbedded: Bool = false // 是否嵌入在Dashboard中
    var onSearchTap: (() -> Void)? = nil // 点击搜索框的回调（用于跳转）
    
    @State private var searchText = ""
    @State private var viewMode: ViewMode = .list
    @State private var sortMode: SortMode = .dateModified
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header for embedded mode
            if isEmbedded {
                HStack {
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
                                    .foregroundColor(.secondary)
                                
                                Text("输入进行搜索...")
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(10)
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Color(.systemBackground))
                        .shadow(color: Color.black.opacity(0.05), radius: 2, y: 1)
                    }
                    .buttonStyle(.plain)
                } else {
                    // 正常模式下的真搜索框
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            HStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.secondary)
                                
                                TextField("输入进行搜索...", text: $searchText)
                                    .focused($isSearchFocused)
                                    .submitLabel(.search)
                            }
                            .padding(10)
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                            
                            if !searchText.isEmpty {
                                Button("取消") {
                                    searchText = ""
                                    isSearchFocused = false
                                }
                                .foregroundColor(.accentColor)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .padding(.bottom, 8)
                    }
                    .background(Color(.systemBackground))
                    .shadow(color: Color.black.opacity(0.05), radius: 2, y: 1)
                }
            }
            
            // Search Results
            NoteListView(
                showAllNotes: true, 
                initialSearchText: searchText, 
                hideSearchBar: true, 
                hideBottomBar: true, 
                hideNavigationTitle: true, 
                viewMode: viewMode, 
                sortMode: sortMode,
                filterRecentDays: filterRecentDays,
                customTitle: pageTitle
            )
                .environment(noteStore)
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
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            // Auto focus on open
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isSearchFocused = true
            }
        }
    }
}

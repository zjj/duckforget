import SwiftUI

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

private struct DisplaySortOptionsModifier: ViewModifier {
    @Binding var viewMode: ViewMode
    @Binding var sortMode: SortMode

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Section("视图") {
                            Picker(selection: $viewMode) {
                                ForEach(ViewMode.allCases, id: \.self) { mode in
                                    Label(mode.rawValue, systemImage: mode.icon)
                                        .tag(mode)
                                }
                            } label: {
                                EmptyView()
                            }
                        }

                        Section("排序") {
                            Picker(selection: $sortMode) {
                                ForEach(SortMode.allCases, id: \.self) { mode in
                                    Label(mode.rawValue, systemImage: mode.icon)
                                        .tag(mode)
                                }
                            } label: {
                                EmptyView()
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 20))
                    }
                    .buttonStyle(.plain)
                }
            }
    }
}

extension View {
    func displaySortOptionsToolbar(
        viewMode: Binding<ViewMode>,
        sortMode: Binding<SortMode>
    ) -> some View {
        modifier(
            DisplaySortOptionsModifier(
                viewMode: viewMode,
                sortMode: sortMode
            )
        )
    }
}
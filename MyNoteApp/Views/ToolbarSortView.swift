import SwiftUI

struct ToolbarSortView: View {
    @EnvironmentObject private var settings: ToolbarSettings
    
    var body: some View {
        List {
            Section(footer: Text("拖动行可以调整笔记编辑器底部工具栏的按钮顺序")) {
                ForEach(settings.items) { item in
                    HStack {
                        Image(systemName: item.icon)
                            .font(.title3)
                            .frame(width: 30)
                            .foregroundColor(.accentColor)
                        Text(item.title)
                            .font(.body)
                        Spacer()
                        Image(systemName: "line.3.horizontal")
                            .foregroundColor(.secondary)
                    }
                }
                .onMove(perform: settings.move)
            }
        }
        .navigationTitle("工具栏排序")
        .environment(\.editMode, .constant(.active)) // 始终处于编辑模式以允许拖拽
    }
}

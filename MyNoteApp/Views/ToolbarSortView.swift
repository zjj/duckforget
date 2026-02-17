import SwiftUI

struct ToolbarSortView: View {
    @EnvironmentObject private var settings: ToolbarSettings
    
    var body: some View {
        List {
            Section(footer: Text("拖动行可以调整记录编辑器底部工具栏的按钮顺序，使用开关控制按钮是否显示")) {
                ForEach($settings.configs) { $config in
                    HStack {
                        // 图标和标题
                        HStack(spacing: 12) {
                            Image(systemName: config.type.icon)
                                .font(.title3)
                                .frame(width: 24)
                                .foregroundColor(config.isEnabled ? .accentColor : .secondary)
                            
                            Text(config.type.title)
                                .font(.body)
                                .foregroundColor(config.isEnabled ? .primary : .secondary)
                        }
                        
                        Spacer()
                        
                        // 开关控制显示/隐藏
                        Toggle("", isOn: $config.isEnabled)
                            .labelsHidden()
                            .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                        
                        // EditMode automatically provides the drag handle here (on the far right)
                    }
                }
                .onMove(perform: settings.move)
            }
        }
        .navigationTitle("工具栏")
        .environment(\.editMode, .constant(.active)) // 始终处于编辑模式以允许拖拽
    }
}

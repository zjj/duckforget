import SwiftUI

struct ToolbarSortView: View {
    @EnvironmentObject private var settings: ToolbarSettings

    var body: some View {
        List {
            Section(footer: Text("拖动行可以调整记录编辑器底部工具栏的按钮顺序，使用开关控制按钮是否显示")) {
                ForEach(
                    settings.configs.indices.filter { settings.configs[$0].type != .markdown },
                    id: \.self
                ) { index in
                    HStack {
                        HStack(spacing: 12) {
                            Image(systemName: settings.configs[index].type.icon)
                                .font(.title3)
                                .frame(width: 24)
                                .foregroundColor(settings.configs[index].isEnabled ? .accentColor : .secondary)

                            Text(settings.configs[index].type.title)
                                .font(.body)
                                .foregroundColor(settings.configs[index].isEnabled ? .primary : .secondary)
                        }

                        Spacer()

                        Toggle("", isOn: $settings.configs[index].isEnabled)
                            .labelsHidden()
                            .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                    }
                }
                .onMove(perform: settings.moveNonMarkdown)
            }

            if let markdownIndex = settings.configs.firstIndex(where: { $0.type == .markdown }) {
                Section(
                    header: Text("Markdown 格式工具栏"),
                    footer: Text("控制是否在编辑器底部显示 Markdown 格式工具栏")
                ) {
                    HStack {
                        HStack(spacing: 12) {
                            Image(systemName: settings.configs[markdownIndex].type.icon)
                                .font(.title3)
                                .frame(width: 24)
                                .foregroundColor(settings.configs[markdownIndex].isEnabled ? .accentColor : .secondary)

                            Text(settings.configs[markdownIndex].type.title)
                                .font(.body)
                                .foregroundColor(settings.configs[markdownIndex].isEnabled ? .primary : .secondary)
                        }

                        Spacer()

                        Toggle("", isOn: $settings.configs[markdownIndex].isEnabled)
                            .labelsHidden()
                            .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                    }
                }
            }
        }
        .navigationTitle("工具栏")
        .environment(\.editMode, .constant(.active))
    }
}

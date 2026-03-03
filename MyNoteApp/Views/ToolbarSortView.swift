import SwiftUI

struct ToolbarSortView: View {
    @Environment(ToolbarSettings.self) private var settings
    @Environment(\.appTheme) private var theme

    var body: some View {
        @Bindable var settings = settings
        List {
            Section(
                header: Text("辅助功能"),
                footer: Text("开启后工具栏图标将变大，更适合手指较粗的用户使用")
            ) {
                HStack {
                    HStack(spacing: 12) {
                        Image(systemName: "hand.point.up.left")
                            .font(.title3)
                            .frame(width: 24)
                            .foregroundColor(settings.isLargeToolbarIcons ? theme.colors.accent : .secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("粗大手指")
                                .font(.body)
                            Text("增大工具栏图标尺寸")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    Toggle("", isOn: $settings.isLargeToolbarIcons)
                        .labelsHidden()
                        .toggleStyle(SwitchToggleStyle(tint: theme.colors.accent))
                }
            }

            Section(footer: Text("拖动行可以调整记录编辑器底部工具栏的按钮顺序，使用开关控制按钮是否显示")) {
                ForEach(settings.configs.filter { $0.type != .markdown }) { config in
                    HStack {
                        HStack(spacing: 12) {
                            Image(systemName: config.type.icon)
                                .font(.title3)
                                .frame(width: 24)
                                .foregroundColor(config.isEnabled ? theme.colors.accent : .secondary)

                            Text(config.type.title)
                                .font(.body)
                                .foregroundColor(config.isEnabled ? .primary : .secondary)
                        }

                        Spacer()

                        Toggle("", isOn: Binding(
                            get: { config.isEnabled },
                            set: { newVal in
                                if let i = settings.configs.firstIndex(where: { $0.id == config.id }) {
                                    settings.configs[i].isEnabled = newVal
                                }
                            }
                        ))
                        .labelsHidden()
                        .toggleStyle(SwitchToggleStyle(tint: theme.colors.accent))
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
                                .foregroundColor(settings.configs[markdownIndex].isEnabled ? theme.colors.accent : .secondary)

                            Text(settings.configs[markdownIndex].type.title)
                                .font(.body)
                                .foregroundColor(settings.configs[markdownIndex].isEnabled ? .primary : .secondary)
                        }

                        Spacer()

                        Toggle("", isOn: $settings.configs[markdownIndex].isEnabled)
                            .labelsHidden()
                            .toggleStyle(SwitchToggleStyle(tint: theme.colors.accent))
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.colors.background.ignoresSafeArea())
        .navigationTitle("工具栏")
        .environment(\.editMode, .constant(.active))
    }
}

import SwiftUI

// MARK: - 工具栏

extension NoteView {

    // MARK: 展开的格式工具栏（2行图标布局）
    
    var expandedFormatToolbar: some View {
        let isLarge = toolbarSettings.isLargeToolbarIcons
        let iconSize: CGFloat = isLarge ? 21 : 16
        let labelSize: CGFloat = isLarge ? 17 : 14
        let rowMinHeight: CGFloat = isLarge ? 48 : 36
        let dividerHeight: CGFloat = isLarge ? 32 : 24

        let allFormats = FormatMenuSheet.FormatAction.allCases.filter { $0 != .image }
        let halfCount = (allFormats.count + 1) / 2
        let row1 = Array(allFormats.prefix(halfCount))
        let row2 = Array(allFormats.dropFirst(halfCount))

        return VStack(spacing: 0) {
            // 第一行
            HStack(spacing: 0) {
                ForEach(row1) { action in
                    Button {
                        applyFormatAction(action)
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            updateCurrentLineTodoStatus()
                        }
                    } label: {
                        Group {
                            if let label = action.customLabel {
                                Text(label)
                                    .font(.system(size: labelSize, weight: .bold, design: .monospaced))
                            } else {
                                Image(systemName: action.icon)
                                    .font(.system(size: iconSize))
                            }
                        }
                        .foregroundColor(action.color)
                        .frame(maxWidth: .infinity, minHeight: rowMinHeight)
                    }
                    .accessibilityLabel(action.title)

                    if action != row1.last {
                        Divider()
                            .frame(height: dividerHeight)
                    }
                }
            }

            Divider()

            // 第二行
            HStack(spacing: 0) {
                ForEach(row2) { action in
                    Button {
                        applyFormatAction(action)
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            updateCurrentLineTodoStatus()
                        }
                    } label: {
                        Group {
                            if let label = action.customLabel {
                                Text(label)
                                    .font(.system(size: labelSize, weight: .bold, design: .monospaced))
                            } else {
                                Image(systemName: action.icon)
                                    .font(.system(size: iconSize))
                            }
                        }
                        .foregroundColor(action.color)
                        .frame(maxWidth: .infinity, minHeight: rowMinHeight)
                    }
                    .accessibilityLabel(action.title)

                    // 待办切换按钮：插入在 checkbox 图标之后、分割线图标之前
                    if action == .checkbox {
                        Divider()
                            .frame(height: dividerHeight)
                        
                        Button {
                            toggleTodoCheckbox()
                        } label: {
                            Text((currentLineIsTodo && currentLineIsTodoCouldBeChecked) ? "[x]" : "[ ]")
                                .font(.system(size: labelSize, weight: .medium, design: .monospaced))
                                .foregroundColor(currentLineIsTodo ? .teal : .gray)
                                .frame(maxWidth: .infinity, minHeight: rowMinHeight)
                                .opacity(todoToggleButtonPressed ? 0.3 : 1.0)
                                .scaleEffect(todoToggleButtonPressed ? 1.2 : 1.0)
                        }
                        .disabled(!currentLineIsTodo)
                        .animation(.easeInOut(duration: 0.15), value: todoToggleButtonPressed)
                    }

                    if action != row2.last {
                        Divider()
                            .frame(height: dividerHeight)
                    }
                }
            }
        }
        .background(theme.colors.card)
    }

    // MARK: 底部工具栏

    /// 是否在设置中启用了 Markdown 工具栏
    var isMarkdownToolbarEnabled: Bool {
        toolbarSettings.configs.first(where: { $0.type == .markdown })?.isEnabled ?? true
    }

    var bottomToolbar: some View {
        let isLarge = toolbarSettings.isLargeToolbarIcons
        let toolbarHeight: CGFloat = isLarge ? 56 : 44
        let iconSize: CGFloat = isLarge ? 24 : 18
        let fixedButtonWidth: CGFloat = isLarge ? 52 : 40
        let fixedButtonFrameHeight: CGFloat = isLarge ? 48 : 36
        let dividerHeight: CGFloat = isLarge ? 32 : 24
        let markdownFontSize: CGFloat = isLarge ? 11 : 9

        return HStack(spacing: 0) {
            // 左侧固定：Markdown 格式按钮（展开/收起格式栏），仅在 Markdown 启用时显示
            if isMarkdownToolbarEnabled {
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        showExpandedFormatBar.toggle()
                    }
                } label: {
                    Group {
                        if showExpandedFormatBar {
                            Image(systemName: "chevron.down")
                                .font(.system(size: iconSize))
                        } else {
                            VStack(spacing: 1) {
                                Text("MARK")
                                    .font(.system(size: markdownFontSize, weight: .semibold, design: .monospaced))
                                Text("DOWN")
                                    .font(.system(size: markdownFontSize, weight: .semibold, design: .monospaced))
                            }
                        }
                    }
                    .foregroundColor(theme.colors.accent)
                    .frame(width: fixedButtonWidth, height: fixedButtonFrameHeight)
                }
                .accessibilityLabel(showExpandedFormatBar ? "收起格式工具栏" : "展开格式工具栏")

                Divider()
                    .frame(height: dividerHeight)
                    .padding(.horizontal, 4)
            }
            
            // 中间可滚动工具栏
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: isLarge ? 12 : 8) {
                    ForEach(toolbarSettings.activeItems.filter { $0 != .markdown }) { item in
                        toolButton(for: item)
                    }
                }
                .padding(.horizontal, 8)
            }
            
            Divider()
                .frame(height: dividerHeight)
                .padding(.horizontal, 4)
            
            // 右侧固定：键盘收起按钮
            Button {
                markdownCoordinator?.blur()
            } label: {
                Image(systemName: "keyboard.chevron.compact.down")
                    .font(.system(size: iconSize))
                    .foregroundColor(theme.colors.accent)
                    .frame(width: fixedButtonWidth, height: fixedButtonFrameHeight)
            }
            .accessibilityLabel("收起键盘")
        }
        .frame(height: toolbarHeight)
        .background(theme.colors.surface)
    }
    
    func toolButton(for item: ToolbarItemType) -> some View {
        ToolbarButton(
            icon: item.icon,
            label: item.title
        ) {
            switch item {
            case .camera: showCamera = true
            case .photo: showPhotoPicker = true
            case .audio: showAudioRecorder = true
            case .folder: showFilePicker = true
            case .location: showLocationPicker = true
            case .drawing: showPaintingCanvas = true
            case .scanText:
                activeScanMode = .textExtraction
            case .scanDocument:
                activeScanMode = .documentScan
            case .markdown:
                // 触发 Markdown 上下文菜单
                let lineText = markdownCoordinator?.getCurrentLineText() ?? ""
                floatingMenuHasSelection = markdownCoordinator?.selectedText != nil
                floatingMenuIsTodoLine = lineText.hasPrefix("- [ ] ") || lineText.hasPrefix("- [x] ") || lineText.hasPrefix("- [X] ")
                floatingMenuIsTodoChecked = lineText.hasPrefix("- [x] ") || lineText.hasPrefix("- [X] ")
                
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    showFloatingMenu = true
                }
            }
        }
    }
    
    // MARK: 工具栏按钮组件
    
    struct ToolbarButton: View {
        let icon: String
        var label: String = ""
        let action: () -> Void
        @Environment(\.appTheme) private var theme
        @Environment(ToolbarSettings.self) private var toolbarSettings

        private var iconSize: CGFloat { toolbarSettings.isLargeToolbarIcons ? 24 : 18 }
        private var frameSize: CGFloat { toolbarSettings.isLargeToolbarIcons ? 48 : 36 }
        
        var body: some View {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: iconSize))
                    .foregroundColor(theme.colors.accent)
                    .frame(width: frameSize, height: frameSize)
            }
            .accessibilityLabel(label)
        }
    }
}

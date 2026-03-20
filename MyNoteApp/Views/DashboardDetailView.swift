import SwiftUI
import SwiftData

struct DashboardDetailView: View {
    @Environment(NoteStore.self) var noteStore
    @Environment(\.appTheme) private var theme
    @Bindable var dashboardConfig: DashboardConfig
    let pageId: UUID
    @Binding var isEditing: Bool
    var availableHeight: CGFloat = 0
    
    @State private var showingAddTagWidget = false
    @State private var showingAddEncouragementWidget = false
    @State private var showingWidgetLibrary = false
    @State private var pendingWidgetType: WidgetType?
    @State private var newEncouragementText = DashboardItem.defaultEncouragement
    @State private var isPressingInlineInputMic = false
    @State private var isPressingInlineInputRecording = false
    @AppStorage("hasSeenDashboardEditHint") private var hasSeenEditHint = false
    
    var page: DashboardPage? {
        dashboardConfig.pages.first(where: { $0.id == pageId })
    }

    private var orderedWidgetTypes: [WidgetType] {
        [
            .inlineInput,
            .encouragement,
            .tag,
            .recentNotes,
            .search,
            .trash,
            .calendar,
            .timeline,
            .location
        ]
    }
    
    var body: some View {
        if let page = page {
            widgetListView(page: page)
        } else {
            ContentUnavailableView("页面不存在", systemImage: "questionmark.folder")
        }
    }
    
    @ViewBuilder
    private func widgetListView(page: DashboardPage) -> some View {
        ScrollViewReader { proxy in
        List {
            // 新手引导条：有内容、未进编辑、从未看过时显示
            if !page.items.isEmpty && !isEditing && !hasSeenEditHint {
                HStack(spacing: 12) {
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("这是你的记忆中枢")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(theme.colors.primaryText)
                        Text("长按页面可自定义布局，或点击右上角 ··· 编辑")
                            .font(.system(size: 12))
                            .foregroundColor(theme.colors.secondaryText)
                    }
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            hasSeenEditHint = true
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(theme.colors.secondaryText.opacity(0.5))
                            .frame(width: 28, height: 28)
                            .background(theme.colors.secondaryText.opacity(0.07), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 8)
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(theme.colors.accent.opacity(0.07))
                        .padding(.vertical, 2)
                )
                .listRowSeparator(.hidden)
            }
            ForEach(page.items) { item in
                DashboardRow(
                    item: item,
                    isEditing: isEditing,
                    dashboardConfig: dashboardConfig,
                    pageId: pageId,
                    availableHeight: availableHeight,
                    onInlineInputVoicePressChanged: { pressing in
                        isPressingInlineInputMic = pressing
                    },
                    onInlineInputRecordingPressChanged: { pressing in
                        isPressingInlineInputRecording = pressing
                    },
                    onFullPageFocused: (item.size == .fullPage || item.type == .inlineInput) ? {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            let anchor: UnitPoint = item.type == .inlineInput ? .bottom : .top
                            proxy.scrollTo(item.id, anchor: anchor)
                        }
                    } : nil
                )
                .id(item.id)
                .onDrag {
                    return NSItemProvider(object: item.id.uuidString as NSString)
                }
            }
            .onMove { source, destination in
                dashboardConfig.moveItem(in: pageId, from: source, to: destination)
            }
            
            // Empty state guidance
            if page.items.isEmpty {
                let emptyStateContent = VStack(spacing: 16) {
                    Image(systemName: isEditing ? "plus.square.dashed" : "tray.and.arrow.down")
                        .font(.system(size: 60))
                        .foregroundColor(isEditing ? theme.colors.accent.opacity(0.6) : theme.colors.secondaryText.opacity(0.5))
                    
                    Text(isEditing ? "点击下方「添加组件」开始" : "随手记，之后能回看和整理")
                        .font(.headline)
                        .foregroundColor(isEditing ? theme.colors.accent : theme.colors.secondaryText)

                    if !isEditing {
                        VStack(spacing: 6) {
                            Text("点这里或长按页面进入编辑，自定义你的记忆中枢")
                                .font(.subheadline)
                                .foregroundColor(theme.colors.accent.opacity(0.9))
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)

                if isEditing {
                    Button {
                        showingWidgetLibrary = true
                    } label: {
                        emptyStateContent
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                } else {
                    emptyStateContent
                        .onTapGesture {
                            withAnimation {
                                isEditing = true
                            }
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: isEditing) { _, editing in
            if editing { hasSeenEditHint = true }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.6).onEnded { _ in
                guard !isEditing, !isPressingInlineInputMic, !isPressingInlineInputRecording else { return }
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isEditing = true
                }
            }
        )
        .overlay(alignment: .bottom) {
            if isEditing {
                Button {
                    showingWidgetLibrary = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                        Text("添加组件")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 13)
                    .background(theme.colors.accent, in: Capsule())
                    .shadow(color: theme.colors.accent.opacity(0.35), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $showingWidgetLibrary, onDismiss: handlePendingWidgetSelection) {
            AddWidgetLibrarySheet(widgetTypes: orderedWidgetTypes) { type in
                pendingWidgetType = type
            }
        }
        .sheet(isPresented: $showingAddTagWidget) {
            AddTagWidgetSheet { tagName in
                addTagWidget(tagName: tagName)
            }
            .environment(noteStore)
        }
        .sheet(isPresented: $showingAddEncouragementWidget) {
            AddEncouragementWidgetSheet(initialText: newEncouragementText) { content in
                let finalContent = content.isEmpty ? DashboardItem.defaultEncouragement : String(content.prefix(200))
                newEncouragementText = finalContent
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    dashboardConfig.addItem(to: pageId, type: .encouragement, content: finalContent)
                }
            }
        }
        } // ScrollViewReader
    }
    
    private func addTagWidget(tagName: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            dashboardConfig.addItem(to: pageId, type: .tag, tagName: tagName)
        }
    }

    private func handlePendingWidgetSelection() {
        guard let type = pendingWidgetType else { return }
        pendingWidgetType = nil

        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        if type == .tag {
            showingAddTagWidget = true
        } else if type == .encouragement {
            newEncouragementText = DashboardItem.defaultEncouragement
            showingAddEncouragementWidget = true
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                dashboardConfig.addItem(to: pageId, type: type)
            }
        }
    }
}

private struct AddWidgetLibrarySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme

    let widgetTypes: [WidgetType]
    let onSelect: (WidgetType) -> Void

    private var recommendedTypes: [WidgetType] {
        widgetTypes.filter(\.isRecommendedForStart)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    introCard

                    if !recommendedTypes.isEmpty {
                        sectionHeader(title: "推荐起步", subtitle: "先放 1 到 2 个常用组件，页面会更容易成型")

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(recommendedTypes, id: \.self) { type in
                                recommendedCard(for: type)
                            }
                        }
                    }

                    sectionHeader(title: "全部组件", subtitle: "按用途挑选，而不是按功能名死记")

                    VStack(spacing: 12) {
                        ForEach(widgetTypes, id: \.self) { type in
                            widgetRow(for: type)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
            .background(theme.colors.background.ignoresSafeArea())
            .navigationTitle("添加组件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("先想你希望这个页面帮你做什么")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(theme.colors.primaryText)
            Text("例如立即记录、快速回看、按地点回忆。选中后会直接添加，少数组件会再让你补一步配置。")
                .font(.system(size: 13))
                .foregroundStyle(theme.colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(theme.colors.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(theme.colors.border.opacity(0.45), lineWidth: 1)
                )
        )
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.colors.primaryText)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(theme.colors.secondaryText)
        }
    }

    private func recommendedCard(for type: WidgetType) -> some View {
        Button {
            onSelect(type)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(theme.colors.accentSoft)
                        .frame(width: 42, height: 42)
                    Image(systemName: type.iconName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(theme.colors.accent)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(type.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.colors.primaryText)
                    Text(type.libraryDescription)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }

                HStack(spacing: 8) {
                    pill(text: type.sizeSummary, highlighted: false)
                    if type.requiresSetup {
                        pill(text: "需配置", highlighted: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 156, alignment: .topLeading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(theme.colors.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(theme.colors.border.opacity(0.35), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func widgetRow(for type: WidgetType) -> some View {
        Button {
            onSelect(type)
            dismiss()
        } label: {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(theme.colors.accentSoft)
                        .frame(width: 42, height: 42)
                    Image(systemName: type.iconName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(theme.colors.accent)
                }

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        Text(type.displayName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(theme.colors.primaryText)
                        if type.isRecommendedForStart {
                            pill(text: "推荐", highlighted: true)
                        }
                    }

                    Text(type.libraryDescription)
                        .font(.system(size: 12.5))
                        .foregroundStyle(theme.colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        pill(text: type.sizeSummary, highlighted: false)
                        if type.requiresSetup {
                            pill(text: "需配置", highlighted: false)
                        }
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(theme.colors.accent)
                    .padding(.top, 2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(theme.colors.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(theme.colors.border.opacity(0.35), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func pill(text: String, highlighted: Bool) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(highlighted ? theme.colors.accent : theme.colors.secondaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(highlighted ? theme.colors.accentSoft : theme.colors.surface)
            )
    }
}

private struct AddEncouragementWidgetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme

    @State private var text: String

    let onConfirm: (String) -> Void

    init(initialText: String, onConfirm: @escaping (String) -> Void) {
        _text = State(initialValue: initialText)
        self.onConfirm = onConfirm
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var previewText: String {
        trimmedText.isEmpty ? DashboardItem.defaultEncouragement : trimmedText
    }

    private var remainingCount: Int {
        max(0, 200 - text.count)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("给这个页面放一句会反复看到的话")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(theme.colors.primaryText)
                            Text("适合一句提醒、鼓励，或者你希望自己别忘掉的短句。")
                                .font(.system(size: 13))
                                .foregroundStyle(theme.colors.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("内容")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(theme.colors.primaryText)

                            ZStack(alignment: .topLeading) {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(theme.colors.card)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .stroke(theme.colors.border.opacity(0.4), lineWidth: 1)
                                    )

                                TextEditor(text: $text)
                                    .font(.system(size: 16))
                                    .foregroundStyle(theme.colors.primaryText)
                                    .scrollContentBackground(.hidden)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .frame(minHeight: 130)
                                    .onChange(of: text) { _, newValue in
                                        if newValue.count > 200 {
                                            text = String(newValue.prefix(200))
                                        }
                                    }

                                if text.isEmpty {
                                    Text("比如：先记下来，之后再慢慢整理。")
                                        .font(.system(size: 16))
                                        .foregroundStyle(theme.colors.secondaryText.opacity(0.5))
                                        .padding(.horizontal, 18)
                                        .padding(.vertical, 18)
                                        .allowsHitTesting(false)
                                }
                            }

                            HStack {
                                Text("最多 200 字")
                                    .font(.system(size: 12))
                                    .foregroundStyle(theme.colors.secondaryText)
                                Spacer()
                                Text("还可输入 \(remainingCount) 字")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(theme.colors.secondaryText)
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("预览")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(theme.colors.primaryText)

                            EncouragementWidget(content: previewText, size: .medium)
                                .allowsHitTesting(false)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 24)
                }

                VStack(spacing: 10) {
                    Button {
                        onConfirm(trimmedText)
                        dismiss()
                    } label: {
                        Text("添加到页面")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(theme.colors.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button("使用默认文案") {
                        text = DashboardItem.defaultEncouragement
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.colors.accent)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 16)
                .background(theme.colors.background)
            }
            .background(theme.colors.background.ignoresSafeArea())
            .navigationTitle("配置鼓励组件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private extension WidgetType {
    var libraryDescription: String {
        switch self {
        case .inlineInput:
            return "马上写下一条想法，不打断当前浏览。"
        case .encouragement:
            return "放一句短句，打开页面时先给自己一点推动。"
        case .tag:
            return "固定看某个标签下的内容，适合做专题页。"
        case .recentNotes:
            return "优先回看最近新增或刚修改过的记录。"
        case .search:
            return "随时查找关键词，快速跳回需要的内容。"
        case .trash:
            return "集中查看最近删除的内容，避免误删后找不到。"
        case .calendar:
            return "按日期回顾记录，适合建立时间感。"
        case .timeline:
            return "把记录展开成连续时间线，适合纵向浏览。"
        case .location:
            return "按地点回看笔记，适合旅行、散步或采风记录。"
        case .statistics:
            return "从数量和趋势上看自己的记录节奏。"
        }
    }

    var sizeSummary: String {
        if supportedSizes.isEmpty {
            return "固定尺寸"
        }
        return supportedSizes.map(\.displayName).joined(separator: " / ")
    }

    var requiresSetup: Bool {
        self == .tag || self == .encouragement
    }

    var isRecommendedForStart: Bool {
        switch self {
        case .inlineInput, .recentNotes, .calendar:
            return true
        default:
            return false
        }
    }
}

struct DashboardRow: View {
    @Environment(NoteStore.self) var noteStore
    @Environment(\.appTheme) private var theme
    private let rowVerticalInset: CGFloat = 5
    private let rowHorizontalInset: CGFloat = 11
    let item: DashboardItem
    let isEditing: Bool
    @Bindable var dashboardConfig: DashboardConfig
    let pageId: UUID
    var availableHeight: CGFloat = 0
    var onInlineInputVoicePressChanged: ((Bool) -> Void)? = nil
    var onInlineInputRecordingPressChanged: ((Bool) -> Void)? = nil
    var onFullPageFocused: (() -> Void)? = nil
    
    @State private var showSearchDetail = false
    @State private var showTagDetail = false
    @State private var showRecentNotesDetail = false
    @State private var showDeleteConfirmation = false
    @State private var showEncouragementEdit = false
    @State private var encouragementTextTemp = ""
    
    /// Full page height: use available height from container, minus some padding for list insets
    private var fullPageHeight: CGFloat {
        availableHeight > 0 ? availableHeight - (rowVerticalInset * 2 + 12) : 600
    }
    
    @ViewBuilder
    private var widgetContent: some View {
        switch item.type {
        case .search:
            SearchWidget(size: item.size, showSearch: $showSearchDetail, onFocused: onFullPageFocused, isEditing: isEditing)
        case .tag:
            if let tagName = item.tagName {
                TagWidget(tagName: tagName, size: item.size, isEditing: isEditing, showTagDetail: $showTagDetail)
            } else {
                Text("标签未设置").foregroundColor(.secondary)
            }
        case .recentNotes:
            RecentNotesWidget(size: item.size, isEditing: isEditing, showRecentNotes: $showRecentNotesDetail)
        //case .newNote:
        //    newNoteCard(size: item.size)
        case .trash:
            TrashWidget(size: item.size)
        case .statistics:
            StatisticsWidget(size: item.size)
        case .encouragement:
            EncouragementWidget(content: item.content ?? DashboardItem.defaultEncouragement, size: item.size)
        case .calendar:
            CalendarWidget(size: item.size, isEditing: isEditing)
        case .inlineInput:
            InlineInputWidget(
                size: item.size,
                onFocused: onFullPageFocused,
                onVoicePressChanged: onInlineInputVoicePressChanged,
                onRecordingPressChanged: onInlineInputRecordingPressChanged
            )
        case .timeline:
            TimelineWidget(isEditing: isEditing)
        case .location:
            LocationWidget(size: item.size, isEditing: isEditing)
        }
    }

    var body: some View {
        widgetContent
        .frame(minHeight: item.size == .fullPage ? fullPageHeight : nil)
        .allowsHitTesting(!isEditing)
        // 编辑模式下淡蓝轮廓提示可操作
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: isEditing ? 1.5 : 0, dash: isEditing ? [6, 3] : [])
                )
                .foregroundColor(theme.colors.accent.opacity(isEditing ? 0.45 : 0))
                .animation(.easeInOut(duration: 0.2), value: isEditing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        // 长按弹出上下文菜单（编辑模式下）
        .contextMenu(isEditing ? ContextMenu {
            // 调整大小
            if item.type.supportedSizes.count > 1 {
                Menu {
                    Picker("调整大小", selection: Binding(
                        get: { item.size },
                        set: { updateSize($0) }
                    )) {
                        ForEach(item.type.supportedSizes, id: \.self) { size in
                            Label(size.label, systemImage: size.iconName)
                                .tag(size)
                        }
                    }
                } label: {
                    Label("调整大小", systemImage: "arrow.up.left.and.arrow.down.right")
                }
            }
            
            // 编辑内容（仅鼓励组件）
            if item.type == .encouragement {
                Button {
                    encouragementTextTemp = item.content ?? ""
                    showEncouragementEdit = true
                } label: {
                    Label("编辑内容", systemImage: "pencil")
                }
            }
            
            // 删除
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("删除", systemImage: "trash")
            }
        } : nil)
        .navigationDestination(isPresented: $showSearchDetail) {
            NoteSearchPage(pageTitle: "搜索")
        }
        .navigationDestination(isPresented: $showTagDetail) {
            if let tagName = item.tagName {
                NoteSearchPage(pageTitle: tagName, filterTagName: tagName, headerIcon: "tag.fill")
                    .environment(noteStore)
            }
        }
        .navigationDestination(isPresented: $showRecentNotesDetail) {
            NoteSearchPage(
                pageTitle: "最近记录",
                filterRecentDays: 2,
                hideSearchBar: false
            )
            .environment(noteStore)
        }
        .alert("修改鼓励语", isPresented: $showEncouragementEdit) {
            TextField("请输入鼓励的话", text: $encouragementTextTemp)
            Button("取消", role: .cancel) { }
            Button("确定") {
                let finalContent = String(encouragementTextTemp.prefix(200))
                dashboardConfig.updateContent(in: pageId, for: item.id, content: finalContent)
            }
        } message: {
            Text("最多200字")
        }
        .alert("确认删除", isPresented: $showDeleteConfirmation) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.warning)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    dashboardConfig.removeItem(from: pageId, itemId: item.id)
                }
            }
        } message: {
            Text("确定要删除这个组件吗？")
        }
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: rowVerticalInset, leading: rowHorizontalInset, bottom: rowVerticalInset, trailing: rowHorizontalInset))
        .listRowBackground(Color.clear)
    }
    
    private func updateSize(_ size: WidgetSize) {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            dashboardConfig.updateSize(in: pageId, for: item.id, size: size)
        }
    }

    private func cycleSize() {
        let supported = item.type.supportedSizes
        guard supported.count > 1,
              let currentIndex = supported.firstIndex(of: item.size) else { return }
        let nextIndex = (currentIndex + 1) % supported.count
        updateSize(supported[nextIndex])
    }
    
    // MARK: - 新建记录卡片
    
    @ViewBuilder
    private func newNoteCard(size: WidgetSize) -> some View {
        // 根据尺寸动态计算图标大小
        let iconSize: CGFloat = {
            switch size {
            case .small: return 36
            case .medium: return 48
            case .large, .fullPage: return 64
            }
        }()
        
        if isEditing {
            // 编辑模式：所有尺寸统一显示占位卡片
            let verticalPadding: CGFloat = {
                switch size {
                case .small: return 20
                case .medium: return 40
                case .large: return 80
                case .fullPage: return 80
                }
            }()
            VStack(spacing: 8) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: iconSize))
                    .foregroundStyle(theme.colors.accent)
                    .symbolRenderingMode(.hierarchical)
                if size == .fullPage {
                    Text("全屏模式：直接显示编辑器")
                        .font(.caption)
                        .foregroundColor(theme.colors.secondaryText.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, verticalPadding)
            .background(theme.colors.card)
            .cornerRadius(16)
        } else if size == .fullPage {
            // 全屏非编辑：直接内嵌编辑器，可立刻输入
            InlineNewNoteWidget(onFocused: onFullPageFocused)
        } else {
            // 非全屏非编辑：卡片，点击 push 到独立编辑页
            let verticalPadding: CGFloat = {
                switch size {
                case .small: return 20
                case .medium: return 40
                case .large: return 80
                case .fullPage: return 80
                }
            }()
            NewNoteButton(verticalPadding: verticalPadding, iconSize: iconSize)
        }
    }
}

// MARK: - 全屏内嵌新建记录编辑器

/// 全屏模式下直接嵌入 dashboard 的编辑器
/// 保持 isEmbedded=true 让 dashboard 的 "..." 工具栏可见
/// 发布后自动重置为新记录
struct InlineNewNoteWidget: View {
    @Environment(NoteStore.self) var noteStore
    @Environment(\.appTheme) private var theme
    @State private var showEditor = false
    var onFocused: (() -> Void)? = nil
    
    var body: some View {
        // 修改为点击触发式：显示一个看起来像编辑器的占位视图
        // 点击后弹出全屏编辑器，从未彻底解决生命周期竞态问题
        VStack(spacing: 0) {
            // 模拟顶部工具栏区域
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(theme.colors.accent.opacity(0.12))
                        .frame(width: 34, height: 34)
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.colors.accent)
                        .symbolRenderingMode(.hierarchical)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("新建记录")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(theme.colors.primaryText)
                    Text("点击开始输入")
                        .font(.caption)
                        .foregroundColor(theme.colors.secondaryText.opacity(0.6))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(theme.colors.secondaryText.opacity(0.35))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(theme.colors.surface)
            
            Divider()
            
            // 模拟内容区域
            ZStack(alignment: .topLeading) {
                theme.colors.surface

                Text("今天有什么想法...")
                    .foregroundColor(theme.colors.secondaryText.opacity(0.4))
                    .font(.system(size: 16))
                    .padding(.top, 16)
                    .padding(.horizontal, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .contentShape(Rectangle()) // 确保整个区域可点击
        .onTapGesture {
            onFocused?()
            showEditor = true
        }
        // 使用 fullScreenCover 进行物理隔离，确保编辑器拥有独立的生命周期
        .fullScreenCover(isPresented: $showEditor) {
            NewNoteModalView(isPresented: $showEditor)
        }
    }
}

/// 专门用于 Modal 弹出的新建记录包装器
struct NewNoteModalView: View {
    @Environment(NoteStore.self) var noteStore
    @Binding var isPresented: Bool
    var initialContent: String = ""
    var existingNote: NoteItem? = nil
    /// 当为 true 时，用户按返回键会始终删除未发布的记录（用于从快捷输入展开的场景）
    var deleteOnCancel: Bool = false
    @State private var currentNote: NoteItem?
    
    var body: some View {
        NavigationStack {
            Group {
                if let note = currentNote {
                    NoteView(
                        note: note,
                        onPublish: {
                            // 发布成功，关闭页面
                            isPresented = false
                        }
                    )
                    // 确保每次都是全新的编辑器实例
                    .id(note.id)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
             
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        // 手动取消，触发清理逻辑
                        if let note = currentNote, !deleteOnCancel {
                            // 当 deleteOnCancel 为 true（从快捷输入展开的场景）时，
                            // 不在这里删除，而是交给 NoteView 的 cleanupOnExit 处理，
                            // 否则会在 NoteView 将编辑内容同步回 model 之前就删除笔记，
                            // 导致用户在全屏编辑器中输入的内容丢失。
                            let isEmpty = note.content.isEmpty && note.attachments.isEmpty
                            if isEmpty {
                                noteStore.permanentlyDeleteNote(note)
                            }
                        }
                        isPresented = false
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                    }
                }
            }
        }
        .onAppear {
            if currentNote == nil {
                if let existingNote {
                    currentNote = existingNote
                } else {
                    let note = noteStore.createNote()
                    if !initialContent.isEmpty {
                        note.content = initialContent
                    }
                    currentNote = note
                }
            }
        }
    }
}

// MARK: - 新建记录独立页面

/// 新建记录编辑页 - 点击组件后 push 到这个页面
/// 工具栏：撤销、重做、发布（保存并重置为新记录）
/// 返回按钮关闭页面回到 dashboard
struct NewNoteEditorPage: View {
    @Environment(NoteStore.self) var noteStore
    @State private var currentNote: NoteItem?
    
    var body: some View {
        Group {
            if let note = currentNote {
                NoteView(note: note, onPublish: publishAndReset)
                    .id(note.id) // 强制重建视图
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if currentNote == nil {
                createNewNote()
            }
        }
    }
    
    private func publishAndReset() {
        // 当前记录已通过 NoteView 自动保存
        // 创建新记录并重置编辑器
        createNewNote()
    }
    
    private func createNewNote() {
        let note = noteStore.createNote()
        currentNote = note
    }
}

// MARK: - 新建记录按钮组件

struct NewNoteButton: View {
    let verticalPadding: CGFloat
    var iconSize: CGFloat = 36 // Default size
    @State private var showEditor = false
    @Environment(\.appTheme) private var theme
    
    var body: some View {
        Button {
            showEditor = true
        } label: {
            VStack(spacing: 10) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: iconSize))
                    .foregroundStyle(theme.colors.accent)
                    .symbolRenderingMode(.hierarchical)

                Text("新建记录")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.colors.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(theme.colors.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                    )
            )
            .shadow(color: theme.colors.shadow, radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .fullScreenCover(isPresented: $showEditor) {
            NewNoteModalView(isPresented: $showEditor)
        }
    }
}

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
    @State private var newEncouragementText = DashboardItem.defaultEncouragement
    
    var page: DashboardPage? {
        dashboardConfig.pages.first(where: { $0.id == pageId })
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
            ForEach(page.items) { item in
                DashboardRow(
                    item: item,
                    isEditing: isEditing,
                    dashboardConfig: dashboardConfig,
                    pageId: pageId,
                    availableHeight: availableHeight,
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
                    Image(systemName: isEditing ? "plus.square.dashed" : "rectangle.on.rectangle.angled")
                        .font(.system(size: 60))
                        .foregroundColor(isEditing ? theme.colors.accent.opacity(0.6) : theme.colors.secondaryText.opacity(0.5))
                    
                    Text(isEditing ? "点击添加组件" : "这里空空如也~")
                        .font(.headline)
                        .foregroundColor(isEditing ? theme.colors.accent : theme.colors.secondaryText)

                    if !isEditing {
                        Text("点击这里开始定制")
                            .font(.subheadline)
                            .foregroundColor(theme.colors.accent.opacity(0.8))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)

                if isEditing {
                    let orderedTypes: [WidgetType] = [
                        //.newNote,
                        .inlineInput,
                        .encouragement,
                        .tag,
                        .recentNotes,
                        .search,
                        .trash,
                        .calendar
                    ]
                    Menu {
                        ForEach(orderedTypes, id: \.self) { type in
                            Button(action: {
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
                            }) {
                                Label("\(type.displayName)", systemImage: type.iconName)
                            }
                        }
                    } label: {
                        emptyStateContent
                    }
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
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.6).onEnded { _ in
                guard !isEditing else { return }
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                withAnimation(.easeIn(duration: 0.3)) {
                    isEditing = true
                }
            }
        )
        .toolbar {
            if isEditing {
                ToolbarItem(placement: .bottomBar) {
                    Menu {
                        // 按照指定顺序展示组件类型
                        let orderedTypes: [WidgetType] = [
                            //.newNote,
                            .inlineInput,
                            .encouragement,
                            //.statistics,
                            .tag,
                            .recentNotes,
                            .search,
                            .trash,
                            .calendar
                        ]
                        ForEach(orderedTypes, id: \.self) { type in
                            Button(action: {
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.impactOccurred()
                                
                                if type == .tag {
                                    // 标签类型需要输入标签名
                                    showingAddTagWidget = true
                                } else if type == .encouragement {
                                    // 鼓励组件带有默认文案，弹出输入框让用户确认或修改
                                    newEncouragementText = DashboardItem.defaultEncouragement
                                    showingAddEncouragementWidget = true
                                } else {
                                    // 其他类型直接添加
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        dashboardConfig.addItem(to: pageId, type: type)
                                    }
                                }
                            }) {
                                Label("\(type.displayName)", systemImage: type.iconName)
                            }
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(theme.colors.accent)
                            .shadow(radius: 2)
                    }

                }
            }
        }
        .sheet(isPresented: $showingAddTagWidget) {
            AddTagWidgetSheet { tagName in
                addTagWidget(tagName: tagName)
            }
            .environment(noteStore)
        }
        .alert("添加鼓励组件", isPresented: $showingAddEncouragementWidget) {
            TextField("输入鼓励的话", text: $newEncouragementText)
            Button("取消", role: .cancel) { }
            Button("添加") {
                let content = newEncouragementText.isEmpty ? DashboardItem.defaultEncouragement : String(newEncouragementText.prefix(200))
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    dashboardConfig.addItem(to: pageId, type: .encouragement, content: content)
                }
            }
        } message: {
            Text("请输入一句鼓励自己的话")
        }
        } // ScrollViewReader
    }
    
    private func addTagWidget(tagName: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            dashboardConfig.addItem(to: pageId, type: .tag, tagName: tagName)
        }
    }
}

struct DashboardRow: View {
    @Environment(NoteStore.self) var noteStore
    @Environment(\.appTheme) private var theme
    let item: DashboardItem
    let isEditing: Bool
    @Bindable var dashboardConfig: DashboardConfig
    let pageId: UUID
    var availableHeight: CGFloat = 0
    var onFullPageFocused: (() -> Void)? = nil
    
    @State private var showSearchDetail = false
    @State private var showTagDetail = false
    @State private var showRecentNotesDetail = false
    @State private var showDeleteConfirmation = false
    @State private var showEncouragementEdit = false
    @State private var encouragementTextTemp = ""
    
    /// Full page height: use available height from container, minus some padding for list insets
    private var fullPageHeight: CGFloat {
        availableHeight > 0 ? availableHeight - 32 : 600
    }
    
    @ViewBuilder
    private var widgetContent: some View {
        switch item.type {
        case .search:
            SearchWidget(size: item.size, showSearch: $showSearchDetail)
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
            InlineInputWidget(size: item.size, onFocused: onFullPageFocused)
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
            if !item.type.supportedSizes.isEmpty {
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
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(Color.clear)
    }
    
    private func updateSize(_ size: WidgetSize) {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            dashboardConfig.updateSize(in: pageId, for: item.id, size: size)
        }
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
                // 创建一个全新的临时记录
                let note = noteStore.createNote()
                if !initialContent.isEmpty {
                    note.content = initialContent
                }
                currentNote = note
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

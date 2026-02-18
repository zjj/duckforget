import SwiftUI
import SwiftData

struct DashboardDetailView: View {
    @Environment(NoteStore.self) var noteStore
    @ObservedObject var dashboardConfig: DashboardConfig
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
                    onFullPageFocused: item.size == .fullPage ? {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(item.id, anchor: .top)
                        }
                    } : nil
                )
                .id(item.id)
            }
            .onMove { source, destination in
                dashboardConfig.moveItem(in: pageId, from: source, to: destination)
            }
            
            // Empty state guidance
            if page.items.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: isEditing ? "plus.square.dashed" : "rectangle.on.rectangle.angled")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    Text(isEditing ? "点击下方「添加组件」开始定制" : "这个仪表盘是空的")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    if !isEditing {
                        Text("点击「定制」开始添加组件")
                            .font(.subheadline)
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .environment(\.editMode, .constant(isEditing ? .active : .inactive))
        .toolbar {
            if isEditing {
                ToolbarItem(placement: .bottomBar) {
                    Menu {
                        // 按照指定顺序展示组件类型
                        let orderedTypes: [WidgetType] = [
                            .newNote,
                            .encouragement,
                            //.statistics,
                            .tag,
                            .recentNotes,
                            .search,
                            .trash
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
                                Label("添加 \(type.displayName)", systemImage: type.iconName)
                            }
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.accentColor)
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
    let item: DashboardItem
    let isEditing: Bool
    @ObservedObject var dashboardConfig: DashboardConfig
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
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Widget Content
            Group {
                switch item.type {
                case .search:
                    SearchWidget(size: item.size, showSearch: $showSearchDetail)
                case .tag:
                    if let tagName = item.tagName {
                        TagWidget(tagName: tagName, size: item.size, showTagDetail: $showTagDetail)
                    } else {
                        Text("标签未设置")
                            .foregroundColor(.secondary)
                    }
                case .recentNotes:
                    RecentNotesWidget(size: item.size, showRecentNotes: $showRecentNotesDetail)
                case .newNote:
                    newNoteCard(size: item.size)
                case .trash:
                    TrashWidget(size: item.size)
                case .statistics:
                    StatisticsWidget(size: item.size)
                case .encouragement:
                    EncouragementWidget(content: item.content ?? DashboardItem.defaultEncouragement, size: item.size)
                }
            }
            .frame(minHeight: item.size == .fullPage ? fullPageHeight : nil)
            .allowsHitTesting(!isEditing)
            .opacity(isEditing ? 0.7 : 1.0)
            .scaleEffect(isEditing ? 0.98 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isEditing)
            .navigationDestination(isPresented: $showSearchDetail) {
                NoteSearchPage(pageTitle: "搜索")
            }
            .navigationDestination(isPresented: $showTagDetail) {
                if let tagName = item.tagName {
                    TagNotesListPage(tagName: tagName)
                        .environment(noteStore)
                }
            }
            .navigationDestination(isPresented: $showRecentNotesDetail) {
                NoteSearchPage(
                    pageTitle: "最近记录",
                    filterRecentDays: 7,
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
            
            // Edit Overlays
            if isEditing {
                // 点击遮罩：拦截点击事件，防止误触组件内部逻辑，或者误删除
                Color.white.opacity(0.01)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // 空操作：拦截点击
                    }
                
                HStack(spacing: 8) {
                    // Edit Content Button for Encouragement Widget
                    if item.type == .encouragement {
                        Button {
                            encouragementTextTemp = item.content ?? ""
                            showEncouragementEdit = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Circle().fill(Color.orange))
                                .shadow(color: .orange.opacity(0.3), radius: 4, x: 0, y: 2)
                        }
                        .buttonStyle(.borderless)
                    }

                    // Resize Menu
                    if item.type != .trash && item.type != .encouragement {
                        Menu {
                            Button("小 (Compact)", systemImage: "rectangle.grid.1x2") {
                                let generator = UISelectionFeedbackGenerator()
                                generator.selectionChanged()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { 
                                    dashboardConfig.updateSize(in: pageId, for: item.id, size: .small) 
                                }
                            }
                            Button("中 (Standard)", systemImage: "rectangle.grid.2x2") {
                                let generator = UISelectionFeedbackGenerator()
                                generator.selectionChanged()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { 
                                    dashboardConfig.updateSize(in: pageId, for: item.id, size: .medium) 
                                }
                            }
                            Button("大 (Large)", systemImage: "rectangle.grid.3x2") {
                                let generator = UISelectionFeedbackGenerator()
                                generator.selectionChanged()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { 
                                    dashboardConfig.updateSize(in: pageId, for: item.id, size: .large) 
                                }
                            }
                            Button("全屏 (Full Page)", systemImage: "rectangle.expand.vertical") {
                                let generator = UISelectionFeedbackGenerator()
                                generator.selectionChanged()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { 
                                    dashboardConfig.updateSize(in: pageId, for: item.id, size: .fullPage) 
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Circle().fill(Color.blue))
                                .shadow(color: .blue.opacity(0.3), radius: 4, x: 0, y: 2)
                        }
                        .menuStyle(.borderlessButton) // 修复 List 中 Menu 点击问题
                    }
                    
                    // Delete Button
                    Button {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Circle().fill(Color.red))
                            .shadow(color: .red.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.borderless) // 修复在 List 编辑模式下无法点击的问题
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
                }
                .padding(8)
                // Offset slightly to avoid overlap with List reorder handles if they appear
                .padding(.trailing, 30)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
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
                Image(systemName: "text.pad.header.badge.plus")
                    .font(.system(size: iconSize))
                    .foregroundColor(.accentColor)
                if size == .fullPage {
                    Text("全屏模式：直接显示编辑器")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, verticalPadding)
            .background(Color(.systemGray6))
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
    @State private var showEditor = false
    var onFocused: (() -> Void)? = nil
    
    var body: some View {
        // 修改为点击触发式：显示一个看起来像编辑器的占位视图
        // 点击后弹出全屏编辑器，从未彻底解决生命周期竞态问题
        VStack(spacing: 0) {
            // 模拟顶部工具栏区域
            HStack {
                Image(systemName: "text.pad.header.badge.plus")
                    .font(.headline)
                    .foregroundColor(.accentColor)
                    .fontWeight(.bold)

                Text("新建记录")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
            
            Divider()
            
            // 模拟内容区域
            ZStack(alignment: .topLeading) {
                Color(.systemBackground)
                
                Text("点击输入...")
                    .foregroundColor(.secondary)
                    .padding(.top, 12)
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
    @State private var currentNote: NoteItem?
    
    var body: some View {
        NavigationStack {
            Group {
                if let note = currentNote {
                    NoteEditorView(
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
                        // 手动取消，触发清理逻辑（需确保 NoteEditorView 的 onDisappear 能处理）
                        // 或者在这里手动删除空记录
                        if let note = currentNote,
                           note.content.isEmpty && note.attachments.isEmpty {
                            noteStore.permanentlyDeleteNote(note)
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
                currentNote = noteStore.createNote()
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
                NoteEditorView(note: note, onPublish: publishAndReset)
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
        // 当前记录已通过 NoteEditorView 自动保存
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
    
    var body: some View {
        NavigationLink {
            NewNoteEditorPage()
        } label: {
            VStack(spacing: 12) {
                Image(systemName: "text.pad.header.badge.plus")
                    .font(.system(size: iconSize))
                    .foregroundColor(.accentColor)
                    // Make it more eye-catching with a symbol effect (iOS 17+) or just bold
                    .symbolRenderingMode(.hierarchical)
                    .fontWeight(.bold)
                
                Text("点击记录")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, verticalPadding)
            .background(Color(.systemGray6))
            .cornerRadius(16)
        }
    }
}

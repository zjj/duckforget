import SwiftData
import SwiftUI

/// 主页容器：使用 TabView 分页，Page 0 是设置/管理页，后续是 dashboard 页
struct FolderListView: View {
    @Environment(NoteStore.self) var noteStore
    @StateObject private var dashboardConfig = DashboardConfig()
    
    // Page Management State
    @State private var showingAddPageAlert = false
    @State private var showingRenameAlert = false
    @State private var newPageName = ""
    @State private var pageToRename: DashboardPage?
    
    // Tab Selection
    @State private var selectedTab: UUID? = nil
    @State private var editingStates: [UUID: Bool] = [:]
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    private let settingsTabID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    private var isAnyPageEditing: Bool {
        editingStates.values.contains(true)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Custom compact header for dashboard pages
                if !isSettingsPage {
                    dashboardHeaderBar
                    Divider()
                }
                
                GeometryReader { geo in
                    TabView(selection: Binding(
                        get: { selectedTab ?? settingsTabID },
                        set: { 
                            // 当切换页面时，自动取消所有页面的编辑状态
                            if isAnyPageEditing {
                                for key in editingStates.keys {
                                    editingStates[key] = false
                                }
                            }
                            selectedTab = $0
                        }
                    )) {
                        // Page 0: Settings / Management
                        DashboardManagementView(
                            dashboardConfig: dashboardConfig,
                            showingAddPageAlert: $showingAddPageAlert,
                            showingRenameAlert: $showingRenameAlert,
                            newPageName: $newPageName,
                            pageToRename: $pageToRename,
                            selectedTab: $selectedTab,
                            editingStates: $editingStates
                        )
                        .tag(settingsTabID)
                        
                        // Pages 1+: Dashboards
                        ForEach(dashboardConfig.pages) { page in
                            DashboardDetailView(
                                dashboardConfig: dashboardConfig,
                                pageId: page.id,
                                isEditing: Binding(
                                    get: { editingStates[page.id] ?? false },
                                    set: { editingStates[page.id] = $0 }
                                ),
                                availableHeight: geo.size.height
                            )
                            .tag(page.id)
                            .onDisappear {
                                // 切换页面时强制收起键盘，防止键盘残留在不相关的页面上
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            }
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }
            .navigationBarHidden(!isSettingsPage)
            .navigationTitle("")
            .toolbar {
                if isSettingsPage {
                    // Settings Icon as Title (Display only)
                    ToolbarItem(placement: .topBarLeading) {
                         Image(systemName: "gear")
                            .font(.title) // Reduced from .largeTitle
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                    }
                }
            }
            .onAppear {
                if selectedTab == nil {
                    if let firstPage = dashboardConfig.pages.first {
                        selectedTab = firstPage.id
                    } else {
                        selectedTab = settingsTabID
                    }
                }
            }
        }
        // Alerts attached to the container to ensure they present over TabView
        .alert("新建页面", isPresented: $showingAddPageAlert) {
            TextField("页面名称", text: $newPageName)
            Button("取消", role: .cancel) {}
            Button("创建") {
                let trimmed = newPageName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    let _ = dashboardConfig.addPage(name: trimmed)
                    // 不自动跳转，保留在当前页面
                }
            }
        }
        .alert("重命名页面", isPresented: $showingRenameAlert) {
            TextField("页面名称", text: $newPageName)
            Button("取消", role: .cancel) {}
            Button("保存") {
                let trimmed = newPageName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, let page = pageToRename {
                    dashboardConfig.renamePage(page, newName: trimmed)
                }
            }
        }
        .alert("新建文件夹", isPresented: $showNewFolder) {
            TextField("文件夹名称", text: $newFolderName)
            Button("取消", role: .cancel) {}
            Button("创建") {
                let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    noteStore.createFolder(name: trimmed)
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var isSettingsPage: Bool {
        selectedTab == settingsTabID
    }
    
    /// Index of the current page within dashboardConfig.pages (nil if settings page)
    private var currentPageIndex: Int? {
        guard let selectedTab = selectedTab else { return nil }
        return dashboardConfig.pages.firstIndex(where: { $0.id == selectedTab })
    }
    
    private var currentPageName: String {
        if let selectedTab = selectedTab,
           let page = dashboardConfig.pages.first(where: { $0.id == selectedTab }) {
            return page.name
        }
        return "仪表盘"
    }
    
    // MARK: - Dashboard Header Bar
    
    /// 自定义头部：[齿轮+名称] [   页面指示点   ] [... / 完成]
    private var dashboardHeaderBar: some View {
        HStack(spacing: 0) {
            // Left: Title (Tap to go to Settings)
            HStack(spacing: 12) {
                Text(currentPageName)
                    .font(.headline)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation {
                    selectedTab = settingsTabID
                }
            }
            
            Spacer()
            
            // Center: iOS-style page indicator dots
            HStack(spacing: 6) {
                ForEach(Array(dashboardConfig.pages.enumerated()), id: \.element.id) { _, page in
                    Circle()
                        .fill(page.id == selectedTab ? Color.primary.opacity(0.9) : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                        .scaleEffect(page.id == selectedTab ? 1.0 : 0.85)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedTab)
                        .onTapGesture {
                            let generator = UISelectionFeedbackGenerator()
                            generator.selectionChanged()
                            withAnimation { selectedTab = page.id }
                        }
                }
            }
            
            Spacer()
            
            // Right: "..." or "完成"
            if let currentPageId = selectedTab {
                currentPageToolbarButton(for: currentPageId)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }
    
    @ViewBuilder
    private func currentPageToolbarButton(for pageId: UUID) -> some View {
        let isEditing = editingStates[pageId] ?? false
        
        if isEditing {
            Button {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    editingStates[pageId] = false
                }
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.accentColor)
            }
        } else {
            Menu {
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        editingStates[pageId] = true
                    }
                } label: {
                    Label("编辑", systemImage: "pencil.circle")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }
}

// Helper to wrap EditButton with custom appearance
struct EditButtonWrapper: View {
    @Environment(\.editMode) private var editMode

    var body: some View {
        Button {
            withAnimation {
                if editMode?.wrappedValue == .active {
                    editMode?.wrappedValue = .inactive
                } else {
                    editMode?.wrappedValue = .active
                }
            }
        } label: {
            if editMode?.wrappedValue == .active {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.accentColor)
            } else {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 20))
                    .foregroundColor(.accentColor)
            }
        }
    }
}

/// The view for managing dashboards (Page 0)
struct DashboardManagementView: View {
    @ObservedObject var dashboardConfig: DashboardConfig
    @EnvironmentObject var toolbarSettings: ToolbarSettings
    @Binding var showingAddPageAlert: Bool
    @Binding var showingRenameAlert: Bool
    @Binding var newPageName: String
    @Binding var pageToRename: DashboardPage?
    @Binding var selectedTab: UUID?
    @Binding var editingStates: [UUID: Bool]

    var body: some View {
        List {
            Section(header: 
                HStack {
                    Text("页面定制")
                    Spacer()
                    Button {
                        newPageName = ""
                        showingAddPageAlert = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.headline)
                            .foregroundColor(.accentColor)
                    }
                }
            ) {
                ForEach(dashboardConfig.pages) { page in
                    HStack {
                        // 禁用的左侧点击行为（只是展示）
                        HStack {
                            Image(systemName: "rectangle.grid.1x2")
                                .foregroundColor(.accentColor)
                            
                            Text(page.name)
                                .foregroundColor(.primary)
                            
                            Spacer()
                        }
                        .contentShape(Rectangle()) // 确保整个区域可点击但不触发操作
                        
                        // 右侧菜单按钮
                        Menu {
                            Button {
                                // 切换并进入编辑模式
                                withAnimation {
                                    selectedTab = page.id
                                    // 稍微延迟以确保页面切换完成
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        editingStates[page.id] = true
                                        // 关闭其他页面的编辑状态
                                        for id in editingStates.keys where id != page.id {
                                            editingStates[id] = false
                                        }
                                    }
                                }
                            } label: {
                                Label("编辑", systemImage: "pencil.circle")
                            }
                            
                            Button {
                                // 仅跳转不编辑
                                withAnimation {
                                    selectedTab = page.id
                                    // 确保编辑状态关闭
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        editingStates[page.id] = false
                                    }
                                }
                            } label: {
                                Label("跳转", systemImage: "arrow.right.circle")
                            }
                            
                            Divider()
                            
                            Button {
                                pageToRename = page
                                newPageName = page.name
                                showingRenameAlert = true
                            } label: {
                                Label("重命名", systemImage: "pencil")
                            }
                            
                            Button(role: .destructive) {
                                dashboardConfig.removePage(page)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 20))
                                .foregroundColor(.secondary)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.impactOccurred()
                            dashboardConfig.removePage(page)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        
                        Button {
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                            pageToRename = page
                            newPageName = page.name
                            showingRenameAlert = true
                        } label: {
                            Label("重命名", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                    .onDrag {
                        return NSItemProvider(object: page.id.uuidString as NSString)
                    }
                }
                .onMove { source, destination in
                    dashboardConfig.movePage(from: source, to: destination)
                }
            }
            
            Section(header: Text("编辑器")) {
                Toggle(isOn: $toolbarSettings.isVoiceInputEnabled) {
                    Label("语音输入", systemImage: "mic.fill")
                }
                .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                
                NavigationLink(destination: ToolbarSortView()) {
                    Label("工具栏", systemImage: "arrow.left.arrow.right")
                }
            }
        }
    }
}

struct PageDropDelegate: DropDelegate {
    let pages: [DashboardPage]
    let dashboardConfig: DashboardConfig
    
    func performDrop(info: DropInfo) -> Bool {
        return true
    }
    
    func dropEntered(info: DropInfo) {
        // 简化拖动排序：
        // List的原生.onDrag/.onDrop较为复杂，这里利用 DropDelegate 进行占位。
        // 但最稳妥的Reorder方式还是在 EditMode 下使用 .onMove。
        // 若要长按Reorder，可以尝试激活 EditMode 或使用第三方库。
        // 鉴于系统限制，我们保留 EditMode 下的 reorder 能力。
    }
}


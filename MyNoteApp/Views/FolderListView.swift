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
                        set: { selectedTab = $0 }
                    )) {
                        // Page 0: Settings / Management
                        DashboardManagementView(
                            dashboardConfig: dashboardConfig,
                            showingAddPageAlert: $showingAddPageAlert,
                            showingRenameAlert: $showingRenameAlert,
                            newPageName: $newPageName,
                            pageToRename: $pageToRename,
                            selectedTab: $selectedTab
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
            .navigationTitle(isSettingsPage ? "仪表盘管理" : "")
            .navigationBarTitleDisplayMode(isSettingsPage ? .large : .inline)
            .toolbar {
                if isSettingsPage {
                    ToolbarItem(placement: .navigationBarLeading) {
                        EditButton()
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: {
                            newPageName = ""
                            showingAddPageAlert = true
                        }) {
                            Label("新建页面", systemImage: "plus")
                        }
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
                    let newPage = dashboardConfig.addPage(name: trimmed)
                    // Optionally switch to new page
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                         selectedTab = newPage.id
                    }
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
            HStack(spacing: 8) {
                Text(currentPageName)
                    .font(.headline)
                    .lineLimit(1)
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
            Button("完成") {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    editingStates[pageId] = false
                }
            }
            .fontWeight(.semibold)
        } else {
            Menu {
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        editingStates[pageId] = true
                    }
                } label: {
                    Label("编辑", systemImage: "pencil")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }
}

/// The view for managing dashboards (Page 0)
struct DashboardManagementView: View {
    @ObservedObject var dashboardConfig: DashboardConfig
    @Binding var showingAddPageAlert: Bool
    @Binding var showingRenameAlert: Bool
    @Binding var newPageName: String
    @Binding var pageToRename: DashboardPage?
    @Binding var selectedTab: UUID?
    
    var body: some View {
        List {
            Section("我的仪表盘") {
                ForEach(dashboardConfig.pages) { page in
                    Button {
                        // Switch tab to this page
                        withAnimation {
                            selectedTab = page.id
                        }
                    } label: {
                        HStack {
                            Label(page.name, systemImage: "rectangle.grid.1x2")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
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
                    .swipeActions(edge: .leading) {
                        Button {
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                            let duplicated = dashboardConfig.duplicatePage(page)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                selectedTab = duplicated.id
                            }
                        } label: {
                            Label("复制", systemImage: "doc.on.doc")
                        }
                        .tint(.green)
                    }
                    .contextMenu {
                        Button {
                            selectedTab = page.id
                        } label: {
                            Label("打开", systemImage: "arrow.up.right.square")
                        }
                        
                        Button {
                            let duplicated = dashboardConfig.duplicatePage(page)
                            selectedTab = duplicated.id
                        } label: {
                            Label("复制页面", systemImage: "doc.on.doc")
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
                    }
                }
                .onMove { source, destination in
                    dashboardConfig.movePage(from: source, to: destination)
                }
            }
        }
    }
}

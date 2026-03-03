import SwiftData
import SwiftUI

/// 主页容器：使用 TabView 分页，Page 0 是设置/管理页，后续是 dashboard 页
struct DashboardContainerView: View {
    @Environment(NoteStore.self) var noteStore
    @Environment(\.appTheme) private var theme
    @State private var dashboardConfig = DashboardConfig()
    @EnvironmentObject var deepLinkHandler: DeepLinkHandler
    
    // Page Management State
    @State private var showingAddPageAlert = false
    @State private var showingRenameAlert = false
    @State private var newPageName = ""
    @State private var pageToRename: DashboardPage?
    
    // Tab Selection
    @State private var selectedTab: UUID? = nil
    @State private var editingStates: [UUID: Bool] = [:]
    private let settingsTabID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    
    // Deep link navigation
    @State private var noteToNavigate: NoteItem?
    @State private var showNoteEditor = false
    @State private var openInEditMode = false

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
        .onChange(of: deepLinkHandler.noteToOpen) { _, noteID in
            guard let noteID = noteID else { return }
            
            // 查找笔记
            let descriptor = FetchDescriptor<NoteItem>(
                predicate: #Predicate { $0.id == noteID && !$0.isDeleted }
            )
            if let notes = try? noteStore.modelContext.fetch(descriptor),
               let note = notes.first {
                noteToNavigate = note
                openInEditMode = deepLinkHandler.openInEditMode
                showNoteEditor = true
                deepLinkHandler.reset()
            }
        }
        .onChange(of: deepLinkHandler.shouldCreateNewNote) { _, shouldCreate in
            if shouldCreate {
                noteToNavigate = noteStore.createNote()
                openInEditMode = true
                showNoteEditor = true
                deepLinkHandler.reset()
            }
        }
        .fullScreenCover(isPresented: $showNoteEditor, onDismiss: {
            noteToNavigate = nil
            openInEditMode = false
        }) {
            if let note = noteToNavigate {
                NavigationStack {
                    NoteView(note: note, startInEditMode: openInEditMode)
                        .environment(noteStore)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button {
                                    showNoteEditor = false
                                } label: {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 17, weight: .semibold))
                                }
                            }
                        }
                }
                .gesture(
                    DragGesture()
                        .onEnded { value in
                            // Only allow swipe to dismiss if starting from the left edge (simulating navigation back)
                            if value.startLocation.x < 50 && value.translation.width > 100 {
                                showNoteEditor = false
                            }
                        }
                )
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
    
    /// 自定义头部：[名称 >] [   页面指示胶囊   ] [... / 完成]
    private var dashboardHeaderBar: some View {
        HStack(spacing: 0) {
            // Left: Title with chevron hint (Tap to go to Settings)
            HStack(spacing: 5) {
                Text(currentPageName)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(theme.colors.secondaryText.opacity(0.4))
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation {
                    selectedTab = settingsTabID
                }
            }
            
            Spacer()
            
            // Center: pill-shaped page indicators (active = stretched capsule)
            HStack(spacing: 5) {
                ForEach(Array(dashboardConfig.pages.enumerated()), id: \.element.id) { _, page in
                    Capsule()
                        .fill(page.id == selectedTab
                              ? theme.colors.primaryText.opacity(0.75)
                              : theme.colors.secondaryText.opacity(0.22))
                        .frame(width: page.id == selectedTab ? 20 : 6, height: 6)
                        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: selectedTab)
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
        .background(.bar)
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
                Text("完成")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(theme.colors.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(theme.colors.accent.opacity(0.1))
                    .clipShape(Capsule())
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
                    .font(.system(size: 22))
                    .foregroundColor(theme.colors.primaryText.opacity(0.75))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
        }
    }
}


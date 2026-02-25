import SwiftUI

/// The view for managing dashboards (Page 0)
struct DashboardManagementView: View {
    @Environment(NoteStore.self) var noteStore
    @Bindable var dashboardConfig: DashboardConfig
    @Environment(ToolbarSettings.self) var toolbarSettings
    @Environment(\.appTheme) private var theme
    @Binding var showingAddPageAlert: Bool
    @Binding var showingRenameAlert: Bool
    @Binding var newPageName: String
    @Binding var pageToRename: DashboardPage?
    @Binding var selectedTab: UUID?
    @Binding var editingStates: [UUID: Bool]
    
    @State private var trashRetentionDays: Int = AppSettings.shared.trashRetentionDays
    @State private var pageToDelete: DashboardPage?
    @State private var showDeleteConfirmation = false
    @State private var isExporting = false
    @State private var exportedURL: URL?
    @State private var showExportSheet = false
    @State private var showExportConfigSheet = false
    @State private var exportErrorMessage: String?
    @State private var showExportError = false
    @State private var exportCurrent: Int = 0
    @State private var exportTotal: Int = 0

    var body: some View {
        @Bindable var toolbarSettings = toolbarSettings
        List {
            Section(header: 
                HStack {
                    Text("页面定制")
                    Spacer()
                    
                    Menu {
                        Button {
                            dashboardConfig.addDefaultLayoutPage()
                        } label: {
                            Label("添加起点配置", systemImage: "plus.square.on.square")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.headline)
                            .foregroundColor(theme.colors.accent)
                    }
                    .padding(.trailing, 8)
                    
                    Button {
                        newPageName = ""
                        showingAddPageAlert = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.headline)
                            .foregroundColor(theme.colors.accent)
                    }
                }, footer: 
                    HStack(spacing: 2) {
                        Text("您可以添加自定义页面，或点击")
                        Menu {
                            Button {
                                dashboardConfig.addDefaultLayoutPage()
                            } label: {
                                Label("添加起点配置", systemImage: "plus.square.on.square")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .foregroundColor(theme.colors.accent)
                        }
                        Text("添加起点配置。")
                    }
            ) {
                ForEach(dashboardConfig.pages) { page in
                    HStack {
                        // 禁用的左侧点击行为（只是展示）
                        HStack {
                            Image(systemName: "rectangle.grid.1x2")
                                .foregroundColor(theme.colors.accent)
                            
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
                                pageToDelete = page
                                showDeleteConfirmation = true
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
                            pageToDelete = page
                            showDeleteConfirmation = true
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
            
            Section(header: Text("数据统计")) {
                NavigationLink {
                    StatisticsWidget(size: .fullPage)
                } label: {
                    Label("查看统计数据", systemImage: "chart.bar.xaxis")
                }
            }
            
            Section(header: Text("标签")) {
                NavigationLink(destination: TagManagementPage()) {
                    Label("标签管理", systemImage: "tag")
                }
            }

            Section(header: Text("编辑器")) {
                Toggle(isOn: $toolbarSettings.isVoiceInputEnabled) {
                    Label("语音转文字", systemImage: "mic.fill")
                }
                .toggleStyle(SwitchToggleStyle(tint: theme.colors.accent))
                
                NavigationLink(destination: ToolbarSortView()) {
                    Label("工具栏", systemImage: "arrow.left.arrow.right")
                }
            }

            Section(header: Text("外观")) {
                NavigationLink(destination: ThemeSettingsView()) {
                    Label("外观主题", systemImage: "paintpalette")
                }
            }

            Section {
                HStack {
                    Label("保留天数", systemImage: "trash")
                    Spacer()
                    Stepper(value: $trashRetentionDays, in: 1...90, step: 1) {
                        Text("\(trashRetentionDays) 天")
                            .foregroundColor(.secondary)
                    }
                    .onChange(of: trashRetentionDays) { _, newValue in
                        AppSettings.shared.trashRetentionDays = newValue
                    }
                }
            } header: {
                Text("废纸篓")
            } footer: {
                Text("废纸篓中的记录将在删除后保留指定天数，超过时间后将被永久删除")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section {
                Button {
                    showExportConfigSheet = true
                } label: {
                    HStack {
                        Label("导出笔记", systemImage: "arrow.up.doc.on.clipboard")
                            .foregroundColor(.primary)
                        Spacer()
                        if isExporting {
                            HStack(spacing: 6) {
                                Text(exportTotal > 0 ? "\(exportCurrent)/\(exportTotal)" : "")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .disabled(isExporting)
            } header: {
                Text("数据导出")
            } footer: {
                if isExporting {
                    Text("正在整理笔记 \(exportCurrent) / \(exportTotal)，请稍候…")
                        .font(.caption)
                        .foregroundColor(theme.colors.accent)
                } else {
                    Text("按时间范围或标签筛选笔记，打包为 ZIP 文件导出")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section(header: Text("其它")) {
                NavigationLink(destination: AboutView()) {
                    Label("关于", systemImage: "info.circle")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.colors.background.ignoresSafeArea())
        .alert("确认删除", isPresented: $showDeleteConfirmation) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                if let page = pageToDelete {
                    dashboardConfig.removePage(page)
                    pageToDelete = nil
                }
            }
        } message: {
            if let page = pageToDelete {
                Text("确定要删除页面「\(page.name)」吗？该页面的所有组件配置都将被清除。")
            }
        }
        .sheet(isPresented: $showExportSheet, onDismiss: {
            if let url = exportedURL {
                try? FileManager.default.removeItem(at: url)
                exportedURL = nil
            }
        }) {
            if let url = exportedURL {
                ShareSheet(items: [url])
            }
        }
        .sheet(isPresented: $showExportConfigSheet) {
            ExportFilterSheet { startDate, endDate, tag in
                exportNotes(startDate: startDate, endDate: endDate, tag: tag)
            }
        }
        .alert("导出失败", isPresented: $showExportError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(exportErrorMessage ?? "未知错误")
        }
    }

    // MARK: - Private Helpers

    private func exportNotes(startDate: Date, endDate: Date, tag: TagItem?) {
        isExporting = true
        exportCurrent = 0
        exportTotal = 0
        let service = ExportService(noteStore: noteStore)
        // Regular Task inherits @MainActor from the call site.
        // exportAllNotes handles background dispatch internally, so no
        // Task.detached or DispatchQueue is needed here.
        Task {
            do {
                let url = try await service.exportAllNotes(
                    startDate: startDate,
                    endDate: endDate,
                    tag: tag
                ) { current, total in
                    // Called on @MainActor via Task { @MainActor in } inside exportAllNotes.
                    exportCurrent = current
                    exportTotal   = total
                }
                isExporting = false
                exportedURL = url
                showExportSheet = true
            } catch {
                isExporting = false
                exportErrorMessage = error.localizedDescription
                showExportError = true
            }
        }
    }
}

// MARK: - Export Filter Sheet

struct ExportFilterSheet: View {
    @Environment(NoteStore.self) var noteStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme

    /// 默认开始时间：当年 1 月 1 日
    @State private var startDate: Date = {
        let comps = Calendar.current.dateComponents([.year], from: Date())
        return Calendar.current.date(from: comps) ?? Date()
    }()
    @State private var endDate: Date = Date()
    @State private var selectedTagID: UUID? = nil

    let onExport: (Date, Date, TagItem?) -> Void

    private var allTags: [TagItem] { noteStore.fetchTags() }

    private var selectedTag: TagItem? {
        guard let id = selectedTagID else { return nil }
        return allTags.first { $0.id == id }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("时间范围")) {
                    DatePicker("开始时间", selection: $startDate, displayedComponents: .date)
                    DatePicker("结束时间", selection: $endDate,
                               in: startDate..., displayedComponents: .date)
                }

                Section(header: Text("标签筛选")) {
                    Picker("标签", selection: $selectedTagID) {
                        Text("不限标签").tag(nil as UUID?)
                        ForEach(allTags) { tag in
                            Label(tag.name, systemImage: "tag")
                                .tag(tag.id as UUID?)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.colors.background.ignoresSafeArea())
            .navigationTitle("导出笔记")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("导出") {
                        onExport(startDate, endDate, selectedTag)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

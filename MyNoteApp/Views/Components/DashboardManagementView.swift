import SwiftUI

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
    
    @State private var trashRetentionDays: Int = AppSettings.shared.trashRetentionDays

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
            
            Section(header: Text("标签")) {
                NavigationLink(destination: TagManagementPage()) {
                    Label("标签管理", systemImage: "tag")
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
                Text("回收站")
            } footer: {
                Text("回收站中的记录将在删除后保留指定天数，超过时间后将被永久删除")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

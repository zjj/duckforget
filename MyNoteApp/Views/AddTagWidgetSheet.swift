import SwiftUI
import SwiftData

/// 添加标签组件Sheet - 选择已有标签或创建新标签
struct AddTagWidgetSheet: View {
    @Environment(NoteStore.self) var noteStore
    @Environment(\.dismiss) private var dismiss
    
    @Query(sort: \TagItem.sortOrder) var allTags: [TagItem]
    
    @State private var showingNewTagInput = false
    @State private var newTagName = ""
    @State private var searchText = ""
    
    var onSelectTag: (String) -> Void
    
    var filteredTags: [TagItem] {
        if searchText.isEmpty {
            return allTags
        } else {
            return allTags.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 搜索栏
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("搜索或输入新标签", text: $searchText)
                        .textFieldStyle(.plain)
                    
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal)
                .padding(.vertical, 8)
                
                Divider()
                
                // 标签列表
                if allTags.isEmpty {
                    // 空状态
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "tag")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary.opacity(0.6))
                        Text("暂无标签")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        
                        if !searchText.isEmpty {
                            Button {
                                createAndSelectTag(searchText)
                            } label: {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                    Text("创建标签 \"\(searchText)\"")
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                        } else {
                            Text("点击右上角添加新标签")
                                .font(.subheadline)
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                        Spacer()
                    }
                } else {
                    List {
                        // 如果搜索文本不为空且没有匹配的标签，显示创建选项
                        if !searchText.isEmpty && !allTags.contains(where: { $0.name.lowercased() == searchText.lowercased() }) {
                            Button {
                                createAndSelectTag(searchText)
                            } label: {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(.accentColor)
                                    Text("创建新标签 \"\(searchText)\"")
                                        .foregroundColor(.primary)
                                    Spacer()
                                }
                            }
                        }
                        
                        // 已有标签列表
                        if !filteredTags.isEmpty {
                            Section(header: filteredTags.count < allTags.count ? Text("已有标签") : nil) {
                                ForEach(filteredTags) { tag in
                                    Button {
                                        selectTag(tag.name)
                                    } label: {
                                        HStack {
                                            Image(systemName: "tag.fill")
                                                .foregroundColor(.orange)
                                            
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(tag.name)
                                                    .font(.headline)
                                                    .foregroundColor(.primary)
                                                
                                                TagNoteCountView(tagName: tag.name)
                                            }
                                            
                                            Spacer()
                                            
                                            Image(systemName: "chevron.right")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                        } else if !searchText.isEmpty {
                            ContentUnavailableView {
                                Label("无匹配标签", systemImage: "magnifyingglass")
                            } description: {
                                Text("点击上方按钮创建新标签")
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("选择标签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNewTagInput = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("新建标签", isPresented: $showingNewTagInput) {
                TextField("标签名称", text: $newTagName)
                Button("取消", role: .cancel) {
                    newTagName = ""
                }
                Button("创建") {
                    createAndSelectTag(newTagName)
                    newTagName = ""
                }
            }
        }
    }
    
    private func selectTag(_ tagName: String) {
        onSelectTag(tagName)
        dismiss()
    }
    
    private func createAndSelectTag(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        // 如果标签不存在，创建它
        if !allTags.contains(where: { $0.name == trimmed }) {
            noteStore.createTag(name: trimmed)
        }
        
        onSelectTag(trimmed)
        dismiss()
    }
}

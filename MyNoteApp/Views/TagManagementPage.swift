import SwiftUI
import SwiftData

/// 标签管理页面（在设置中）- 添加、重命名、删除标签
struct TagManagementPage: View {
    @Environment(NoteStore.self) var noteStore
    @Query(sort: \TagItem.sortOrder) var allTags: [TagItem]
    
    @State private var showingAddTag = false
    @State private var newTagName = ""
    @State private var editingTag: TagItem?
    @State private var editingTagName = ""
    @State private var tagToDelete: TagItem?
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        List {
            if allTags.isEmpty {
                ContentUnavailableView {
                    Label("暂无标签", systemImage: "tag")
                } description: {
                    Text("点击右上角添加新标签")
                }
            } else {
                ForEach(allTags) { tag in
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
                        
                        // 菜单按钮
                        Menu {
                            Button {
                                editingTag = tag
                                editingTagName = tag.name
                            } label: {
                                Label("重命名", systemImage: "pencil")
                            }
                            
                            Button(role: .destructive) {
                                tagToDelete = tag
                                showDeleteConfirmation = true
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 20))
                                .foregroundColor(.secondary)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            tagToDelete = tag
                            showDeleteConfirmation = true
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        
                        Button {
                            editingTag = tag
                            editingTagName = tag.name
                        } label: {
                            Label("重命名", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
            }
        }
        .navigationTitle("标签管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddTag = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("新建标签", isPresented: $showingAddTag) {
            TextField("标签名称", text: $newTagName)
            Button("取消", role: .cancel) {
                newTagName = ""
            }
            Button("创建") {
                createNewTag()
            }
        }
        .alert("重命名标签", isPresented: .constant(editingTag != nil)) {
            TextField("标签名称", text: $editingTagName)
            Button("取消", role: .cancel) {
                editingTag = nil
                editingTagName = ""
            }
            Button("保存") {
                renameTag()
            }
        }
        .alert("确认删除", isPresented: $showDeleteConfirmation) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                if let tag = tagToDelete {
                    noteStore.deleteTag(tag)
                    tagToDelete = nil
                }
            }
        } message: {
            if let tag = tagToDelete {
                Text("确定要删除标签「\(tag.name)」吗？这不会删除笔记，只会移除标签关联。")
            }
        }
    }
    
    private func createNewTag() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            newTagName = ""
            return
        }
        
        // 检查是否已存在同名标签
        if allTags.contains(where: { $0.name == trimmed }) {
            // 可以在这里显示错误提示
            newTagName = ""
            return
        }
        
        noteStore.createTag(name: trimmed)
        newTagName = ""
    }
    
    private func renameTag() {
        guard let tag = editingTag else { return }
        
        let trimmed = editingTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            editingTag = nil
            editingTagName = ""
            return
        }
        
        // 检查是否已存在同名标签（排除当前标签）
        if allTags.contains(where: { $0.name == trimmed && $0.id != tag.id }) {
            // 可以在这里显示错误提示
            editingTag = nil
            editingTagName = ""
            return
        }
        
        noteStore.renameTag(tag, to: trimmed)
        editingTag = nil
        editingTagName = ""
    }
}

struct TagNoteCountView: View {
    @Query var notes: [NoteItem]
    
    init(tagName: String) {
        let filter = #Predicate<NoteItem> { note in
            !note.isDeleted && note.tags.contains { $0.name == tagName }
        }
        _notes = Query(filter: filter)
    }
    
    var body: some View {
        Text("\(notes.count) 个记录")
            .font(.caption)
            .foregroundColor(.secondary)
    }
}

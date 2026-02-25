import SwiftUI
import SwiftData

/// 标签管理Sheet - 在记录编辑时管理标签
struct TagManagementSheet: View {
    let note: NoteItem
    @Environment(NoteStore.self) var noteStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    
    @Query(sort: \TagItem.sortOrder) var allTags: [TagItem]
    
    @State private var selectedTagIds: Set<UUID> = []
    @State private var showingAddTag = false
    @State private var newTagName = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 已选标签列表
                if !selectedTagIds.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("已选标签")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(allTags.filter { selectedTagIds.contains($0.id) }) { tag in
                                    HStack(spacing: 4) {
                                        Text(tag.name)
                                            .font(.subheadline)
                                        Button {
                                            selectedTagIds.remove(tag.id)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(theme.colors.accentSoft)
                                    .cornerRadius(16)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical, 12)
                    
                    Divider()
                }
                
                // 所有标签列表
                List {
                    ForEach(allTags) { tag in
                        Button {
                            if selectedTagIds.contains(tag.id) {
                                selectedTagIds.remove(tag.id)
                            } else {
                                selectedTagIds.insert(tag.id)
                            }
                        } label: {
                            HStack {
                                Image(systemName: selectedTagIds.contains(tag.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selectedTagIds.contains(tag.id) ? theme.colors.accent : .secondary)
                                
                                Label {
                                    Text(tag.name)
                                        .foregroundColor(.primary)
                                } icon: {
                                    Image(systemName: "tag.fill")
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("整理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        saveTagsToNote()
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        showingAddTag = true
                    } label: {
                        Label("新建标签", systemImage: "plus.circle.fill")
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
            .onAppear {
                // 初始化已选标签
                selectedTagIds = Set(note.tags.map { $0.id })
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
        if let existingTag = allTags.first(where: { $0.name == trimmed }) {
            selectedTagIds.insert(existingTag.id)
        } else {
            let newTag = noteStore.createTag(name: trimmed)
            selectedTagIds.insert(newTag.id)
        }
        
        newTagName = ""
    }
    
    private func saveTagsToNote() {
        let selectedTags = allTags.filter { selectedTagIds.contains($0.id) }
        noteStore.setTags(selectedTags, for: note)
    }
}

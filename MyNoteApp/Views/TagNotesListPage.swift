import SwiftUI
import SwiftData

/// 显示特定标签的所有笔记（类似NoteSearchPage但筛选特定标签）
struct TagNotesListPage: View {
    @Environment(NoteStore.self) var noteStore
    @Environment(\.dismiss) private var dismiss
    
    let tagName: String
    
    @Query(filter: #Predicate<NoteItem> { $0.isDeleted == false }, sort: \NoteItem.updatedAt, order: .reverse)
    var allNotes: [NoteItem]
    
    @State private var searchText = ""
    @State private var selectedNote: NoteItem?
    
    // 筛选属于该标签的笔记
    var tagNotes: [NoteItem] {
        allNotes.filter { note in
            note.tags.contains { $0.name == tagName }
        }
    }
    
    // 搜索过滤
    var filteredNotes: [NoteItem] {
        if searchText.isEmpty {
            return tagNotes
        } else {
            return tagNotes.filter { note in
                note.content.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 搜索栏
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("搜索 \(tagName) 标签", text: $searchText)
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
            .padding(12)
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding()
            
            Divider()
            
            // 笔记列表
            if filteredNotes.isEmpty {
                ContentUnavailableView {
                    Label(searchText.isEmpty ? "此标签下暂无笔记" : "无匹配结果", systemImage: "tag")
                } description: {
                    if searchText.isEmpty {
                        Text("创建笔记并添加 \(tagName) 标签")
                    } else {
                        Text("尝试其他关键词")
                    }
                }
            } else {
                List {
                    ForEach(filteredNotes) { note in
                        NavigationLink(destination: NoteEditorView(note: note).environment(noteStore)) {
                            NoteRowView(note: note)
                                .environment(noteStore)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(tagName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

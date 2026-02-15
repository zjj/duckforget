import SwiftUI
import SwiftData

struct SearchWidget: View {
    @Environment(NoteStore.self) var noteStore
    @State private var searchText = ""
    @State private var isSearchActive = false
    
    // 搜索结果
    @State private var searchResults: [NoteItem] = []
    
    var body: some View {
        VStack(spacing: 8) {
            Button {
                isSearchActive = true
            } label: {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    Text("搜索备忘录...")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $isSearchActive) {
                NavigationStack {
                    NoteListView(folder: nil, showAllNotes: true)
                        // 这里可以传入 initialSearchText 如果需要
                        .environment(noteStore)
                }
            }
        }
    }
}

struct FolderListWidget: View {
    @Environment(NoteStore.self) var noteStore
    @Query(sort: \FolderItem.sortOrder) var folders: [FolderItem]
    
    // widget size
    let size: WidgetSize
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("文件夹")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Spacer()
                NavigationLink(destination: NoteListView(folder: nil, showAllNotes: true).environment(noteStore)) {
                    Text("全部")
                        .font(.caption)
                }
            }
            .padding(.horizontal)
            
            if folders.isEmpty {
                Text("暂无文件夹")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ScrollView(size == .small ? .horizontal : .vertical, showsIndicators: false) {
                    if size == .small {
                        LazyHStack(spacing: 12) {
                            ForEach(folders) { folder in
                                FolderItemView(folder: folder)
                            }
                        }
                        .padding(.horizontal)
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(folders) { folder in
                                FolderItemView(folder: folder)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .frame(maxHeight: size == .fullPage ? .infinity : nil)
            }
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

struct FolderItemView: View {
    let folder: FolderItem
    @Environment(NoteStore.self) var noteStore

    var body: some View {
        NavigationLink(destination: NoteListView(folder: folder, showAllNotes: false).environment(noteStore)) {
            HStack {
                Image(systemName: folder.iconName)
                    .foregroundColor(.yellow)
                    .font(.title2)
                
                VStack(alignment: .leading) {
                    Text(folder.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("\(folder.notes.filter { !$0.isDeleted }.count) 个备忘录")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
}

struct RecentNotesWidget: View {
    @Environment(NoteStore.self) var noteStore
    @Query(
        filter: #Predicate<NoteItem> { $0.isDeleted == false },
        sort: \NoteItem.updatedAt,
        order: .reverse
    ) var notes: [NoteItem]
    
    let size: WidgetSize
    
    var displayedNotes: [NoteItem] {
        switch size {
        case .small: return Array(notes.prefix(3))
        case .medium: return Array(notes.prefix(5))
        case .large: return Array(notes.prefix(10))
        case .fullPage: return Array(notes.prefix(20))
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("最近笔记")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            
            if displayedNotes.isEmpty {
                Text("暂无笔记")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else if size == .fullPage {
                // 全屏模式：垂直列表展示
                LazyVStack(spacing: 8) {
                    ForEach(displayedNotes) { note in
                        NavigationLink(destination: NoteEditorView(note: note).environment(noteStore)) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(note.title)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .lineLimit(1)
                                        .foregroundColor(.primary)
                                    Text(note.preview)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer()
                                Text(note.updatedAt.formatted(.relative(presentation: .named)))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }
                    }
                }
                .padding(.horizontal)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(displayedNotes) { note in
                            NavigationLink(destination: NoteEditorView(note: note).environment(noteStore)) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(note.title)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .lineLimit(1)
                                        .foregroundColor(.primary)
                                    
                                    Text(note.preview)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    
                                    Spacer()
                                    
                                    Text(note.updatedAt.formatted(.relative(presentation: .named)))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding()
                                .frame(width: 140, height: 100)
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

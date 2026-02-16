import SwiftData
import SwiftUI

/// 备忘录列表主页 - 模仿 iOS 备忘录
struct NoteListView: View {
    let folder: FolderItem?
    let showAllNotes: Bool
    var initialSearchText: String = ""
    var hideSearchBar: Bool = false
    var hideBottomBar: Bool = false

    @Environment(NoteStore.self) var noteStore
    @Query(
        filter: #Predicate<NoteItem> { $0.isDeleted == false },
        sort: \NoteItem.updatedAt,
        order: .reverse
    ) var allActiveNotes: [NoteItem]
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var showMoveSheet = false
    @State private var noteToMove: NoteItem?
    @FocusState private var searchFocused: Bool

    /// 当前文件夹（或全部）的活跃备忘录
    private var scopedNotes: [NoteItem] {
        if showAllNotes {
            return allActiveNotes
        }
        return allActiveNotes.filter { $0.folder?.id == folder?.id }
    }

    /// 搜索过滤
    private var filteredNotes: [NoteItem] {
        let base = scopedNotes
        guard !searchText.isEmpty else { return base }
        return base.filter { $0.content.localizedCaseInsensitiveContains(searchText) }
    }

    private var navigationTitle: String {
        if showAllNotes { return "所有备忘录" }
        return folder?.name ?? "备忘录"
    }

    var body: some View {
        VStack(spacing: 0) {
            // 列表区域
            Group {
                if scopedNotes.isEmpty && searchText.isEmpty {
                    emptyStateView
                } else {
                    notesListView
                }
            }

            if !hideBottomBar {
                Divider()

                // 底部搜索栏 + 新建按钮
                bottomBar
            }
        }
        .navigationTitle(navigationTitle)
        .onAppear {
            if !initialSearchText.isEmpty {
                searchText = initialSearchText
                isSearching = true
            }
        }
        .onChange(of: initialSearchText) { _, newValue in
            searchText = newValue
            if !newValue.isEmpty {
                isSearching = true
            }
        }
        .sheet(isPresented: $showMoveSheet) {
            if let note = noteToMove {
                MoveToFolderSheet(note: note)
                    .environment(noteStore)
            }
        }
    }

    // MARK: - 底部栏：搜索 + 计数 + 新建

    private var bottomBar: some View {
        VStack(spacing: 0) {
            // 搜索栏（展开时显示）
            if isSearching && !hideSearchBar {
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                            .font(.subheadline)

                        TextField("搜索", text: $searchText)
                            .focused($searchFocused)
                            .font(.subheadline)

                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                    .font(.subheadline)
                            }
                        }
                    }
                    .padding(8)
                    .background(Color(.systemGray5))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    Button("取消") {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            searchText = ""
                            isSearching = false
                            searchFocused = false
                        }
                    }
                    .font(.subheadline)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // 工具栏行
            HStack {
                // 搜索按钮
                if !isSearching {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isSearching = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            searchFocused = true
                        }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 18))
                    }
                }

                Spacer()

                Text("\(scopedNotes.count) 个备忘录")
                    .font(.footnote)
                    .foregroundColor(.secondary)

                Spacer()

                NavigationLink {
                    NewNoteEditorView(folder: showAllNotes ? nil : folder)
                        .environment(noteStore)
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 18))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color(.systemBackground))
    }

    // MARK: - 空状态

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "note.text")
                .font(.system(size: 64))
                .foregroundColor(.secondary.opacity(0.6))
            Text("没有备忘录")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("点击右下角按钮创建新备忘录")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.7))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 列表

    private var notesListView: some View {
        List {
            noteRows(filteredNotes)
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func noteRows(_ notes: [NoteItem]) -> some View {
        ForEach(notes) { note in
            NavigationLink {
                NoteEditorView(note: note)
                    .environment(noteStore)
            } label: {
                NoteRowView(note: note)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    withAnimation {
                        noteStore.softDeleteNote(note)
                    }
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
            .contextMenu {
                Button {
                    noteToMove = note
                    showMoveSheet = true
                } label: {
                    Label("移动到文件夹", systemImage: "folder")
                }
                Button(role: .destructive) {
                    noteStore.softDeleteNote(note)
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        }
    }
}

// MARK: - 移动到文件夹的 Sheet

struct MoveToFolderSheet: View {
    let note: NoteItem
    @Environment(NoteStore.self) var noteStore
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FolderItem.sortOrder) var folders: [FolderItem]

    var body: some View {
        NavigationStack {
            List {
                // 无文件夹（根级）
                Button {
                    noteStore.moveNote(note, to: nil)
                    dismiss()
                } label: {
                    Label {
                        Text("所有备忘录")
                            .foregroundColor(.primary)
                    } icon: {
                        Image(systemName: "note.text")
                            .foregroundColor(.yellow)
                    }
                }

                ForEach(folders) { folder in
                    Button {
                        noteStore.moveNote(note, to: folder)
                        dismiss()
                    } label: {
                        Label {
                            Text(folder.name)
                                .foregroundColor(.primary)
                        } icon: {
                            Image(systemName: folder.iconName)
                                .foregroundColor(.yellow)
                        }
                    }
                }
            }
            .navigationTitle("移动到")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - 新建备忘录包装器（NavigationLink 目标）

/// 在 onAppear 时创建新备忘录，然后显示编辑器
struct NewNoteEditorView: View {
    let folder: FolderItem?
    @Environment(NoteStore.self) var noteStore
    @State private var note: NoteItem?

    var body: some View {
        Group {
            if let note {
                NoteEditorView(note: note)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if note == nil {
                note = noteStore.createNote(in: folder)
            }
        }
    }
}

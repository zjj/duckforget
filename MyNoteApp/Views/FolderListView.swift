import SwiftData
import SwiftUI

/// 文件夹列表 - 主页入口（仿 Apple Notes 文件夹页）
struct FolderListView: View {
    @Environment(NoteStore.self) var noteStore
    @Query(sort: \FolderItem.sortOrder) var folders: [FolderItem]
    @Query(filter: #Predicate<NoteItem> { $0.isDeleted == false })
    var allNotes: [NoteItem]
    @Query(filter: #Predicate<NoteItem> { $0.isDeleted == true })
    var trashedNotes: [NoteItem]

    @State private var showNewFolder = false
    @State private var newFolderName = ""

    var body: some View {
        NavigationStack {
            List {
                // iCloud 区域（顶部）
                Section {
                    // 所有备忘录
                    NavigationLink {
                        NoteListView(folder: nil, showAllNotes: true)
                            .environment(noteStore)
                    } label: {
                        Label {
                            HStack {
                                Text("所有备忘录")
                                Spacer()
                                Text("\(allNotes.count)")
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "note.text")
                                .foregroundColor(.yellow)
                        }
                    }
                }

                // 用户文件夹
                if !folders.isEmpty {
                    Section(header: Text("文件夹")) {
                        ForEach(folders) { folder in
                            NavigationLink {
                                NoteListView(folder: folder, showAllNotes: false)
                                    .environment(noteStore)
                            } label: {
                                Label {
                                    HStack {
                                        Text(folder.name)
                                        Spacer()
                                        Text("\(activeFolderNoteCount(folder))")
                                            .foregroundColor(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: folder.iconName)
                                        .foregroundColor(.yellow)
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    withAnimation {
                                        noteStore.deleteFolder(folder)
                                    }
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                // 最近删除
                Section {
                    NavigationLink {
                        TrashView()
                            .environment(noteStore)
                    } label: {
                        Label {
                            HStack {
                                Text("最近删除")
                                Spacer()
                                Text("\(trashedNotes.count)")
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "trash")
                                .foregroundColor(.yellow)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("文件夹")
            .toolbar {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        newFolderName = ""
                        showNewFolder = true
                    } label: {
                        HStack {
                            Image(systemName: "folder.badge.plus")
                            Text("新建文件夹")
                        }
                        .font(.subheadline)
                    }
                    Spacer()
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
    }

    private func activeFolderNoteCount(_ folder: FolderItem) -> Int {
        folder.notes.filter { !$0.isDeleted }.count
    }
}

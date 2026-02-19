import SwiftData
import SwiftUI

/// 废纸篓视图 - 显示最近删除的记录
struct TrashView: View {
    @Environment(NoteStore.self) var noteStore
    @Query(
        filter: #Predicate<NoteItem> { $0.isDeleted == true },
        sort: \NoteItem.updatedAt,
        order: .reverse
    ) var trashedNotes: [NoteItem]
    
    let appSettings = AppSettings.shared
    
    @State private var noteToDelete: NoteItem?
    @State private var showDeleteConfirmation = false
    @State private var showEmptyTrashConfirmation = false

    var body: some View {
        Group {
            if trashedNotes.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "trash")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text("废纸篓是空的")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("删除的记录将保留 \(appSettings.trashRetentionDays) 天")
                        .font(.subheadline)
                        .foregroundColor(.secondary.opacity(0.7))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(trashedNotes) { note in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(note.preview)
                                .font(.headline)
                                .lineLimit(1)
                            HStack(spacing: 8) {
                                if let deletedAt = note.deletedAt {
                                    Text("删除于 \(deletedAt.formattedShort)")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                Text(daysRemaining(note))
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                        .padding(.vertical, 3)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                noteToDelete = note
                                showDeleteConfirmation = true
                            } label: {
                                Label("永久删除", systemImage: "trash.slash")
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                withAnimation {
                                    noteStore.restoreNote(note)
                                }
                            } label: {
                                Label("恢复", systemImage: "arrow.uturn.backward")
                            }
                            .tint(.blue)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("最近删除")
        .toolbar {
            if !trashedNotes.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            withAnimation {
                                for note in trashedNotes {
                                    noteStore.restoreNote(note)
                                }
                            }
                        } label: {
                            Label("恢复全部", systemImage: "arrow.uturn.backward")
                        }

                        Button(role: .destructive) {
                            showEmptyTrashConfirmation = true
                        } label: {
                            Label("清空废纸篓", systemImage: "trash.slash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
        }
        .alert("确认永久删除", isPresented: $showDeleteConfirmation) {
            Button("取消", role: .cancel) { }
            Button("永久删除", role: .destructive) {
                if let note = noteToDelete {
                    withAnimation {
                        noteStore.permanentlyDeleteNote(note)
                    }
                    noteToDelete = nil
                }
            }
        } message: {
            Text("确定要永久删除这条笔记吗？此操作无法撤销！")
        }
        .alert("确认清空废纸篓", isPresented: $showEmptyTrashConfirmation) {
            Button("取消", role: .cancel) { }
            Button("永久删除全部", role: .destructive) {
                withAnimation {
                    noteStore.emptyTrash()
                }
            }
        } message: {
            Text("确定要清空废纸篓吗？所有已删除的笔记将被永久删除，此操作无法撤销！")
        }
    }

    private func daysRemaining(_ note: NoteItem) -> String {
        guard let deletedAt = note.deletedAt else { return "" }
        let calendar = Calendar.current
        let expiryDate = calendar.date(byAdding: .day, value: appSettings.trashRetentionDays, to: deletedAt) ?? deletedAt
        let remaining = calendar.dateComponents([.day], from: Date(), to: expiryDate).day ?? 0
        if remaining <= 0 {
            return "即将删除"
        }
        return "剩余 \(remaining) 天"
    }
}

import SwiftData
import SwiftUI

/// 废纸篓视图 - 显示最近删除的记录
struct TrashView: View {
    @Environment(NoteStore.self) var noteStore
    @Environment(\.appTheme) private var theme
    @Query var trashedNotes: [NoteItem]
    
    let appSettings = AppSettings.shared
    
    init() {
        var descriptor = FetchDescriptor<NoteItem>(
            predicate: #Predicate { $0.isDeleted == true }
        )
        descriptor.sortBy = [SortDescriptor(\.updatedAt, order: .reverse)]
        descriptor.fetchLimit = 500  // Limit to most recent 500 trashed notes
        _trashedNotes = Query(descriptor)
    }
    
    @State private var noteToDelete: NoteItem?
    @State private var showDeleteConfirmation = false
    @State private var showEmptyTrashConfirmation = false
    @State private var showTrashActionsDialog = false

    var body: some View {
        Group {
            if trashedNotes.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "trash")
                        .font(.system(size: 64))
                        .foregroundColor(theme.colors.secondaryText.opacity(0.6))
                        .accessibilityHidden(true)
                    Text("废纸篓是空的")
                        .font(.title2)
                        .foregroundColor(theme.colors.secondaryText)
                    Text("删除的记录将保留 \(appSettings.trashRetentionDays) 天")
                        .font(.subheadline)
                        .foregroundColor(theme.colors.secondaryText.opacity(0.7))
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
                                        .foregroundColor(theme.colors.secondaryText)
                                }
                                Text(daysRemaining(note))
                                    .font(.caption)
                                    .foregroundColor(theme.colors.accent)
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
                            .tint(theme.colors.accent)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(theme.colors.background.ignoresSafeArea())
        .tint(theme.colors.accent)
        .navigationTitle("最近删除")
        .toolbarBackground(theme.colors.surface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            if !trashedNotes.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showTrashActionsDialog = true
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 20))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("废纸篓操作")
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
        .confirmationDialog("废纸篓", isPresented: $showTrashActionsDialog) {
            Button("恢复全部记录") {
                withAnimation {
                    for note in trashedNotes {
                        noteStore.restoreNote(note)
                    }
                }
            }

            Button("清空废纸篓", role: .destructive) {
                showEmptyTrashConfirmation = true
            }

            Button("取消", role: .cancel) {}
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

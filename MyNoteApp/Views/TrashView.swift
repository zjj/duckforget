import SwiftData
import SwiftUI

/// 回收站视图 - 显示最近删除的备忘录
struct TrashView: View {
    @Environment(NoteStore.self) var noteStore
    @Query(
        filter: #Predicate<NoteItem> { $0.isDeleted == true },
        sort: \NoteItem.updatedAt,
        order: .reverse
    ) var trashedNotes: [NoteItem]

    var body: some View {
        Group {
            if trashedNotes.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "trash")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text("回收站是空的")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("删除的备忘录将保留 30 天")
                        .font(.subheadline)
                        .foregroundColor(.secondary.opacity(0.7))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(trashedNotes) { note in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(note.title)
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
                            Text(note.preview)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        .padding(.vertical, 3)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                withAnimation {
                                    noteStore.permanentlyDeleteNote(note)
                                }
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
                            withAnimation {
                                noteStore.emptyTrash()
                            }
                        } label: {
                            Label("清空回收站", systemImage: "trash.slash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }

    private func daysRemaining(_ note: NoteItem) -> String {
        guard let deletedAt = note.deletedAt else { return "" }
        let calendar = Calendar.current
        let expiryDate = calendar.date(byAdding: .day, value: 30, to: deletedAt) ?? deletedAt
        let remaining = calendar.dateComponents([.day], from: Date(), to: expiryDate).day ?? 0
        if remaining <= 0 {
            return "即将删除"
        }
        return "剩余 \(remaining) 天"
    }
}

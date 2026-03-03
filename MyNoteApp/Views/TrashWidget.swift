import SwiftUI
import SwiftData

// MARK: - 废纸篓组件

struct TrashWidget: View {
    @Environment(NoteStore.self) var noteStore
    @Query var trashedNotes: [NoteItem]
    
    let size: WidgetSize
    let appSettings = AppSettings.shared
    @Environment(\.appTheme) private var theme
    
    init(size: WidgetSize) {
        self.size = size
        var descriptor = FetchDescriptor<NoteItem>(
            predicate: #Predicate { $0.isDeleted == true }
        )
        descriptor.sortBy = [SortDescriptor(\.deletedAt, order: .reverse)]
        descriptor.fetchLimit = 100  // Limit to most recent 100 trashed notes
        _trashedNotes = Query(descriptor)
    }
    
    var displayedNotes: [NoteItem] {
        switch size {
        case .small: return Array(trashedNotes.prefix(3))
        case .medium: return Array(trashedNotes.prefix(5))
        case .large: return Array(trashedNotes.prefix(10))
        case .fullPage: return trashedNotes
        }
    }
    
    var body: some View {
        if size == .fullPage {
            // 全屏模式显示完整的废纸篓页面
            TrashDetailPage()
                .environment(noteStore)
        } else {
            // 小组件模式：简单卡片，点击跳转
            ZStack {
                NavigationLink(destination: TrashDetailPage().environment(noteStore)) {
                    EmptyView()
                }
                .opacity(0)

                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.12))
                            .frame(width: 40, height: 40)
                        Image(systemName: "trash")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Color.orange)
                            .symbolRenderingMode(.hierarchical)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("废纸篓")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)
                        Text("\(trashedNotes.count) 条记录")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.45))
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(theme.colors.surface)
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
                .shadow(color: theme.colors.shadow, radius: 6, x: 0, y: 2)
            }
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

// MARK: - 废纸篓卡片按钮（无 chevron）

struct TrashCardButton: View {
    let trashedCount: Int
    @Binding var showTrashDetail: Bool
    @Environment(\.appTheme) private var theme
    
    var body: some View {
        Button {
            showTrashDetail = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "trash")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.orange)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("废纸篓")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("废纸篓（\(trashedCount)条）")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(theme.colors.surface)
            .cornerRadius(16)
            .shadow(color: theme.colors.shadow, radius: 6, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }
}

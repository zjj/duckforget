import SwiftData
import SwiftUI
import CoreSpotlight

@main
struct MyNoteAppApp: App {
    let container: ModelContainer
    let noteStore: NoteStore

    /// Non-nil when the persistent store could not be opened even after a
    /// lightweight-migration attempt.  The root view shows a blocking alert
    /// so the user can decide whether to erase data or quit.
    let migrationError: String?

    @State private var toolbarSettings = ToolbarSettings()
    @StateObject private var deepLinkHandler = DeepLinkHandler()

    init() {
        let schema = Schema([NoteItem.self, AttachmentItem.self, TagItem.self])
        let config = ModelConfiguration(schema: schema)

        // ── Attempt 1: normal open (handles additive / lightweight migrations) ──
        if let result = try? ModelContainer(for: schema, configurations: [config]) {
            self.container = result
            self.noteStore = NoteStore(modelContext: result.mainContext)
            self.migrationError = nil
            return
        }

        // ── Attempt 2: fall back to an in-memory container so the app stays
        //    alive and can show the user a recovery alert. ──
        let fallback = try! ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        self.container = fallback
        self.noteStore = NoteStore(modelContext: fallback.mainContext)

        // Capture a human-readable description for the alert.
        var desc = "数据库与当前 Schema 不兼容"
        if let url = try? ModelConfiguration(schema: schema).url {
            desc += "（\(url.lastPathComponent)）"
        }
        self.migrationError = desc
    }

    var body: some Scene {
        WindowGroup {
            DashboardContainerView()
                .modelContainer(container)
                .environment(noteStore)
                .environment(toolbarSettings)
                .environmentObject(deepLinkHandler)
                .onOpenURL { url in
                    if url.scheme == "mynoteapp" && url.host == "create-note" {
                        deepLinkHandler.createNewNote()
                    }
                }
                .onContinueUserActivity(CSSearchableItemActionType) { userActivity in
                    if let uniqueIdentifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                       let noteID = UUID(uuidString: uniqueIdentifier) {
                        deepLinkHandler.openNote(id: noteID, autoEdit: false)
                    }
                }
                .modifier(MigrationErrorModifier(migrationError: migrationError))
        }
    }
}

// MARK: - Migration Error Alert

/// Surfaces a blocking alert when the persistent store could not be opened.
/// The user can choose to permanently erase the store or quit the app.
private struct MigrationErrorModifier: ViewModifier {
    let migrationError: String?
    @State private var showAlert = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                if migrationError != nil { showAlert = true }
            }
            .alert("数据库无法打开", isPresented: $showAlert) {
                Button("永久删除并重置", role: .destructive) {
                    eraseAndRelaunch()
                }
                Button("退出 App", role: .cancel) {
                    exit(0)
                }
            } message: {
                Text("""
                \(migrationError ?? "未知错误")

                当前笔记数据暂时无法读取。您可以选择：
                • 永久删除数据库并以全新状态启动
                • 退出 App，待下次更新后再试

                如有重要数据，建议先退出，联系开发者寻求恢复帮助。
                """)
            }
    }

    private func eraseAndRelaunch() {
        let schema = Schema([NoteItem.self, AttachmentItem.self, TagItem.self])
        guard let storeURL = try? ModelConfiguration(schema: schema).url else { return }
        let fm = FileManager.default
        for ext in ["", "-shm", "-wal"] {
            let u = storeURL.deletingPathExtension()
                .appendingPathExtension(ext.isEmpty ? "store" : "store\(ext)")
            try? fm.removeItem(at: u)
        }
        // Also try the exact URL reported by the config
        try? fm.removeItem(at: storeURL)
        exit(0)   // user relaunches manually; fresh init() will succeed
    }
}

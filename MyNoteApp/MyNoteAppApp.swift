import SwiftData
import SwiftUI
import CoreSpotlight

@main
struct MyNoteAppApp: App {
    let container: ModelContainer
    let noteStore: NoteStore
    @StateObject private var toolbarSettings = ToolbarSettings()
    @StateObject private var deepLinkHandler = DeepLinkHandler()

    init() {
        let schema = Schema([NoteItem.self, AttachmentItem.self, TagItem.self])
        let config = ModelConfiguration(schema: schema)

        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            self.container = container
            self.noteStore = NoteStore(modelContext: container.mainContext)
        } catch {
            // Schema changed — remove old store and retry
            let storeURL = config.url
            let fm = FileManager.default
            let related = [
                storeURL,
                storeURL.deletingPathExtension().appendingPathExtension("store-shm"),
                storeURL.deletingPathExtension().appendingPathExtension("store-wal"),
            ]
            for url in related {
                try? fm.removeItem(at: url)
            }
            do {
                let container = try ModelContainer(for: schema, configurations: [config])
                self.container = container
                self.noteStore = NoteStore(modelContext: container.mainContext)
            } catch {
                fatalError("Failed to create ModelContainer after reset: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            FolderListView()
                .modelContainer(container)
                .environment(noteStore)
                .environmentObject(toolbarSettings)
                .environmentObject(deepLinkHandler)
                .onOpenURL { url in
                    if url.scheme == "mynoteapp" && url.host == "create-note" {
                        deepLinkHandler.createNewNote()
                    }
                }
                .onContinueUserActivity(CSSearchableItemActionType) { userActivity in
                    if let uniqueIdentifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                       let noteID = UUID(uuidString: uniqueIdentifier) {
                        deepLinkHandler.openNote(id: noteID)
                    }
                }
                .onAppear {
                    // 应用启动时重新索引所有笔记
                    DispatchQueue.global(qos: .utility).async {
                        noteStore.reindexAllNotes()
                    }
                }
        }
    }
}

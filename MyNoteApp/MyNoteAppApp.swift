import SwiftData
import SwiftUI

@main
struct MyNoteAppApp: App {
    let container: ModelContainer
    let noteStore: NoteStore
    @StateObject private var toolbarSettings = ToolbarSettings()

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
        }
    }
}

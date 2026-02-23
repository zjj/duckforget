import SwiftUI
import SwiftData

/// Size-class aware root view:
/// • iPad / large window (.regular horizontal size class) → `NavigationSplitView`
///   with a NoteList sidebar and a NoteView detail pane.
/// • iPhone / compact window → existing `DashboardContainerView`.
struct AdaptiveRootView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(NoteStore.self) private var noteStore
    @EnvironmentObject private var deepLinkHandler: DeepLinkHandler

    /// The note currently shown in the detail column (iPad only).
    @State private var selectedNote: NoteItem?

    var body: some View {
        if horizontalSizeClass == .regular {
            iPadSplitView
        } else {
            DashboardContainerView()
        }
    }

    // MARK: - iPad Split View

    private var iPadSplitView: some View {
        NavigationSplitView {
            NoteListView(showAllNotes: true, splitViewSelection: $selectedNote)
                .navigationTitle("记录")
                .navigationBarTitleDisplayMode(.large)
        } detail: {
            if let note = selectedNote {
                NavigationStack {
                    NoteView(note: note, startInEditMode: false)
                        .environment(noteStore)
                        .navigationBarTitleDisplayMode(.inline)
                }
            } else {
                ContentUnavailableView(
                    "选择一条记录",
                    systemImage: "note.text",
                    description: Text("从左侧列表中选择一条记录查看或编辑")
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
        // Mirror deep-link handling from DashboardContainerView
        .onChange(of: deepLinkHandler.noteToOpen) { _, noteID in
            guard let noteID else { return }
            let descriptor = FetchDescriptor<NoteItem>(
                predicate: #Predicate { $0.id == noteID && !$0.isDeleted }
            )
            if let notes = try? noteStore.modelContext.fetch(descriptor),
               let note = notes.first {
                selectedNote = note
                deepLinkHandler.reset()
            }
        }
        .onChange(of: deepLinkHandler.shouldCreateNewNote) { _, shouldCreate in
            guard shouldCreate else { return }
            selectedNote = noteStore.createNote()
            deepLinkHandler.reset()
        }
    }
}

import Foundation
import SwiftUI
import Combine

/// 处理深度链接（如从 Spotlight 打开笔记）
class DeepLinkHandler: ObservableObject {
    @Published var noteToOpen: UUID?
    @Published var shouldCreateNewNote: Bool = false
    @Published var openInEditMode: Bool = false
    
    func openNote(id: UUID, autoEdit: Bool = true) {
        noteToOpen = id
        openInEditMode = autoEdit
    }
    
    func createNewNote() {
        shouldCreateNewNote = true
    }

    func reset() {
        noteToOpen = nil
        shouldCreateNewNote = false
        openInEditMode = false
    }
}

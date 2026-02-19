import Foundation
import SwiftUI
import Combine

/// 处理深度链接（如从 Spotlight 打开笔记）
class DeepLinkHandler: ObservableObject {
    @Published var noteToOpen: UUID?
    @Published var shouldCreateNewNote: Bool = false
    
    func openNote(id: UUID) {
        noteToOpen = id
    }
    
    func createNewNote() {
        shouldCreateNewNote = true
    }

    func reset() {
        noteToOpen = nil
        shouldCreateNewNote = false
    }
}

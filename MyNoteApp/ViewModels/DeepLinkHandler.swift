import Foundation
import SwiftUI

/// 处理深度链接（如从 Spotlight 打开笔记）
class DeepLinkHandler: ObservableObject {
    @Published var noteToOpen: UUID?
    
    func openNote(id: UUID) {
        noteToOpen = id
    }
    
    func reset() {
        noteToOpen = nil
    }
}

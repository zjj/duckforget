import Foundation
import Combine

/// 管理笔记编辑的撤销/重做操作，支持文本和附件的变化
class UndoRedoManager: ObservableObject {
    // MARK: - 历史记录
    
    /// 最大历史记录数量
    private let maxHistoryCount = 20
    
    /// 撤销栈
    private var undoStack: [EditAction] = []
    
    /// 重做栈
    private var redoStack: [EditAction] = []
    
    // MARK: - 状态
    
    /// 是否可以撤销
    var canUndo: Bool {
        !undoStack.isEmpty
    }
    
    /// 是否可以重做
    var canRedo: Bool {
        !redoStack.isEmpty
    }
    
    // MARK: - 编辑操作类型
    
    enum EditAction: Codable {
        case textChange(previousText: String, newText: String)
        case attachmentAdded(attachmentID: UUID)
        case attachmentDeleted(attachmentID: UUID)
    }
    
    // MARK: - 历史数据结构（用于序列化）
    
    private struct HistoryData: Codable {
        var undoStack: [EditAction]
        var redoStack: [EditAction]
    }
    
    // MARK: - 公开方法
    
    /// 记录一个编辑操作
    func recordAction(_ action: EditAction) {
        // 添加到撤销栈
        undoStack.append(action)
        
        // 限制撤销栈大小
        if undoStack.count > maxHistoryCount {
            undoStack.removeFirst()
        }
        
        // 清空重做栈（新的编辑会清除原有的重做历史）
        redoStack.removeAll()
    }
    
    /// 撤销操作，返回要执行的反向操作
    func undo() -> EditAction? {
        guard let action = undoStack.popLast() else {
            return nil
        }
        
        // 将操作移到重做栈
        redoStack.append(action)
        
        // 限制重做栈大小
        if redoStack.count > maxHistoryCount {
            redoStack.removeFirst()
        }
        
        return action
    }
    
    /// 重做操作，返回要执行的操作
    func redo() -> EditAction? {
        guard let action = redoStack.popLast() else {
            return nil
        }
        
        // 将操作移回撤销栈
        undoStack.append(action)
        
        return action
    }
    
    /// 清空所有历史记录
    func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
    
    /// 仅清空撤销栈（用于新建笔记初始化后清理）
    func clearUndoStack() {
        undoStack.removeAll()
    }
    
    // MARK: - 持久化
    
    /// 将历史记录序列化为Data
    func serializeHistory() -> Data? {
        let historyData = HistoryData(undoStack: undoStack, redoStack: redoStack)
        return try? JSONEncoder().encode(historyData)
    }
    
    /// 从Data加载历史记录
    func loadHistory(from data: Data) {
        guard let historyData = try? JSONDecoder().decode(HistoryData.self, from: data) else {
            return
        }
        undoStack = historyData.undoStack
        redoStack = historyData.redoStack
    }
}

import SwiftUI

enum ToolbarItemType: String, CaseIterable, Identifiable, Codable {
    case camera
    case photo
    case audio
    case folder
    case location
    case drawing
    case scanText
    case scanDocument
    case markdown
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .camera: return "camera"
        case .photo: return "photo.on.rectangle"
        case .audio: return "waveform"
        case .folder: return "folder"
        case .location: return "mappin.and.ellipse"
        case .drawing: return "pencil.tip.crop.circle"
        case .scanText: return "text.viewfinder"
        case .scanDocument: return "doc.viewfinder"
        case .markdown: return "number"
        }
    }
    
    var title: String {
        switch self {
        case .camera: return "拍照/录像"
        case .photo: return "相册"
        case .audio: return "录音"
        case .folder: return "文件"
        case .location: return "位置"
        case .drawing: return "手绘"
        case .scanText: return "文字识别"
        case .scanDocument: return "文档扫描"
        case .markdown: return "Markdown"
        }
    }
}

import Foundation
import SwiftData

// MARK: - 附件类型

enum AttachmentType: String, Codable {
    case photo
    case video
    case scannedDocument
    case scannedText
    case audio
    case file

    var iconName: String {
        switch self {
        case .photo: return "photo"
        case .video: return "video.fill"
        case .scannedDocument: return "doc.viewfinder"
        case .scannedText: return "text.viewfinder"
        case .audio: return "waveform"
        case .file: return "doc.fill"
        }
    }

    var displayName: String {
        switch self {
        case .photo: return "照片"
        case .video: return "视频"
        case .scannedDocument: return "扫描文稿"
        case .scannedText: return "扫描文本"
        case .audio: return "录音"
        case .file: return "文件"
        }
    }
}

// MARK: - 附件模型

@Model
final class AttachmentItem {
    var id: UUID
    var type: AttachmentType
    var fileName: String
    var thumbnailFileName: String?
    var createdAt: Date
    var note: NoteItem?

    init(
        id: UUID = UUID(),
        type: AttachmentType,
        fileName: String,
        thumbnailFileName: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.fileName = fileName
        self.thumbnailFileName = thumbnailFileName
        self.createdAt = createdAt
    }
}

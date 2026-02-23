import Foundation
import SwiftData
import UIKit

// MARK: - Export Format

enum ExportFormat: CaseIterable, Identifiable {
    case pdf
    case txt
    case markdown
    case zip

    var id: Self { self }

    var displayName: String {
        switch self {
        case .pdf:      return "PDF"
        case .txt:      return "纯文本（.txt）"
        case .markdown: return "Markdown（.md）"
        case .zip:      return "ZIP 归档（含附件）"
        }
    }

    var fileExtension: String {
        switch self {
        case .pdf:      return "pdf"
        case .txt:      return "txt"
        case .markdown: return "md"
        case .zip:      return "zip"
        }
    }

    var systemImage: String {
        switch self {
        case .pdf:      return "doc.richtext"
        case .txt:      return "doc.plaintext"
        case .markdown: return "doc.text"
        case .zip:      return "doc.zipper"
        }
    }
}

// MARK: - Export Error

enum ExportError: LocalizedError {
    case encodingFailed
    case fileWriteFailed(Error)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:          return "内容编码失败"
        case .fileWriteFailed(let e):  return "文件写入失败：\(e.localizedDescription)"
        }
    }
}

// MARK: - Export Service

final class ExportService {
    private let noteStore: NoteStore

    init(noteStore: NoteStore) {
        self.noteStore = noteStore
    }

    // MARK: - Export Snapshots

    /// Plain-value snapshot of all data needed to export one note.
    /// Must be created on the ModelContext's actor (main actor), then it is safe
    /// to pass across task boundaries and use from any thread / actor.
    private struct NoteExportSnapshot {
        let id: UUID
        let content: String
        let preview: String
        let createdAt: Date
        let updatedAt: Date
        let tagNames: [String]
        let attachments: [AttachmentExportSnapshot]
    }

    private struct AttachmentExportSnapshot {
        let id: UUID
        let type: AttachmentType
        let fileName: String
        let thumbnailFileName: String?
        let fileURL: URL
        let thumbnailURL: URL?
    }

    /// Captures all values needed for export from SwiftData model objects.
    /// Call this on the same actor/thread as the ModelContext (main actor).
    private func makeSnapshot(note: NoteItem) -> NoteExportSnapshot {
        let sorted = noteStore.getAttachments(for: note)
        return NoteExportSnapshot(
            id: note.id,
            content: note.content,
            preview: note.preview,
            createdAt: note.createdAt,
            updatedAt: note.updatedAt,
            tagNames: note.tags.map { $0.name },
            attachments: sorted.map { att in
                AttachmentExportSnapshot(
                    id: att.id,
                    type: att.type,
                    fileName: att.fileName,
                    thumbnailFileName: att.thumbnailFileName,
                    fileURL: noteStore.attachmentURL(for: att),
                    thumbnailURL: noteStore.thumbnailURL(for: att)
                )
            }
        )
    }

    /// 将笔记导出为指定格式，返回临时文件 URL（用完记得删除）
    func export(note: NoteItem, format: ExportFormat) throws -> URL {
        // Capture all required values from SwiftData model objects up front
        // (caller must be on the ModelContext's actor — main actor — at this point).
        // The private export methods then work exclusively with plain value types
        // and are safe even if moved to Task.detached in the future.
        let snapshot = makeSnapshot(note: note)
        switch format {
        case .pdf:      return try exportPDF(note: snapshot)
        case .txt:      return try exportTXT(note: snapshot)
        case .markdown: return try exportMarkdown(note: snapshot)
        case .zip:      return try exportZIP(note: snapshot)
        }
    }

    // MARK: - PDF

    private func exportPDF(note: NoteExportSnapshot) throws -> URL {
        // PDF 中不包含录音和视频附件
        let excludedTypes: Set<AttachmentType> = [.audio, .video]
        let pdfAttachments = note.attachments.filter { !excludedTypes.contains($0.type) }

        let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8) // A4
        let margin: CGFloat = 50
        let contentWidth = pageRect.width - margin * 2
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let pdfData = renderer.pdfData { ctx in
            ctx.beginPage()
            var y: CGFloat = margin

            // ---- 日期 ----
            let dateStr = note.updatedAt.formatted(date: .abbreviated, time: .shortened)
            let metaAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10, weight: .regular),
                .foregroundColor: UIColor.systemGray
            ]
            (dateStr as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: metaAttrs)
            y += 18

            // ---- 标签 ----
            if !note.tagNames.isEmpty {
                let tagsStr = note.tagNames.map { "#\($0)" }.joined(separator: "  ")
                let tagAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 11, weight: .medium),
                    .foregroundColor: UIColor.systemBlue
                ]
                let tagRect = CGRect(x: margin, y: y, width: contentWidth, height: 20)
                (tagsStr as NSString).draw(in: tagRect, withAttributes: tagAttrs)
                y += 22
            }

            // ---- 分隔线 ----
            let divPath = UIBezierPath()
            divPath.move(to: CGPoint(x: margin, y: y))
            divPath.addLine(to: CGPoint(x: pageRect.width - margin, y: y))
            UIColor.systemGray4.setStroke()
            divPath.lineWidth = 0.5
            divPath.stroke()
            y += 14

            // ---- 正文（支持自动换页，渲染 Markdown 格式）----
            // 注意：CTFrameDraw 使用 Core Graphics 原生坐标系（原点在左下，Y 轴向上），
            // 而 UIGraphicsPDFRenderer 上下文已对 Y 轴做了翻转（UIKit 坐标系）。
            // 因此需要：
            //   1. 在每次 CTFrameDraw 前 save/翻转/restore CG 上下文；
            //   2. 将绘制区域 (UIKit rect) 转换为 CG 坐标系中对应的 rect。
            let attrContent = markdownAttributedString(for: note.content)

            let framesetter = CTFramesetterCreateWithAttributedString(attrContent)
            var charIndex = 0
            while charIndex < attrContent.length {
                let availableHeight = pageRect.height - y - margin

                // CG 坐标系中的等价区域：
                //   UIKit bottom edge (y + availableHeight = pageH - margin)
                //     → CG y = pageH - (pageH - margin) = margin
                //   height 不变
                let cgRect = CGRect(x: margin, y: margin,
                                    width: contentWidth, height: availableHeight)
                let path = CGPath(rect: cgRect, transform: nil)
                let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(charIndex, 0), path, nil)

                // 翻转上下文：undo UIKit flip → 恢复 CG 原生坐标（原点左下，Y 向上）
                let cgCtx = ctx.cgContext
                cgCtx.saveGState()
                cgCtx.translateBy(x: 0, y: pageRect.height)
                cgCtx.scaleBy(x: 1, y: -1)
                // 重置 textMatrix：NSString.draw(in:) 等 UIKit 绘制方法会修改 textMatrix
                // 以补偿 UIKit 坐标系翻转，CTFrameDraw 在 CG 坐标系下需要 identity textMatrix，
                // 否则文字会被二次翻转导致镜像。
                cgCtx.textMatrix = .identity
                CTFrameDraw(frame, cgCtx)
                cgCtx.restoreGState()

                let visibleRange = CTFrameGetVisibleStringRange(frame)
                if visibleRange.length == 0 { break }
                charIndex += visibleRange.length

                if charIndex < attrContent.length {
                    ctx.beginPage()
                    y = margin
                }
            }
            y = pageRect.height - margin // reset to bottom of page for image logic below

            // ---- 图片附件（photo / drawing / scannedDocument）----
            let imageTypes: Set<AttachmentType> = [.photo, .drawing, .scannedDocument]
            let imageAttachments = pdfAttachments.filter { imageTypes.contains($0.type) }

            if !imageAttachments.isEmpty {
                ctx.beginPage()
                var iy: CGFloat = margin

                for attachment in imageAttachments {
                    let url = attachment.fileURL
                    guard let imgData = try? Data(contentsOf: url),
                          let img = UIImage(data: imgData) else { continue }

                    // 修正图片方向，防止 EXIF 旋转导致镜像或方向错误
                    let normalizedImg = Self.normalizeImageOrientation(img)

                    // 宽度撑满内容区，高度按原始比例等比缩放
                    let aspect = normalizedImg.size.height / max(normalizedImg.size.width, 1)
                    let imgW = contentWidth
                    let imgH = contentWidth * aspect

                    if iy + imgH > pageRect.height - margin {
                        ctx.beginPage()
                        iy = margin
                    }

                    let imgRect = CGRect(x: margin, y: iy, width: imgW, height: imgH)
                    normalizedImg.draw(in: imgRect)
                    iy += imgH + 14
                }
            }

            // ---- 位置附件（location）----
            let locationAttachments = pdfAttachments.filter { $0.type == .location }

            if !locationAttachments.isEmpty {
                // 如果前面没有图片附件，需要新开一页
                if imageAttachments.isEmpty {
                    ctx.beginPage()
                }
                var ly: CGFloat = imageAttachments.isEmpty ? margin : (pageRect.height - margin) // 如果有图片页的话换页
                if !imageAttachments.isEmpty {
                    ctx.beginPage()
                    ly = margin
                }

                let locationTitleAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 11, weight: .medium),
                    .foregroundColor: UIColor.systemGray
                ]
                let coordAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                    .foregroundColor: UIColor.systemGray2
                ]

                for attachment in locationAttachments {
                    // 尝试渲染位置缩略图
                    if let thumbURL = attachment.thumbnailURL,
                       let thumbData = try? Data(contentsOf: thumbURL),
                       let thumbImg = UIImage(data: thumbData) {
                        let normalizedThumb = Self.normalizeImageOrientation(thumbImg)
                        let aspect = normalizedThumb.size.height / max(normalizedThumb.size.width, 1)
                        let imgW = contentWidth
                        let imgH = contentWidth * aspect

                        if ly + imgH + 30 > pageRect.height - margin {
                            ctx.beginPage()
                            ly = margin
                        }

                        let imgRect = CGRect(x: margin, y: ly, width: imgW, height: imgH)
                        normalizedThumb.draw(in: imgRect)
                        ly += imgH + 4
                    }

                    // 解析并渲染坐标文字
                    let dataURL = attachment.fileURL
                    if let jsonData = try? Data(contentsOf: dataURL),
                       let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                       let lat = json["latitude"] as? Double,
                       let lon = json["longitude"] as? Double {
                        let coordStr = String(format: "📍 %.6f, %.6f", lat, lon)
                        if ly + 20 > pageRect.height - margin {
                            ctx.beginPage()
                            ly = margin
                        }
                        (coordStr as NSString).draw(at: CGPoint(x: margin, y: ly), withAttributes: coordAttrs)
                        ly += 18
                    } else {
                        ("📍 位置" as NSString).draw(at: CGPoint(x: margin, y: ly), withAttributes: locationTitleAttrs)
                        ly += 18
                    }
                    ly += 10
                }
            }
        }

        return try writeTempFile(data: pdfData, name: creationFilename(for: note) + ".pdf")
    }

    // MARK: - Markdown → NSAttributedString (for PDF)

    private func markdownAttributedString(for content: String) -> NSAttributedString {
        let baseFontSize: CGFloat = 13
        let bodyFont  = UIFont.systemFont(ofSize: baseFontSize)
        let codeFont  = UIFont.monospacedSystemFont(ofSize: baseFontSize * 0.9, weight: .regular)
        let h1Font    = UIFont.systemFont(ofSize: baseFontSize * 1.6,  weight: .bold)
        let h2Font    = UIFont.systemFont(ofSize: baseFontSize * 1.35, weight: .bold)
        let h3Font    = UIFont.systemFont(ofSize: baseFontSize * 1.15, weight: .semibold)
        let bodyColor = UIColor.black
        let grayColor = UIColor.systemGray

        let result = NSMutableAttributedString()
        let lines   = content.components(separatedBy: "\n")
        var inCodeBlock = false
        var codeLines: [String] = []

        func appendLine(_ text: String, font: UIFont, color: UIColor = bodyColor) {
            result.append(NSAttributedString(
                string: text + "\n",
                attributes: [.font: font, .foregroundColor: color]
            ))
        }

        // 剥离行内 Markdown 语法，保留文字
        func stripInline(_ text: String) -> String {
            var s = text
            s = s.replacingOccurrences(of: "\\*\\*(.+?)\\*\\*",  with: "$1", options: .regularExpression)
            s = s.replacingOccurrences(of: "\\*(.+?)\\*",         with: "$1", options: .regularExpression)
            s = s.replacingOccurrences(of: "~~(.+?)~~",           with: "$1", options: .regularExpression)
            s = s.replacingOccurrences(of: "`([^`]+)`",           with: "$1", options: .regularExpression)
            s = s.replacingOccurrences(of: "!\\[.*?\\]\\(.*?\\)", with: "",   options: .regularExpression)
            s = s.replacingOccurrences(of: "\\[(.+?)\\]\\(.*?\\)",with: "$1", options: .regularExpression)
            return s
        }

        for line in lines {
            // 代码块围栏
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                if inCodeBlock {
                    result.append(NSAttributedString(
                        string: codeLines.joined(separator: "\n") + "\n",
                        attributes: [.font: codeFont, .foregroundColor: grayColor]
                    ))
                    codeLines = []; inCodeBlock = false
                } else {
                    inCodeBlock = true
                }
                continue
            }
            if inCodeBlock { codeLines.append(line); continue }

            // 块级元素
            if      line.hasPrefix("### ") { appendLine(stripInline(String(line.dropFirst(4))), font: h3Font) }
            else if line.hasPrefix("## ")  { appendLine(stripInline(String(line.dropFirst(3))), font: h2Font) }
            else if line.hasPrefix("# ")   { appendLine(stripInline(String(line.dropFirst(2))), font: h1Font) }
            else if line.hasPrefix("> ")   { appendLine("│ " + stripInline(String(line.dropFirst(2))), font: bodyFont, color: grayColor) }
            else if line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") {
                appendLine("☑ " + stripInline(String(line.dropFirst(6))), font: bodyFont)
            } else if line.hasPrefix("- [ ] ") {
                appendLine("☐ " + stripInline(String(line.dropFirst(6))), font: bodyFont)
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                appendLine("• " + stripInline(String(line.dropFirst(2))), font: bodyFont)
            } else {
                appendLine(stripInline(line), font: bodyFont)
            }
        }

        // 冲刷未关闭的代码块
        if !codeLines.isEmpty {
            result.append(NSAttributedString(
                string: codeLines.joined(separator: "\n") + "\n",
                attributes: [.font: codeFont, .foregroundColor: grayColor]
            ))
        }
        return result
    }

    // MARK: - TXT

    private func exportTXT(note: NoteExportSnapshot) throws -> URL {
        guard let data = note.content.data(using: .utf8) else {
            throw ExportError.encodingFailed
        }
        return try writeTempFile(data: data, name: creationFilename(for: note) + ".txt")
    }

    // MARK: - Markdown

    private func exportMarkdown(note: NoteExportSnapshot) throws -> URL {
        var md = ""

        // YAML front-matter（包含标签和日期）
        if !note.tagNames.isEmpty {
            let iso = ISO8601DateFormatter()
            md += "---\n"
            md += "tags: \(note.tagNames.joined(separator: ", "))\n"
            md += "date: \(iso.string(from: note.updatedAt))\n"
            md += "---\n\n"
        }

        md += note.content

        guard let data = md.data(using: .utf8) else {
            throw ExportError.encodingFailed
        }
        return try writeTempFile(data: data, name: creationFilename(for: note) + ".md")
    }

    // MARK: - ZIP

    private func exportZIP(note: NoteExportSnapshot) throws -> URL {
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmpDir) }

        let assetsDir = tmpDir.appendingPathComponent("assets")
        try fm.createDirectory(at: assetsDir, withIntermediateDirectories: true)

        // ---- 复制附件，处理文件名冲突 ----
        let allAttachments = note.attachments
        var fileMapping: [(attachment: AttachmentExportSnapshot, destName: String)] = []
        var usedNames = Set<String>()

        for attachment in allAttachments {
            var destName = attachment.fileName
            if usedNames.contains(destName) {
                let ext  = (destName as NSString).pathExtension
                let base = (destName as NSString).deletingPathExtension
                var counter = 2
                repeat {
                    destName = "\(base)_\(counter).\(ext)"
                    counter += 1
                } while usedNames.contains(destName)
            }
            usedNames.insert(destName)
            fileMapping.append((attachment, destName))

            let src = attachment.fileURL
            if (try? src.checkResourceIsReachable()) == true {
                try? fm.copyItem(at: src, to: assetsDir.appendingPathComponent(destName))
            }

            // 位置附件：额外复制缩略图（地图截图）
            if attachment.type == .location,
               let thumbName = attachment.thumbnailFileName,
               let thumbSrc = attachment.thumbnailURL {
                if (try? thumbSrc.checkResourceIsReachable()) == true {
                    try? fm.copyItem(at: thumbSrc, to: assetsDir.appendingPathComponent(thumbName))
                }
            }
        }

        // ---- meta.json ----
        let meta = buildMeta(note: note, fileMapping: fileMapping)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let metaData = try encoder.encode(meta)
        try metaData.write(to: tmpDir.appendingPathComponent("meta.json"))

        // ---- index.html ----
        let htmlString = buildHTML(note: note, fileMapping: fileMapping)
        guard let htmlData = htmlString.data(using: .utf8) else { throw ExportError.encodingFailed }
        try htmlData.write(to: tmpDir.appendingPathComponent("index.html"))

        // ---- Collect zip entries ----
        var entries: [ZipEntry] = []

        if let data = try? Data(contentsOf: tmpDir.appendingPathComponent("meta.json")) {
            entries.append(ZipEntry(path: "meta.json", data: data))
        }
        if let data = try? Data(contentsOf: tmpDir.appendingPathComponent("index.html")) {
            entries.append(ZipEntry(path: "index.html", data: data))
        }
        for m in fileMapping {
            let assetURL = assetsDir.appendingPathComponent(m.destName)
            if let data = try? Data(contentsOf: assetURL) {
                entries.append(ZipEntry(path: "assets/\(m.destName)", data: data))
            }
        }

        let zipData = buildZip(entries: entries)
        return try writeTempFile(data: zipData, name: creationFilename(for: note) + ".zip")
    }

    // MARK: - Export All Notes

    /// 导出符合条件的笔记，打包为一个 ZIP 文件。
    /// - Parameters:
    ///   - startDate: 创建时间下限（包含当日，nil 表示不限）
    ///   - endDate:   创建时间上限（包含当日 23:59:59，nil 表示不限）
    ///   - tag:       标签过滤（nil 表示所有标签）
    ///   - progress:  进度回调 (已处理笔记数, 笔记总数)，始终在 @MainActor 上调用
    /// ZIP 内每条笔记对应 yyyy/MM/dd/yyyyMMddHHmmss/ 路径的文件夹。
    /// 返回的文件以 {开始日期}_{结束日期}.zip 命名，日期格式 yyyyMMdd。
    ///
    /// 必须从 @MainActor 调用（调用者通常是 Task { } 继承主 actor）。
    /// 函数首先在主 actor 上抓取快照，然后将全部文件 I/O 切换到后台线程执行，
    /// 避免阻塞主线程，也不会用 DispatchQueue.main.sync 产生死锁。
    func exportAllNotes(
        startDate: Date? = nil,
        endDate: Date? = nil,
        tag: TagItem? = nil,
        progress: @escaping @Sendable (Int, Int) -> Void = { _, _ in }
    ) async throws -> URL {
        // ── Phase 0: fetch + snapshot on @MainActor ──────────────────────────
        // ModelContext must only be accessed on its owning actor (main actor).
        // We capture all required values into plain Sendable structs here.
        let descriptor = FetchDescriptor<NoteItem>(
            predicate: #Predicate { !$0.isDeleted },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        var notes = (try? noteStore.modelContext.fetch(descriptor)) ?? []

        // ---- in-memory date filtering ----
        if let start = startDate {
            let startOfDay = Calendar.current.startOfDay(for: start)
            notes = notes.filter { $0.createdAt >= startOfDay }
        }
        if let end = endDate {
            let endOfDay = Calendar.current.date(
                bySettingHour: 23, minute: 59, second: 59, of: end
            ) ?? end
            notes = notes.filter { $0.createdAt <= endOfDay }
        }
        if let tag = tag {
            notes = notes.filter { note in note.tags.contains { $0.id == tag.id } }
        }

        // Capture into plain value-type snapshots before leaving main actor.
        let snapshots = notes.map { makeSnapshot(note: $0) }
        let total = snapshots.count

        // Send initial progress on main actor (we are already on it).
        progress(0, total)

        // ── Phase 1+2: heavy file I/O on a background thread ─────────────────
        // NoteExportSnapshot / AttachmentExportSnapshot are plain value types
        // (Sendable), so passing them into Task.detached is safe.
        return try await Task.detached(priority: .userInitiated) { [startDate, endDate] in
            let fm = FileManager.default
            let stagingDir = fm.temporaryDirectory.appendingPathComponent("export_\(UUID().uuidString)")
            try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: stagingDir) }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

            let datePrefixFmt = DateFormatter()
            datePrefixFmt.locale = Locale(identifier: "en_US_POSIX")
            datePrefixFmt.dateFormat = "yyyy/MM/dd"

            var usedFolders: [String: Int] = [:]
            // Show at most ~12 distinct progress ticks; always fire on first and last.
            let progressStep = max(1, total / 12)

            for (index, note) in snapshots.enumerated() {
                let datePrefix = datePrefixFmt.string(from: note.createdAt)
                let baseName   = self.creationFilename(for: note)
                let baseFolder = "\(datePrefix)/\(baseName)"
                let count = usedFolders[baseFolder, default: 0]
                usedFolders[baseFolder] = count + 1
                let folderName = count == 0 ? baseFolder : "\(baseFolder)_\(count + 1)"

                let noteDir   = stagingDir.appendingPathComponent(folderName)
                let assetsDir = noteDir.appendingPathComponent("assets")
                try fm.createDirectory(at: assetsDir, withIntermediateDirectories: true)

                let allAttachments = note.attachments
                var fileMapping: [(attachment: AttachmentExportSnapshot, destName: String)] = []
                var usedNames = Set<String>()

                for attachment in allAttachments {
                    var destName = attachment.fileName
                    if usedNames.contains(destName) {
                        let ext  = (destName as NSString).pathExtension
                        let base = (destName as NSString).deletingPathExtension
                        var counter = 2
                        repeat {
                            destName = "\(base)_\(counter).\(ext)"
                            counter += 1
                        } while usedNames.contains(destName)
                    }
                    usedNames.insert(destName)
                    fileMapping.append((attachment, destName))

                    let src = attachment.fileURL
                    if (try? src.checkResourceIsReachable()) == true {
                        try? fm.copyItem(at: src, to: assetsDir.appendingPathComponent(destName))
                    }

                    // 位置附件：额外复制缩略图（地图截图）
                    if attachment.type == .location,
                       let thumbName = attachment.thumbnailFileName,
                       let thumbSrc = attachment.thumbnailURL {
                        if (try? thumbSrc.checkResourceIsReachable()) == true {
                            try? fm.copyItem(at: thumbSrc, to: assetsDir.appendingPathComponent(thumbName))
                        }
                    }
                }

                // Write meta.json to disk
                if let metaData = try? encoder.encode(self.buildMeta(note: note, fileMapping: fileMapping)) {
                    try metaData.write(to: noteDir.appendingPathComponent("meta.json"))
                }

                // Write index.html to disk
                if let htmlData = self.buildHTML(note: note, fileMapping: fileMapping).data(using: .utf8) {
                    try htmlData.write(to: noteDir.appendingPathComponent("index.html"))
                }

                // Send throttled progress update back to main actor.
                let current = index + 1
                let isLast  = current == total
                if isLast || current == 1 || current % progressStep == 0 {
                    Task { @MainActor in progress(current, total) }
                }
            }

            // Phase 2: stream-zip the staging directory
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyyMMdd"
            fmt.locale = Locale(identifier: "en_US_POSIX")
            let startStr = startDate.map { fmt.string(from: $0) } ?? fmt.string(from: Date())
            let endStr   = endDate.map   { fmt.string(from: $0) } ?? fmt.string(from: Date())
            let fileName = "\(startStr)_\(endStr).zip"

            let outputURL = fm.temporaryDirectory.appendingPathComponent(fileName)
            try self.streamZip(from: stagingDir, to: outputURL)
            return outputURL
        }.value
    }

    // MARK: - Streaming ZIP (disk → disk, chunk-by-chunk, no full-file in memory)

    private struct ZipEntryMeta {
        let path: String
        let crc: UInt32
        let size: UInt32
        let offset: UInt32
        let dosTime: UInt16
        let dosDate: UInt16
    }

    private let chunkSize = 256 * 1024   // 256 KB read buffer

    /// 从 sourceDir 目录树流式写入 ZIP 到 outputURL。
    /// 每次仅持有一个 chunkSize 的读缓冲，不会将整个文件加载到内存中。
    private func streamZip(from sourceDir: URL, to outputURL: URL) throws {
        let fm = FileManager.default
        fm.createFile(atPath: outputURL.path, contents: nil)
        guard let outHandle = FileHandle(forWritingAtPath: outputURL.path) else {
            throw ExportError.fileWriteFailed(
                NSError(domain: "ExportService", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "无法创建 ZIP 输出文件"])
            )
        }
        defer { try? outHandle.close() }

        var metas: [ZipEntryMeta] = []
        var writeOffset: UInt32 = 0
        let dosTime = dosDateTime(from: Date())
        let basePath = sourceDir.standardizedFileURL.path

        let enumerator = fm.enumerator(
            at: sourceDir.standardizedFileURL,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            let resVals = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if resVals?.isDirectory == true { continue }

            var relPath = fileURL.standardizedFileURL.path
            if relPath.hasPrefix(basePath + "/") {
                relPath = String(relPath.dropFirst(basePath.count + 1))
            }
            let nameData = relPath.data(using: .utf8) ?? Data()
            let fileSize = UInt32(resVals?.fileSize ?? 0)

            // Pass 1: stream-compute CRC32 without keeping file in memory
            let crc = try streamCRC32(of: fileURL)

            // Build and write local file header
            var header = Data(capacity: 30 + nameData.count)
            header += u32(0x04034b50)
            header += u16(20)
            header += u16(0)
            header += u16(0)                          // STORE
            header += u16(dosTime.time)
            header += u16(dosTime.date)
            header += u32(crc)
            header += u32(fileSize)
            header += u32(fileSize)
            header += u16(UInt16(nameData.count))
            header += u16(0)
            header += nameData
            try outHandle.write(contentsOf: header)

            // Pass 2: stream-write file content in chunks
            try streamWrite(from: fileURL, to: outHandle)

            metas.append(ZipEntryMeta(
                path: relPath, crc: crc, size: fileSize,
                offset: writeOffset,
                dosTime: dosTime.time, dosDate: dosTime.date
            ))
            writeOffset += UInt32(header.count) + fileSize
        }

        // Central directory — only tiny per-entry metadata, no file data
        let centralStart = writeOffset
        for m in metas {
            let nameData = m.path.data(using: .utf8) ?? Data()
            var entry = Data(capacity: 46 + nameData.count)
            entry += u32(0x02014b50)
            entry += u16(0x031E)
            entry += u16(20)
            entry += u16(0)
            entry += u16(0)
            entry += u16(m.dosTime)
            entry += u16(m.dosDate)
            entry += u32(m.crc)
            entry += u32(m.size)
            entry += u32(m.size)
            entry += u16(UInt16(nameData.count))
            entry += u16(0); entry += u16(0)
            entry += u16(0); entry += u16(0)
            entry += u32(0)
            entry += u32(m.offset)
            entry += nameData
            try outHandle.write(contentsOf: entry)
        }

        let centralSize = UInt32(metas.reduce(0) { $0 + 46 + ($1.path.utf8.count) })
        var eocd = Data(capacity: 22)
        eocd += u32(0x06054b50)
        eocd += u16(0); eocd += u16(0)
        eocd += u16(UInt16(metas.count))
        eocd += u16(UInt16(metas.count))
        eocd += u32(centralSize)
        eocd += u32(centralStart)
        eocd += u16(0)
        try outHandle.write(contentsOf: eocd)
    }

    /// 流式计算文件 CRC32，每次只读 chunkSize 字节
    private func streamCRC32(of fileURL: URL) throws -> UInt32 {
        guard let inHandle = FileHandle(forReadingAtPath: fileURL.path) else {
            return 0
        }
        defer { try? inHandle.close() }
        var crc: UInt32 = 0xFFFF_FFFF
        while true {
            guard let chunk = try inHandle.read(upToCount: chunkSize), !chunk.isEmpty else { break }
            for byte in chunk {
                crc ^= UInt32(byte)
                for _ in 0..<8 {
                    crc = (crc >> 1) ^ (0xEDB8_8320 & (~(crc & 1) &+ 1))
                }
            }
        }
        return crc ^ 0xFFFF_FFFF
    }

    /// 流式将 fileURL 内容写入 outHandle，每次读写 chunkSize 字节
    private func streamWrite(from fileURL: URL, to outHandle: FileHandle) throws {
        guard let inHandle = FileHandle(forReadingAtPath: fileURL.path) else { return }
        defer { try? inHandle.close() }
        while true {
            guard let chunk = try inHandle.read(upToCount: chunkSize), !chunk.isEmpty else { break }
            try outHandle.write(contentsOf: chunk)
        }
    }

    // MARK: - Meta JSON Model

    private struct NoteMeta: Encodable {
        let id: String
        let content: String
        let tags: [String]
        let createdAt: String
        let updatedAt: String
        let attachments: [AttachmentMeta]
    }

    private struct AttachmentMeta: Encodable {
        let fileName: String
        let type: String
    }

    private func buildMeta(note: NoteExportSnapshot,
                           fileMapping: [(attachment: AttachmentExportSnapshot, destName: String)]) -> NoteMeta {
        let iso = ISO8601DateFormatter()
        return NoteMeta(
            id: note.id.uuidString,
            content: note.content,
            tags: note.tagNames,
            createdAt: iso.string(from: note.createdAt),
            updatedAt: iso.string(from: note.updatedAt),
            attachments: fileMapping.map {
                AttachmentMeta(fileName: $0.destName, type: $0.attachment.type.rawValue)
            }
        )
    }

    // MARK: - HTML Builder

    private func buildHTML(note: NoteExportSnapshot,
                           fileMapping: [(attachment: AttachmentExportSnapshot, destName: String)]) -> String {
        let title   = note.preview.isEmpty ? "笔记" : note.preview
        let dateStr = note.updatedAt.formatted(date: .abbreviated, time: .shortened)

        let tagsHTML: String = note.tagNames.isEmpty ? "" :
            "<div class=\"tags\">" +
            note.tagNames.map { "<span class=\"tag\">#\(escapeHTML($0))</span>" }.joined() +
            "</div>"

        let contentHTML = escapeHTML(note.content)
            .replacingOccurrences(of: "\n", with: "<br>\n")

        let imageTypes: Set<AttachmentType> = [.photo, .drawing, .scannedDocument]
        var attachHTML = ""
        for m in fileMapping {
            let escaped = escapeHTML(m.destName)
            if imageTypes.contains(m.attachment.type) {
                attachHTML += "<div class=\"attachment\">"
                attachHTML += "<img src=\"assets/\(escaped)\" alt=\"\(escapeHTML(m.attachment.type.displayName))\">"
                attachHTML += "</div>\n"
            } else if m.attachment.type == .location {
                // 位置附件：显示缩略图 + 坐标文字
                attachHTML += "<div class=\"attachment location-attachment\">\n"
                if let thumbName = m.attachment.thumbnailFileName {
                    let thumbEscaped = escapeHTML(thumbName)
                    attachHTML += "<img src=\"assets/\(thumbEscaped)\" alt=\"位置截图\">\n"
                }
                // 解析 JSON 获取坐标
                let dataURL = m.attachment.fileURL
                if let jsonData = try? Data(contentsOf: dataURL),
                   let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                   let lat = json["latitude"] as? Double,
                   let lon = json["longitude"] as? Double {
                    attachHTML += "<p class=\"location-coord\">📍 \(String(format: "%.6f, %.6f", lat, lon))</p>\n"
                } else {
                    attachHTML += "<p class=\"location-coord\">📍 位置</p>\n"
                }
                attachHTML += "</div>\n"
            } else {
                attachHTML += "<div class=\"attachment file-attachment\">"
                attachHTML += "<a href=\"assets/\(escaped)\">📎 \(escaped)</a>"
                attachHTML += "</div>\n"
            }
        }
        if !attachHTML.isEmpty {
            attachHTML = "<div class=\"attachments\">\n\(attachHTML)</div>"
        }

        return """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>\(escapeHTML(title))</title>
          <style>
            *, *::before, *::after { box-sizing: border-box; }
            body {
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
              max-width: 780px; margin: 40px auto; padding: 0 24px;
              color: #1c1c1e; background: #ffffff; line-height: 1.6;
            }
            .meta { color: #8e8e93; font-size: 13px; margin-bottom: 6px; }
            .tags { margin: 6px 0 16px; }
            .tag {
              display: inline-block; background: #f2f2f7; color: #007aff;
              border-radius: 12px; padding: 3px 10px; margin-right: 6px;
              font-size: 13px; font-weight: 500;
            }
            hr { border: none; border-top: 1px solid #e5e5ea; margin: 16px 0; }
            .content { font-size: 16px; line-height: 1.8; }
            .attachments {
              margin-top: 28px;
              display: grid;
              grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
              gap: 12px;
            }
            .attachment img {
              width: 100%; border-radius: 10px; object-fit: cover;
              box-shadow: 0 2px 8px rgba(0,0,0,0.12);
            }
            .file-attachment {
              background: #f2f2f7; border-radius: 10px;
              padding: 12px 14px; font-size: 14px;
            }
            .file-attachment a { color: #007aff; text-decoration: none; }
            .file-attachment a:hover { text-decoration: underline; }
            .location-attachment { text-align: center; }
            .location-attachment img { border-radius: 10px; }
            .location-coord {
              font-size: 13px; color: #8e8e93; margin: 6px 0 0;
              font-family: ui-monospace, SFMono-Regular, monospace;
            }
          </style>
        </head>
        <body>
          <div class="meta">\(escapeHTML(dateStr))</div>
          \(tagsHTML)
          <hr>
          <div class="content">\(contentHTML)</div>
          \(attachHTML)
        </body>
        </html>
        """
    }

    private func escapeHTML(_ str: String) -> String {
        str
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    // MARK: - Pure-Swift ZIP Builder (STORE, no compression, zero dependencies)

    private struct ZipEntry {
        let path: String
        let data: Data
    }

    private func buildZip(entries: [ZipEntry]) -> Data {
        var archive = Data()
        var centralDir = Data()
        var localOffsets: [UInt32] = []

        let dosTime = dosDateTime(from: Date())

        for entry in entries {
            localOffsets.append(UInt32(archive.count))
            let nameData = entry.path.data(using: .utf8) ?? Data()
            let crc      = crc32(entry.data)
            let size     = UInt32(entry.data.count)

            // Local file header
            archive += u32(0x04034b50)          // signature PK\x03\x04
            archive += u16(20)                  // version needed
            archive += u16(0)                   // general purpose bit flag
            archive += u16(0)                   // compression method = STORE
            archive += u16(dosTime.time)         // last mod file time
            archive += u16(dosTime.date)         // last mod file date
            archive += u32(crc)                  // CRC-32
            archive += u32(size)                 // compressed size
            archive += u32(size)                 // uncompressed size
            archive += u16(UInt16(nameData.count))
            archive += u16(0)                    // extra field length
            archive += nameData
            archive += entry.data
        }

        let centralDirOffset = UInt32(archive.count)

        for (i, entry) in entries.enumerated() {
            let nameData = entry.path.data(using: .utf8) ?? Data()
            let crc      = crc32(entry.data)
            let size     = UInt32(entry.data.count)

            centralDir += u32(0x02014b50)           // signature PK\x01\x02
            centralDir += u16(0x031E)               // version made by (Unix, 3.0)
            centralDir += u16(20)                   // version needed
            centralDir += u16(0)                    // general purpose bit flag
            centralDir += u16(0)                    // compression = STORE
            centralDir += u16(dosTime.time)
            centralDir += u16(dosTime.date)
            centralDir += u32(crc)
            centralDir += u32(size)
            centralDir += u32(size)
            centralDir += u16(UInt16(nameData.count))
            centralDir += u16(0)                    // extra field length
            centralDir += u16(0)                    // file comment length
            centralDir += u16(0)                    // disk number start
            centralDir += u16(0)                    // internal attributes
            centralDir += u32(0)                    // external attributes
            centralDir += u32(localOffsets[i])      // offset of local header
            centralDir += nameData
        }

        archive += centralDir

        // End of central directory record
        archive += u32(0x06054b50)                  // signature PK\x05\x06
        archive += u16(0)                           // disk number
        archive += u16(0)                           // disk with start of central dir
        archive += u16(UInt16(entries.count))       // entries on this disk
        archive += u16(UInt16(entries.count))       // total entries
        archive += u32(UInt32(centralDir.count))    // size of central directory
        archive += u32(centralDirOffset)            // offset of central directory
        archive += u16(0)                           // comment length

        return archive
    }

    // Little-endian binary helpers
    private func u16(_ v: UInt16) -> Data { Swift.withUnsafeBytes(of: v.littleEndian) { Data($0) } }
    private func u32(_ v: UInt32) -> Data { Swift.withUnsafeBytes(of: v.littleEndian) { Data($0) } }

    /// DOS date/time format (used in ZIP headers)
    private func dosDateTime(from date: Date) -> (date: UInt16, time: UInt16) {
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let yr  = max(0, (c.year  ?? 1980) - 1980)
        let mon = c.month  ?? 1
        let day = c.day    ?? 1
        let hr  = c.hour   ?? 0
        let min = c.minute ?? 0
        let sec = (c.second ?? 0) / 2
        return (
            date: UInt16((yr << 9) | (mon << 5) | day),
            time: UInt16((hr << 11) | (min << 5) | sec)
        )
    }

    /// CRC-32 (ISO 3309 polynomial) — pure Swift, no external deps
    private func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc >> 1) ^ (0xEDB8_8320 & (~(crc & 1) &+ 1))
            }
        }
        return crc ^ 0xFFFF_FFFF
    }

    // MARK: - Image Orientation Normalization

    /// 将图片方向标准化为 .up，避免 PDF 渲染时出现镜像或旋转问题
    static func normalizeImageOrientation(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { _ in
            image.draw(at: .zero)
        }
    }

    // MARK: - File Helpers

    /// 写入临时目录，返回 URL
    private func writeTempFile(data: Data, name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw ExportError.fileWriteFailed(error)
        }
        return url
    }

    /// 以笔记创建时间生成文件名，格式：yyyyMMddHHmmss
    private nonisolated func creationFilename(for note: NoteExportSnapshot) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMddHHmmss"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt.string(from: note.createdAt)
    }

    /// 清理文件名（去除非法字符，限制长度 60）
    private func sanitizeFilename(_ str: String) -> String {
        let illegalChars = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = str.components(separatedBy: illegalChars).joined(separator: "_")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "笔记" : String(trimmed.prefix(60))
    }
}

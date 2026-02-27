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

            // ---- 正文（支持自动换页，渲染 Markdown 格式；表格用 Core Graphics 绘制）----
            let segments = parsePDFSegments(note.content)
            for segment in segments {
                switch segment {
                case .text(let attrStr):
                    guard attrStr.length > 0 else { break }
                    let framesetter = CTFramesetterCreateWithAttributedString(attrStr)
                    var charIndex = 0
                    while charIndex < attrStr.length {
                        var availableHeight = pageRect.height - y - margin
                        if availableHeight < 20 {
                            ctx.beginPage(); y = margin
                            availableHeight = pageRect.height - y - margin
                        }
                        let cgRect = CGRect(x: margin, y: margin,
                                            width: contentWidth, height: availableHeight)
                        let path = CGPath(rect: cgRect, transform: nil)
                        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(charIndex, 0), path, nil)

                        let cgCtx = ctx.cgContext
                        cgCtx.saveGState()
                        cgCtx.translateBy(x: 0, y: pageRect.height)
                        cgCtx.scaleBy(x: 1, y: -1)
                        cgCtx.textMatrix = .identity
                        CTFrameDraw(frame, cgCtx)
                        cgCtx.restoreGState()

                        let visibleRange = CTFrameGetVisibleStringRange(frame)
                        if visibleRange.length == 0 { break }
                        if let newY = yAfterCTFrame(frame, pageHeight: pageRect.height) { y = newY }
                        charIndex += visibleRange.length
                        if charIndex < attrStr.length {
                            ctx.beginPage(); y = margin
                        }
                    }

                case .table(let headers, let rows):
                    drawPDFTable(ctx, headers: headers, rows: rows,
                                 x: margin, y: &y,
                                 width: contentWidth, pageRect: pageRect, margin: margin)
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

                    // 缩放到目标尺寸，避免在 PDF 中嵌入完整分辨率位图
                    let targetSize = CGSize(width: imgW, height: imgH)
                    let downsampledImg = Self.downsampleForPDF(normalizedImg, targetPointSize: targetSize)

                    let imgRect = CGRect(x: margin, y: iy, width: imgW, height: imgH)
                    downsampledImg.draw(in: imgRect)
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

                        // 缩放到目标尺寸，避免在 PDF 中嵌入完整分辨率位图
                        let thumbTargetSize = CGSize(width: imgW, height: imgH)
                        let downsampledThumb = Self.downsampleForPDF(normalizedThumb, targetPointSize: thumbTargetSize)

                        let imgRect = CGRect(x: margin, y: ly, width: imgW, height: imgH)
                        downsampledThumb.draw(in: imgRect)
                        ly += imgH + 4
                    }

                    // 仅显示位置标识，不显示具体坐标
                    if ly + 20 > pageRect.height - margin {
                        ctx.beginPage()
                        ly = margin
                    }
                    ("📍 位置" as NSString).draw(at: CGPoint(x: margin, y: ly), withAttributes: locationTitleAttrs)
                    ly += 18
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
        let codeFont  = UIFont.monospacedSystemFont(ofSize: baseFontSize * 0.88, weight: .regular)
        let h1Font    = UIFont.systemFont(ofSize: baseFontSize * 1.6,  weight: .bold)
        let h2Font    = UIFont.systemFont(ofSize: baseFontSize * 1.35, weight: .bold)
        let h3Font    = UIFont.systemFont(ofSize: baseFontSize * 1.15, weight: .semibold)
        let bodyColor = UIColor.black
        let grayColor = UIColor.systemGray

        let result = NSMutableAttributedString()
        let lines   = content.components(separatedBy: "\n")
        var i = 0

        func append(_ text: String, font: UIFont, color: UIColor = bodyColor, afterSpacing: CGFloat = 2) {
            let para = NSMutableParagraphStyle()
            para.paragraphSpacing = afterSpacing
            para.lineSpacing = 1
            result.append(NSAttributedString(
                string: text + "\n",
                attributes: [.font: font, .foregroundColor: color, .paragraphStyle: para]
            ))
        }

        // 剥离行内 Markdown 语法，保留文字
        func stripInline(_ text: String) -> String {
            var s = text
            s = s.replacingOccurrences(of: "\\*\\*\\*(.+?)\\*\\*\\*", with: "$1", options: .regularExpression)
            s = s.replacingOccurrences(of: "\\*\\*(.+?)\\*\\*",  with: "$1", options: .regularExpression)
            s = s.replacingOccurrences(of: "\\*(.+?)\\*",         with: "$1", options: .regularExpression)
            s = s.replacingOccurrences(of: "~~(.+?)~~",           with: "$1", options: .regularExpression)
            s = s.replacingOccurrences(of: "`([^`]+)`",           with: "$1", options: .regularExpression)
            s = s.replacingOccurrences(of: "!\\[.*?\\]\\(.*?\\)", with: "",   options: .regularExpression)
            s = s.replacingOccurrences(of: "\\[(.+?)\\]\\(.*?\\)",with: "$1", options: .regularExpression)
            return s
        }

        // 计算字符串在等宽字体中的显示宽度（CJK 字符占 2 格）
        func displayWidth(_ s: String) -> Int {
            s.unicodeScalars.reduce(0) { acc, scalar in
                let v = scalar.value
                let wide = (v >= 0x1100 && v <= 0x115F) ||
                           (v >= 0x2E80 && v <= 0x9FFF) ||
                           (v >= 0xAC00 && v <= 0xD7AF) ||
                           (v >= 0xF900 && v <= 0xFAFF) ||
                           (v >= 0xFF00 && v <= 0xFF60) ||
                           (v >= 0xFFE0 && v <= 0xFFE6)
                return acc + (wide ? 2 : 1)
            }
        }

        func parseTableCells(_ row: String) -> [String] {
            var cells = row.components(separatedBy: "|")
            if cells.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { cells.removeFirst() }
            if cells.last?.trimmingCharacters(in: .whitespaces).isEmpty == true  { cells.removeLast() }
            return cells.map { $0.trimmingCharacters(in: .whitespaces) }
        }

        func isSeparatorRow(_ row: String) -> Bool {
            let cells = parseTableCells(row)
            guard !cells.isEmpty else { return false }
            return cells.allSatisfy { cell in
                !cell.isEmpty &&
                cell.replacingOccurrences(of: "-", with: "")
                    .replacingOccurrences(of: ":", with: "")
                    .replacingOccurrences(of: " ", with: "")
                    .isEmpty
            }
        }

        // 渲染带边框的表格（Unicode box-drawing 字符 + 等宽字体）
        func renderTable(_ tableLines: [String]) {
            guard !tableLines.isEmpty else { return }

            let headerCells = parseTableCells(tableLines[0]).map { stripInline($0) }
            let bodyStart   = tableLines.count > 1 && isSeparatorRow(tableLines[1]) ? 2 : 1
            var bodyRows: [[String]] = []
            for j in bodyStart ..< tableLines.count {
                bodyRows.append(parseTableCells(tableLines[j]).map { stripInline($0) })
            }

            let numCols = max(headerCells.count, bodyRows.map { $0.count }.max() ?? 0)
            guard numCols > 0 else { return }

            // 每列最小宽度 = 3，取标题与所有数据中的最大显示宽度
            var colWidths = Array(repeating: 3, count: numCols)
            for (c, t) in headerCells.enumerated() where c < numCols {
                colWidths[c] = max(colWidths[c], displayWidth(t))
            }
            for row in bodyRows {
                for (c, t) in row.enumerated() where c < numCols {
                    colWidths[c] = max(colWidths[c], displayWidth(t))
                }
            }

            // 文本居左，右侧填充空格至列宽
            func padCell(_ text: String, _ colWidth: Int) -> String {
                let spaces = max(0, colWidth - displayWidth(text))
                return " " + text + String(repeating: " ", count: spaces + 1)
            }

            // 生成水平分隔线
            func hLine(left: String, mid: String, fill: Character, right: String) -> String {
                let parts = colWidths.map { String(repeating: fill, count: $0 + 2) }
                return left + parts.joined(separator: mid) + right
            }

            func dataRow(_ cells: [String]) -> String {
                var out = "│"
                for c in 0 ..< numCols {
                    let t = c < cells.count ? cells[c] : ""
                    out += padCell(t, colWidths[c]) + "│"
                }
                return out
            }

            let top    = hLine(left: "┌", mid: "┬", fill: "─", right: "┐")
            let divSep = hLine(left: "├", mid: "┼", fill: "─", right: "┤")
            let bottom = hLine(left: "└", mid: "┴", fill: "─", right: "┘")

            append(top,                      font: codeFont, color: grayColor,  afterSpacing: 0)
            append(dataRow(headerCells),     font: codeFont, color: bodyColor,  afterSpacing: 0)
            append(divSep,                   font: codeFont, color: grayColor,  afterSpacing: 0)
            for (ri, row) in bodyRows.enumerated() {
                let isLast = ri == bodyRows.count - 1
                append(dataRow(row), font: codeFont, color: bodyColor, afterSpacing: 0)
                if isLast { append(bottom, font: codeFont, color: grayColor, afterSpacing: 6) }
            }
            if bodyRows.isEmpty { append(bottom, font: codeFont, color: grayColor, afterSpacing: 6) }
        }

        while i < lines.count {
            let line = lines[i]

            // 代码块围栏
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                let fence = line.hasPrefix("```") ? "```" : "~~~"
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].hasPrefix(fence) {
                    codeLines.append(lines[i])
                    i += 1
                }
                i += 1 // skip closing fence
                append(codeLines.joined(separator: "\n"), font: codeFont, color: grayColor, afterSpacing: 4)
                continue
            }

            // 表格行已由 parsePDFSegments 提取并交由 drawPDFTable 绘制，此处跳过
            if line.hasPrefix("|") {
                while i < lines.count && lines[i].hasPrefix("|") { i += 1 }
                continue
            }

            // 块级元素
            if      line.hasPrefix("### ") { append(stripInline(String(line.dropFirst(4))), font: h3Font) }
            else if line.hasPrefix("## ")  { append(stripInline(String(line.dropFirst(3))), font: h2Font) }
            else if line.hasPrefix("# ")   { append(stripInline(String(line.dropFirst(2))), font: h1Font) }
            else if line.hasPrefix("> ")   { append("│ " + stripInline(String(line.dropFirst(2))), font: bodyFont, color: grayColor) }
            else if line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") {
                append("☑ " + stripInline(String(line.dropFirst(6))), font: bodyFont)
            } else if line.hasPrefix("- [ ] ") {
                append("☐ " + stripInline(String(line.dropFirst(6))), font: bodyFont)
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                append("• " + stripInline(String(line.dropFirst(2))), font: bodyFont)
            } else {
                append(stripInline(line), font: bodyFont)
            }

            i += 1
        }

        return result
    }

    // MARK: - PDF Segment Helpers

    private func stripMarkdownInline(_ text: String) -> String {
        var s = text
        s = s.replacingOccurrences(of: "\\*\\*\\*(.+?)\\*\\*\\*", with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\*\\*(.+?)\\*\\*",       with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\*(.+?)\\*",             with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: "~~(.+?)~~",               with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: "`([^`]+)`",               with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: "!\\[.*?\\]\\(.*?\\)",    with: "",   options: .regularExpression)
        s = s.replacingOccurrences(of: "\\[(.+?)\\]\\(.*?\\)",   with: "$1", options: .regularExpression)
        return s
    }

    private enum PDFContentSegment {
        case text(NSAttributedString)
        case table(headers: [String], rows: [[String]])
    }

    private func parsePDFSegments(_ content: String) -> [PDFContentSegment] {
        let lines = content.components(separatedBy: "\n")
        var segments: [PDFContentSegment] = []
        var textLines: [String] = []
        var i = 0

        func flushText() {
            while textLines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { textLines.removeLast() }
            if !textLines.isEmpty {
                segments.append(.text(markdownAttributedString(for: textLines.joined(separator: "\n"))))
                textLines = []
            }
        }

        func splitCells(_ row: String) -> [String] {
            var cells = row.components(separatedBy: "|")
            if cells.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { cells.removeFirst() }
            if cells.last?.trimmingCharacters(in: .whitespaces).isEmpty  == true { cells.removeLast() }
            return cells.map { $0.trimmingCharacters(in: .whitespaces) }
        }

        func isSep(_ row: String) -> Bool {
            let cells = splitCells(row)
            guard !cells.isEmpty else { return false }
            return cells.allSatisfy {
                !$0.isEmpty &&
                $0.replacingOccurrences(of: "-", with: "")
                  .replacingOccurrences(of: ":", with: "")
                  .replacingOccurrences(of: " ", with: "").isEmpty
            }
        }

        while i < lines.count {
            let line = lines[i]
            if line.hasPrefix("|") {
                flushText()
                var tableLines: [String] = []
                while i < lines.count && lines[i].hasPrefix("|") { tableLines.append(lines[i]); i += 1 }
                guard !tableLines.isEmpty else { continue }
                let headers   = splitCells(tableLines[0]).map { stripMarkdownInline($0) }
                let bodyStart = (tableLines.count > 1 && isSep(tableLines[1])) ? 2 : 1
                let rows      = (bodyStart..<tableLines.count).map { splitCells(tableLines[$0]).map { stripMarkdownInline($0) } }
                segments.append(.table(headers: headers, rows: rows))
            } else {
                textLines.append(line)
                i += 1
            }
        }
        flushText()
        return segments
    }

    /// Returns the UIKit-Y position immediately below the last rendered line of a CTFrame.
    private func yAfterCTFrame(_ frame: CTFrame, pageHeight: CGFloat) -> CGFloat? {
        let cfLines = CTFrameGetLines(frame)
        let count   = CFArrayGetCount(cfLines)
        guard count > 0 else { return nil }
        var origins = Array(repeating: CGPoint.zero, count: count)
        CTFrameGetLineOrigins(frame, CFRangeMake(0, 0), &origins)
        // origins are in CG coords (Y from bottom). Last entry = last (bottom) line.
        let lastOrigin = origins[count - 1]
        let lastLine   = unsafeBitCast(CFArrayGetValueAtIndex(cfLines, count - 1), to: CTLine.self)
        var descent: CGFloat = 0
        CTLineGetTypographicBounds(lastLine, nil, &descent, nil)
        // Convert: UIKit Y = pageHeight – CG Y
        let bottomOfLineInCG = lastOrigin.y - descent
        return pageHeight - bottomOfLineInCG + 6 // 6 pt leading
    }

    /// Draws a table using Core Graphics within the PDF renderer and advances `y`.
    private func drawPDFTable(
        _ ctx: UIGraphicsPDFRendererContext,
        headers: [String], rows: [[String]],
        x: CGFloat, y: inout CGFloat,
        width: CGFloat, pageRect: CGRect, margin: CGFloat
    ) {
        let cellH:      CGFloat = 24
        let cellFont   = UIFont.systemFont(ofSize: 11, weight: .regular)
        let headerFont = UIFont.systemFont(ofSize: 11, weight: .semibold)
        let numCols = max(headers.count, rows.map { $0.count }.max() ?? 0)
        guard numCols > 0 else { return }
        // Floor the column width so all columns share exact pixel-aligned boundaries
        let colW    = floor(width / CGFloat(numCols))
        let tableW  = colW * CGFloat(numCols)
        let insetX: CGFloat = 6
        let lineW:  CGFloat = 0.5

        let headerBg    = UIColor(red: 0.918, green: 0.918, blue: 0.937, alpha: 1)
        let evenRowBg   = UIColor.white
        let oddRowBg    = UIColor(red: 0.972, green: 0.972, blue: 0.980, alpha: 1)
        let borderColor = UIColor(red: 0.745, green: 0.745, blue: 0.765, alpha: 1)
        let textColor   = UIColor.black

        let allRows: [(cells: [String], font: UIFont, bg: UIColor)] =
            [(headers, headerFont, headerBg)] +
            rows.enumerated().map { ri, row in (row, cellFont, ri % 2 == 0 ? evenRowBg : oddRowBg) }

        // Start new page if the header + at least one data row won't fit
        if y + cellH * CGFloat(min(allRows.count, 2)) > pageRect.height - margin {
            ctx.beginPage()
            y = margin
        }

        let cgCtx = ctx.cgContext

        // ---- Draw rows (fills + text), page-breaking as needed ----
        var rowStartY       = y
        var pageTableTopY   = y   // Y of the first row on the current PDF page
        var rowsOnThisPage  = 0

        for rowData in allRows {
            if rowStartY + cellH > pageRect.height - margin {
                // Flush the grid for the portion on the current page …
                drawGridLines(cgCtx, x: x, topY: pageTableTopY, tableW: tableW,
                              numCols: numCols, colW: colW, rowCount: rowsOnThisPage,
                              cellH: cellH, lineW: lineW, color: borderColor)
                // … then start a fresh page
                ctx.beginPage()
                y            = margin
                rowStartY    = margin
                pageTableTopY = margin
                rowsOnThisPage = 0
            }

            // Fill row background
            let rowRect = CGRect(x: x, y: rowStartY, width: tableW, height: cellH)
            rowData.bg.setFill()
            cgCtx.fill(rowRect)

            // Draw cell text
            for c in 0 ..< numCols {
                let cellX    = x + CGFloat(c) * colW
                let text     = c < rowData.cells.count ? rowData.cells[c] : ""
                let textY    = rowStartY + (cellH - rowData.font.lineHeight) / 2
                let textRect = CGRect(x: cellX + insetX, y: textY,
                                      width: colW - insetX * 2, height: cellH)
                (text as NSString).draw(in: textRect, withAttributes: [
                    .font: rowData.font, .foregroundColor: textColor
                ])
            }
            rowStartY      += cellH
            rowsOnThisPage += 1
        }

        // ---- Flush grid for the last (or only) page ----
        drawGridLines(cgCtx, x: x, topY: pageTableTopY, tableW: tableW,
                      numCols: numCols, colW: colW, rowCount: rowsOnThisPage,
                      cellH: cellH, lineW: lineW, color: borderColor)

        y = rowStartY + 10 // spacing after table
    }

    /// Draws a clean grid (outer border + all internal lines) using explicit CGPath.
    private func drawGridLines(
        _ cgCtx: CGContext,
        x: CGFloat, topY: CGFloat,
        tableW: CGFloat, numCols: Int, colW: CGFloat,
        rowCount: Int, cellH: CGFloat,
        lineW: CGFloat, color: UIColor
    ) {
        guard rowCount > 0 else { return }
        cgCtx.saveGState()
        cgCtx.setStrokeColor(color.cgColor)
        cgCtx.setLineWidth(lineW)
        cgCtx.setLineCap(.square)

        let totalH = cellH * CGFloat(rowCount)
        let path   = CGMutablePath()

        // Outer rectangle
        path.addRect(CGRect(x: x, y: topY, width: tableW, height: totalH))

        // Internal horizontal lines (between rows)
        for r in 1 ..< rowCount {
            let lineY = topY + CGFloat(r) * cellH
            path.move(to: CGPoint(x: x, y: lineY))
            path.addLine(to: CGPoint(x: x + tableW, y: lineY))
        }

        // Internal vertical lines (between columns)
        for c in 1 ..< numCols {
            let lineX = x + CGFloat(c) * colW
            path.move(to: CGPoint(x: lineX, y: topY))
            path.addLine(to: CGPoint(x: lineX, y: topY + totalH))
        }

        cgCtx.addPath(path)
        cgCtx.strokePath()
        cgCtx.restoreGState()
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

        let contentHTML = markdownToHTML(note.content)

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
                //if let jsonData = try? Data(contentsOf: dataURL),
                //   let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                //   let lat = json["latitude"] as? Double,
                //   let lon = json["longitude"] as? Double {
                //    attachHTML += "<p class=\"location-coord\">📍 \(String(format: "%.6f, %.6f", lat, lon))</p>\n"
                //} else {
                //    attachHTML += "<p class=\"location-coord\">📍 位置</p>\n"
                //}
                attachHTML += "<p class=\"location-coord\">📍 位置</p>\n"
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
            .content h1 { font-size: 1.6em; font-weight: 700; margin: 0.6em 0 0.3em; }
            .content h2 { font-size: 1.35em; font-weight: 700; margin: 0.6em 0 0.3em; }
            .content h3 { font-size: 1.15em; font-weight: 600; margin: 0.6em 0 0.3em; }
            .content blockquote { border-left: 3px solid #e5e5ea; margin: 8px 0; padding: 4px 12px; color: #8e8e93; }
            .content pre { background: #f2f2f7; border-radius: 8px; padding: 12px 14px; overflow-x: auto; font-size: 0.88em; }
            .content code { font-family: ui-monospace, SFMono-Regular, monospace; background: #f2f2f7; padding: 1px 4px; border-radius: 4px; font-size: 0.88em; }
            .content pre code { background: none; padding: 0; }
            .content ul, .content ol { padding-left: 1.5em; margin: 6px 0; }
            .content table { border-collapse: collapse; width: 100%; margin: 12px 0; font-size: 0.95em; }
            .content table th, .content table td { border: 1px solid #d1d1d6; padding: 8px 12px; text-align: left; }
            .content table thead th { background: #f2f2f7; font-weight: 600; }
            .content table tbody tr:nth-child(even) { background: #fafafa; }
            .content del { text-decoration: line-through; color: #8e8e93; }
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

    // MARK: - Markdown → HTML

    private func markdownToHTML(_ content: String) -> String {
        let lines = content.components(separatedBy: "\n")
        var html = ""
        var i = 0

        func renderInline(_ raw: String) -> String {
            var s = escapeHTML(raw)
            s = s.replacingOccurrences(of: "\\*\\*\\*(.+?)\\*\\*\\*",  with: "<strong><em>$1</em></strong>", options: .regularExpression)
            s = s.replacingOccurrences(of: "\\*\\*(.+?)\\*\\*",       with: "<strong>$1</strong>",         options: .regularExpression)
            s = s.replacingOccurrences(of: "__(.+?)__",               with: "<strong>$1</strong>",         options: .regularExpression)
            s = s.replacingOccurrences(of: "\\*(.+?)\\*",             with: "<em>$1</em>",                 options: .regularExpression)
            s = s.replacingOccurrences(of: "~~(.+?)~~",               with: "<del>$1</del>",               options: .regularExpression)
            s = s.replacingOccurrences(of: "`([^`]+)`",               with: "<code>$1</code>",             options: .regularExpression)
            s = s.replacingOccurrences(of: "!\\[([^\\]]*)\\]\\(([^)]+)\\)", with: "<img src=\"$2\" alt=\"$1\">", options: .regularExpression)
            s = s.replacingOccurrences(of: "\\[([^\\]]+)\\]\\(([^)]+)\\)",  with: "<a href=\"$2\">$1</a>",    options: .regularExpression)
            return s
        }

        func parseTableRow(_ row: String) -> [String] {
            var cells = row.components(separatedBy: "|")
            if cells.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { cells.removeFirst() }
            if cells.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { cells.removeLast() }
            return cells.map { $0.trimmingCharacters(in: .whitespaces) }
        }

        func isSeparatorRow(_ row: String) -> Bool {
            let cells = parseTableRow(row)
            guard !cells.isEmpty else { return false }
            return cells.allSatisfy { cell in
                !cell.isEmpty &&
                cell.replacingOccurrences(of: "-", with: "")
                    .replacingOccurrences(of: ":", with: "")
                    .replacingOccurrences(of: " ", with: "")
                    .isEmpty
            }
        }

        while i < lines.count {
            let line = lines[i]

            // Code fence
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                let fence = line.hasPrefix("```") ? "```" : "~~~"
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].hasPrefix(fence) {
                    codeLines.append(escapeHTML(lines[i]))
                    i += 1
                }
                i += 1 // skip closing fence
                html += "<pre><code>\(codeLines.joined(separator: "\n"))</code></pre>\n"
                continue
            }

            // Table: consecutive lines starting with |
            if line.hasPrefix("|") {
                var tableLines: [String] = []
                while i < lines.count && lines[i].hasPrefix("|") {
                    tableLines.append(lines[i])
                    i += 1
                }
                guard tableLines.count >= 2 else {
                    for tl in tableLines { html += "<p>\(renderInline(tl))</p>\n" }
                    continue
                }
                let headers = parseTableRow(tableLines[0])
                let bodyStart = (tableLines.count > 1 && isSeparatorRow(tableLines[1])) ? 2 : 1
                html += "<table>\n<thead>\n<tr>"
                for h in headers { html += "<th>\(renderInline(h))</th>" }
                html += "</tr>\n</thead>\n<tbody>\n"
                for j in bodyStart..<tableLines.count {
                    let cells = parseTableRow(tableLines[j])
                    html += "<tr>"
                    for cell in cells { html += "<td>\(renderInline(cell))</td>" }
                    html += "</tr>\n"
                }
                html += "</tbody>\n</table>\n"
                continue
            }

            // Headings
            if line.hasPrefix("### ") {
                html += "<h3>\(renderInline(String(line.dropFirst(4))))</h3>\n"
            } else if line.hasPrefix("## ") {
                html += "<h2>\(renderInline(String(line.dropFirst(3))))</h2>\n"
            } else if line.hasPrefix("# ") {
                html += "<h1>\(renderInline(String(line.dropFirst(2))))</h1>\n"
            } else if line.hasPrefix("---") && line.replacingOccurrences(of: "-", with: "").isEmpty {
                html += "<hr>\n"
            } else if line.hasPrefix("> ") {
                html += "<blockquote>\(renderInline(String(line.dropFirst(2))))</blockquote>\n"
            } else if line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") {
                html += "<ul class=\"task-list\"><li>\u{2611} \(renderInline(String(line.dropFirst(6))))</li></ul>\n"
            } else if line.hasPrefix("- [ ] ") {
                html += "<ul class=\"task-list\"><li>\u{2610} \(renderInline(String(line.dropFirst(6))))</li></ul>\n"
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                html += "<ul><li>\(renderInline(String(line.dropFirst(2))))</li></ul>\n"
            } else if line.range(of: "^\\d+\\. ", options: .regularExpression) != nil {
                let text = line.replacingOccurrences(of: "^\\d+\\. ", with: "", options: .regularExpression)
                html += "<ol><li>\(renderInline(text))</li></ol>\n"
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                html += "<br>\n"
            } else {
                html += "<p>\(renderInline(line))</p>\n"
            }

            i += 1
        }
        return html
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

    // MARK: - Image Downsampling for PDF

    /// 将图片缩放到指定点尺寸并压缩为 JPEG，然后从 JPEG 数据重建 UIImage。
    /// 这样 UIGraphicsPDFRenderer 会以 DCTDecode（JPEG）方式嵌入图片，
    /// 而非嵌入未压缩的完整位图，PDF 体积可缩小 10-50 倍。
    private static func downsampleForPDF(_ image: UIImage, targetPointSize: CGSize, scale: CGFloat = 1.0) -> UIImage {
        let pixelW = targetPointSize.width * scale
        let pixelH = targetPointSize.height * scale
        let size = CGSize(width: pixelW, height: pixelH)
        let renderer = UIGraphicsImageRenderer(size: size)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        // 压缩为 JPEG；从 JPEG data 重新创建 UIImage，
        // 使 CGImage 的 data provider 持有 JPEG 编码数据，
        // PDF 渲染器会直接嵌入压缩流而非 raw bitmap。
        guard let jpegData = resized.jpegData(compressionQuality: 0.65),
              let compressed = UIImage(data: jpegData) else {
            return resized
        }
        return compressed
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

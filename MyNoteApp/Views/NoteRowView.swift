import SwiftUI

// MARK: - 记录列表卡片

/// 记录列表行视图（自适应内容 + 附件的卡片样式）
struct NoteRowView: View {
    let note: NoteItem
    var showDateFooter: Bool = true
    @Environment(\.appTheme) private var theme
    @Environment(NoteStore.self) private var noteStore

    /// 可视类型附件（图片、视频、扫描文稿、涂鸦）
    private var visualAttachments: [AttachmentItem] {
        note.attachments
            .filter { [.photo, .video, .scannedDocument, .drawing].contains($0.type) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// 非可视类型附件（录音、文件、位置、扫描文本）
    private var otherAttachments: [AttachmentItem] {
        note.attachments
            .filter { ![.photo, .video, .scannedDocument, .drawing].contains($0.type) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NoteCardTextSummary(note: note)
                .padding(.bottom, 10)

            // ── 图片 / 视频马赛克 ─────────────────────────────
            if !visualAttachments.isEmpty {
                visualGrid
                    .padding(.bottom, 8)
            }

            // ── 其他附件 chips ────────────────────────────────
            if !otherAttachments.isEmpty {
                otherChipsRow
                    .padding(.bottom, 8)
            }

            // ── 底部日期 ──────────────────────────────────────
            if showDateFooter {
                Spacer(minLength: 6)
                footerMetaRow
            }
        }
        .padding(12)
        .frame(minHeight: 140)
        .background(theme.colors.card)
        .cornerRadius(12)
    }

    // MARK: - 底部元信息

    @ViewBuilder
    private var footerMetaRow: some View {
        HStack(alignment: .center, spacing: 8) {
            if !note.tags.isEmpty {
                HStack(spacing: 5) {
                    ForEach(Array(note.tags.prefix(1)), id: \.id) { tag in
                        HStack(spacing: 3) {
                            Image(systemName: "tag.fill")
                                .font(.system(size: 6))
                            Text(tag.name)
                                .font(.system(size: 9, weight: .medium))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(theme.colors.cardSecondary.opacity(0.85))
                        .foregroundColor(theme.colors.secondaryText.opacity(0.82))
                        .clipShape(Capsule())
                    }

                    if note.tags.count > 1 {
                        Text("+\(note.tags.count - 1)")
                            .font(.caption2)
                            .foregroundColor(theme.colors.secondaryText.opacity(0.7))
                    }
                }
                .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(note.updatedAt.formattedAbsolute)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - 可视附件马赛克

    @ViewBuilder
    private var visualGrid: some View {
        let imgs = Array(visualAttachments.prefix(4))
        let overflow = visualAttachments.count - 4

        switch imgs.count {
        case 1:
            // 单图：全宽，适度高度
            CardThumbnail(attachment: imgs[0])
                .frame(maxWidth: .infinity)
                .frame(height: 150)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8))

        case 2:
            // 双图：并排等宽
            HStack(spacing: 4) {
                ForEach(imgs) { att in
                    CardThumbnail(attachment: att)
                        .frame(maxWidth: .infinity)
                        .frame(height: 105)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
            }

        default:
            // 3-4 张：左侧大图 + 右侧纵列
            let lead   = imgs[0]
            let rest   = Array(imgs.dropFirst())
            let slotH  = (150.0 - CGFloat(rest.count - 1) * 4) / CGFloat(rest.count)

            HStack(alignment: .top, spacing: 4) {
                CardThumbnail(attachment: lead)
                    .frame(maxWidth: .infinity)
                    .frame(height: 150)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                VStack(spacing: 4) {
                    ForEach(Array(rest.enumerated()), id: \.element.id) { idx, att in
                        ZStack {
                            CardThumbnail(attachment: att)
                                .frame(maxWidth: .infinity)
                                .frame(height: slotH)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 6))

                            // 最后一格显示溢出数
                            if idx == rest.count - 1, overflow > 0 {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(.black.opacity(0.45))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: slotH)
                                Text("+\(overflow)")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - 其他附件 Chips

    @ViewBuilder
    private var otherChipsRow: some View {
        let shown = Array(otherAttachments.prefix(5))
        let extra = otherAttachments.count - shown.count
        HStack(spacing: 5) {
            ForEach(shown) { att in
                HStack(spacing: 3) {
                    Image(systemName: att.type.iconName)
                        .font(.system(size: 9))
                    Text(att.type.displayName)
                        .font(.system(size: 10))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(theme.colors.cardSecondary)
                .foregroundColor(theme.colors.secondaryText)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            if extra > 0 {
                Text("+\(extra)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }
}

struct NoteCardTextSummary: View {
    let note: NoteItem
    var compact: Bool = false

    @Environment(\.appTheme) private var theme
    @Environment(FontManager.self) private var fontManager

    private var summary: NotePreviewSummary { NotePreviewSummary(note: note) }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 5) {
            if let headline = summary.headline {
                Text(headline)
                    .font(Font(fontManager.bodyFont(textStyle: compact ? .footnote : .subheadline)).weight(.semibold))
                    .foregroundColor(theme.colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            switch summary.style {
            case .standard:
                standardContent

            case .checklist:
                checklistContent

            case .table:
                tableContent

            case .quote:
                quoteContent
            }

            if let supportText = summary.supportText,
               let supportIcon = summary.supportIcon {
                Label(supportText, systemImage: supportIcon)
                    .font(Font(fontManager.bodyFont(size: 11)))
                    .foregroundColor(theme.colors.secondaryText.opacity(0.78))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var standardContent: some View {
        if !summary.excerpt.isEmpty {
            Text(summary.excerpt)
                .font(Font(fontManager.bodyFont(textStyle: summary.headline == nil && !compact ? .subheadline : .footnote)))
                .foregroundColor(summary.headline == nil ? theme.colors.primaryText : theme.colors.secondaryText)
                .lineLimit(summary.headline == nil ? (compact ? 3 : 3) : 2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var checklistContent: some View {
        if summary.headline == nil, !summary.excerpt.isEmpty {
            Text(summary.excerpt)
                .font(Font(fontManager.bodyFont(textStyle: compact ? .footnote : .subheadline)))
                .foregroundColor(theme.colors.primaryText)
                .lineLimit(2)
        } else if !summary.excerpt.isEmpty {
            Text(summary.excerpt)
                .font(Font(fontManager.bodyFont(textStyle: .footnote)))
                .foregroundColor(theme.colors.secondaryText)
                .lineLimit(2)
        }

        ForEach(Array(summary.detailLines.prefix(compact ? 2 : 2)), id: \.self) { item in
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "circle")
                    .font(.system(size: 7))
                    .foregroundColor(theme.colors.accent.opacity(0.85))
                Text(item)
                    .font(Font(fontManager.bodyFont(size: compact ? 11 : 12)))
                    .foregroundColor(theme.colors.secondaryText)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var tableContent: some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: summary.badgeIcon ?? "tablecells")
                .font(.system(size: compact ? 11 : 12, weight: .medium))
                .foregroundColor(theme.colors.accent)
            Text(summary.excerpt)
                .font(Font(fontManager.bodyFont(size: compact ? 11 : 12)).weight(.medium))
                .foregroundColor(summary.headline == nil ? theme.colors.primaryText : theme.colors.secondaryText)
                .lineLimit(1)
        }

        if let first = summary.detailLines.first {
            Text(first)
                .font(Font(fontManager.bodyFont(size: 11)))
                .foregroundColor(theme.colors.secondaryText.opacity(0.82))
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var quoteContent: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(summary.excerpt)
                .font(Font(fontManager.bodyFont(textStyle: summary.headline == nil && !compact ? .subheadline : .footnote)).italic())
                .foregroundColor(summary.headline == nil ? theme.colors.primaryText : theme.colors.secondaryText)
                .lineLimit(compact ? 2 : 3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(theme.colors.accent.opacity(0.7))
                        .frame(width: 3)
                }

            if let first = summary.detailLines.first {
                Text(first)
                    .font(Font(fontManager.bodyFont(size: 11)))
                    .foregroundColor(theme.colors.secondaryText.opacity(0.78))
                    .lineLimit(1)
            }
        }
    }
}

struct NotePreviewSummary {
    enum Style {
        case standard
        case checklist
        case table
        case quote
    }

    let style: Style
    let headline: String?
    let excerpt: String
    let detailLines: [String]
    let supportText: String?
    let supportIcon: String?
    let badgeIcon: String?

    init(note: NoteItem) {
        let entries = Self.parseEntries(from: note.content)
        let checklistItems = entries.filter { if case .checkbox = $0.kind { return true } else { return false } }
        let uncheckedItems = checklistItems.compactMap { entry -> String? in
            if case .checkbox(let checked) = entry.kind, !checked {
                return entry.text
            }
            return nil
        }
        let completedCount = checklistItems.filter { entry in
            if case .checkbox(let checked) = entry.kind {
                return checked
            }
            return false
        }.count

        let headingEntry = entries.first(where: { if case .heading = $0.kind { return true } else { return false } })
        let contentEntries: [Entry]
        if let headingEntry, entries.first?.text == headingEntry.text {
            contentEntries = Array(entries.dropFirst())
        } else {
            contentEntries = entries
        }
        let primaryEntry = contentEntries.first ?? entries.first
        let secondaryEntry = contentEntries.dropFirst().first(where: { !$0.text.isEmpty })
        let primaryText = primaryEntry?.text ?? note.preview
        let secondaryText = secondaryEntry?.text

        switch primaryEntry?.kind {
        case .table:
            style = .table
            headline = headingEntry?.text
            excerpt = primaryText.isEmpty ? "表格内容" : primaryText
            detailLines = [Self.tableMetricsText(from: contentEntries)]
            badgeIcon = "tablecells"

        case .quote:
            style = .quote
            headline = headingEntry?.text
            excerpt = primaryText.isEmpty ? (note.preview.isEmpty ? "空白笔记" : note.preview) : primaryText
            detailLines = secondaryText.map { [$0] } ?? []
            badgeIcon = "quote.opening"

        case .checkbox, .bullet, .numbered where checklistItems.count >= 2 || (primaryEntry?.isChecklistLike ?? false):
            style = .checklist
            headline = headingEntry?.text
            excerpt = headingEntry == nil ? (secondaryText ?? primaryText) : ""
            detailLines = Array((uncheckedItems.isEmpty ? checklistItems.map(\.text) : uncheckedItems).prefix(2))
            badgeIcon = "checklist"

        default:
            style = .standard
            if let headingEntry {
                headline = headingEntry.text
                excerpt = secondaryText ?? primaryText
            } else if let primaryEntry,
                      case .paragraph = primaryEntry.kind,
                      primaryEntry.text.count <= 24,
                      secondaryText != nil {
                headline = primaryEntry.text
                excerpt = secondaryText ?? ""
            } else {
                headline = nil
                excerpt = Self.mergeExcerpt(primary: primaryText, secondary: secondaryText)
            }
            detailLines = []
            badgeIcon = nil
        }

        if style == .checklist {
            supportText = "已完成 \(completedCount)/\(checklistItems.count) 项"
            supportIcon = "checklist"
        } else if style == .table {
            supportText = Self.tableMetricsText(from: contentEntries)
            supportIcon = "tablecells"
        } else if note.attachments.count > 0 {
            supportText = Self.attachmentSummary(note.attachments)
            supportIcon = note.attachments.first?.type.iconName ?? "paperclip"
        } else {
            supportText = nil
            supportIcon = nil
        }
    }

    private enum EntryKind {
        case heading
        case paragraph
        case bullet
        case checkbox(Bool)
        case numbered
        case quote
        case table
    }

    private struct Entry {
        let text: String
        let kind: EntryKind

        var isChecklistLike: Bool {
            switch kind {
            case .checkbox, .bullet, .numbered:
                return true
            default:
                return false
            }
        }
    }

    private static func mergeExcerpt(primary: String, secondary: String?) -> String {
        guard let secondary, !secondary.isEmpty, secondary != primary else {
            return primary
        }
        return "\(primary)\n\(secondary)"
    }

    private static func attachmentSummary(_ attachments: [AttachmentItem]) -> String {
        guard !attachments.isEmpty else { return "" }
        let grouped = Dictionary(grouping: attachments, by: \.type)
        if grouped.count == 1, let type = attachments.first?.type {
            return "\(attachments.count) 个\(type.displayName)"
        }
        return "\(attachments.count) 个附件"
    }

    private static func tableMetricsText(from entries: [Entry]) -> String {
        let tableCount = entries.filter { if case .table = $0.kind { return true } else { return false } }.count
        return tableCount > 1 ? "包含 \(tableCount) 个表格区块" : "结构化表格预览"
    }

    private static func parseEntries(from content: String, limit: Int = 6) -> [Entry] {
        let lines = content.components(separatedBy: "\n")
        var result: [Entry] = []
        var index = 0

        while index < lines.count, result.count < limit {
            let raw = lines[index]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let fence = trimmed.hasPrefix("```") ? "```" : "~~~"
                index += 1
                while index < lines.count, !lines[index].hasPrefix(fence) {
                    index += 1
                }
                index += 1
                continue
            }

            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                index += 1
                continue
            }

            if trimmed.allSatisfy({ $0 == "-" || $0 == "_" || $0 == "*" || $0 == " " }) {
                index += 1
                continue
            }

            if let match = trimmed.range(of: "^#{1,6} ", options: .regularExpression) {
                let text = String(trimmed[match.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !text.isEmpty {
                    result.append(Entry(text: cleanInline(text), kind: .heading))
                }
                index += 1
                continue
            }

            if trimmed.hasPrefix("- [ ] ") {
                result.append(Entry(text: cleanInline(String(trimmed.dropFirst(6))), kind: .checkbox(false)))
                index += 1
                continue
            }

            if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
                result.append(Entry(text: cleanInline(String(trimmed.dropFirst(6))), kind: .checkbox(true)))
                index += 1
                continue
            }

            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                result.append(Entry(text: cleanInline(String(trimmed.dropFirst(2))), kind: .bullet))
                index += 1
                continue
            }

            if let range = trimmed.range(of: "^\\d+\\.\\s", options: .regularExpression) {
                let text = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                result.append(Entry(text: cleanInline(text), kind: .numbered))
                index += 1
                continue
            }

            if trimmed.hasPrefix("> ") {
                result.append(Entry(text: cleanInline(String(trimmed.dropFirst(2))), kind: .quote))
                index += 1
                continue
            }

            if isTableLine(trimmed), index + 1 < lines.count, isSeparatorLine(lines[index + 1]) {
                let headers = tableRow(trimmed).filter { !$0.isEmpty }
                let headerText = headers.isEmpty ? "表格内容" : headers.joined(separator: " / ")
                result.append(Entry(text: cleanInline(headerText), kind: .table))
                index += 2
                while index < lines.count, isTableLine(lines[index]) {
                    index += 1
                }
                continue
            }

            result.append(Entry(text: cleanInline(trimmed), kind: .paragraph))
            index += 1
        }

        return result.filter { !$0.text.isEmpty }
    }

    private static func cleanInline(_ text: String) -> String {
        var value = text
        value = value.replacingOccurrences(of: "\\*\\*(.+?)\\*\\*", with: "$1", options: .regularExpression)
        value = value.replacingOccurrences(of: "\\*(.+?)\\*", with: "$1", options: .regularExpression)
        value = value.replacingOccurrences(of: "~~(.+?)~~", with: "$1", options: .regularExpression)
        value = value.replacingOccurrences(of: "`([^`]+)`", with: "$1", options: .regularExpression)
        value = value.replacingOccurrences(of: "!\\[.*?\\]\\(.*?\\)", with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: "\\[(.+?)\\]\\(.*?\\)", with: "$1", options: .regularExpression)
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func tableRow(_ line: String) -> [String] {
        line.split(separator: "|", omittingEmptySubsequences: false)
            .dropFirst()
            .dropLast()
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func isTableLine(_ line: String) -> Bool {
        line.contains("|") && !line.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func isSeparatorLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return false }
        return trimmed.replacingOccurrences(of: "|", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ":", with: "")
            .trimmingCharacters(in: .whitespaces)
            .isEmpty
    }
}

// MARK: - 卡片内容预览（按块解析 Markdown + 底部渐隐）

struct NoteCardPreview: View {
    let content: String
    @Environment(\.appTheme) private var theme
    @Environment(FontManager.self) private var fontManager
    // ── 预览块类型 ────────────────────────────────────────
    private enum PreviewBlock {
        case title(String)
        case heading(level: Int, text: String)
        case paragraph(String)
        case bullet(String)
        case numbered(index: String, text: String)
        case checkbox(checked: Bool, text: String)
        case blockquote(String)
        case table(headers: [String], rows: [[String]])
    }

    // ── 工具：解析表格单元格 ──────────────────────────────
    private func tableRow(_ line: String) -> [String] {
        line.split(separator: "|", omittingEmptySubsequences: false)
            .dropFirst().dropLast()   // 去掉首尾空元素
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
    private func isTableLine(_ line: String) -> Bool {
        line.contains("|") && !line.trimmingCharacters(in: .whitespaces).isEmpty
    }
    private func isSeparatorLine(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.contains("|") else { return false }
        return t.replacingOccurrences(of: "|", with: "")
                .replacingOccurrences(of: "-", with: "")
                .replacingOccurrences(of: ":", with: "")
                .trimmingCharacters(in: .whitespaces).isEmpty
    }

    // ── 解析（最多 10 块，跳过代码围栏） ──────────────────
    private var blocks: [PreviewBlock] {
        var result: [PreviewBlock] = []
        var titleConsumed = false
        let lines = content.components(separatedBy: "\n")
        var i = 0

        while i < lines.count, result.count < 10 {
            let raw = lines[i]
            let t   = raw.trimmingCharacters(in: .whitespaces)

            // 空行
            if t.isEmpty { i += 1; continue }

            // 代码围栏：整块跳过
            if t.hasPrefix("```") || t.hasPrefix("~~~") {
                let fence = t.hasPrefix("```") ? "```" : "~~~"
                i += 1
                while i < lines.count, !lines[i].hasPrefix(fence) { i += 1 }
                i += 1; continue
            }

            // 分割线
            if t == "---" || t == "***" || t == "___" { i += 1; continue }

            // 纯符号行（如 `* * *`）
            if t.allSatisfy({ $0 == "-" || $0 == "_" || $0 == "*" || $0 == " " }) { i += 1; continue }

            // 标题 # ... ######
            if let m = t.range(of: #"^#{1,6} "#, options: .regularExpression) {
                let level = t[t.startIndex ..< m.upperBound].filter { $0 == "#" }.count
                let text  = String(t[m.upperBound...])
                if !titleConsumed {
                    result.append(.title(text)); titleConsumed = true
                } else {
                    result.append(.heading(level: level, text: text))
                }
                i += 1; continue
            }

            // 引用块
            if t.hasPrefix("> ") {
                result.append(.blockquote(String(t.dropFirst(2))))
                i += 1; continue
            }

            // Checkbox（必须在 bullet 之前检测）
            if t.hasPrefix("- [ ] ") {
                result.append(.checkbox(checked: false, text: String(t.dropFirst(6))))
                i += 1; continue
            }
            if t.hasPrefix("- [x] ") || t.hasPrefix("- [X] ") {
                result.append(.checkbox(checked: true, text: String(t.dropFirst(6))))
                i += 1; continue
            }

            // 无序列表
            if t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("+ ") {
                result.append(.bullet(String(t.dropFirst(2))))
                i += 1; continue
            }

            // 有序列表
            if let r = t.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                let idx  = String(t[t.startIndex ..< r.upperBound]).trimmingCharacters(in: .init(charactersIn: " "))
                let text = String(t[r.upperBound...])
                result.append(.numbered(index: idx, text: text))
                i += 1; continue
            }

            // 表格：首行含 |，第二行是分隔行
            if isTableLine(t), i + 1 < lines.count, isSeparatorLine(lines[i + 1]) {
                let headers = tableRow(t)
                i += 2 // 跳过分隔行
                var rows: [[String]] = []
                while i < lines.count, isTableLine(lines[i]) {
                    rows.append(tableRow(lines[i]))
                    i += 1
                }
                result.append(.table(headers: headers, rows: rows))
                continue
            }

            // 普通段落
            if !titleConsumed {
                result.append(.title(t)); titleConsumed = true
            } else {
                result.append(.paragraph(t))
            }
            i += 1
        }
        return result
    }

    // ── 视图 ─────────────────────────────────────────────
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockRow(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mask(
            VStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 22)
            }
        )
    }

    @ViewBuilder
    private func blockRow(_ block: PreviewBlock) -> some View {
        switch block {

        case .title(let text):
            Text(inline(text))
                .font(Font(fontManager.bodyFont(textStyle: .subheadline)).weight(.semibold))
                .foregroundColor(theme.colors.primaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

        case .heading(_, let text):
            Text(inline(text))
                .font(Font(fontManager.bodyFont(textStyle: .footnote)).weight(.semibold))
                .foregroundColor(theme.colors.primaryText)
                .lineLimit(1)

        case .paragraph(let text):
            Text(inline(text))
                .font(Font(fontManager.bodyFont(textStyle: .footnote)))
                .foregroundColor(theme.colors.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("•")
                    .font(Font(fontManager.bodyFont(textStyle: .footnote)))
                    .foregroundColor(theme.colors.secondaryText)
                Text(inline(text))
                    .font(Font(fontManager.bodyFont(textStyle: .footnote)))
                    .foregroundColor(theme.colors.secondaryText)
                    .lineLimit(1)
            }

        case .numbered(let idx, let text):
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(idx)
                    .font(Font(fontManager.bodyFont(textStyle: .footnote)))
                    .foregroundColor(theme.colors.secondaryText)
                    .frame(minWidth: 16, alignment: .trailing)
                Text(inline(text))
                    .font(Font(fontManager.bodyFont(textStyle: .footnote)))
                    .foregroundColor(theme.colors.secondaryText)
                    .lineLimit(1)
            }

        case .checkbox(let checked, let text):
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 11))
                    .foregroundColor(checked ? theme.colors.accent : theme.colors.secondaryText)
                Text(inline(text))
                    .font(Font(fontManager.bodyFont(textStyle: .footnote)))
                    .foregroundColor(checked
                        ? theme.colors.secondaryText.opacity(0.5)
                        : theme.colors.secondaryText)
                    .strikethrough(checked, color: theme.colors.secondaryText.opacity(0.4))
                    .lineLimit(1)
            }

        case .blockquote(let text):
            Text(inline(text))
                .font(Font(fontManager.bodyFont(textStyle: .footnote)).italic())
                .foregroundColor(theme.colors.secondaryText.opacity(0.8))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 9)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(theme.colors.accent.opacity(0.7))
                        .frame(width: 3)
                }

        case .table(let headers, let rows):
            PreviewTable(headers: headers, rows: rows)
        }
    }

    /// 每块独立解析 inline Markdown → AttributedString（一块出错不影响其他块）
    private func inline(_ raw: String) -> AttributedString {
        let opts = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: raw, options: opts)) ?? AttributedString(raw)
    }
}

// MARK: - 卡片内预览表格

private struct PreviewTable: View {
    let headers: [String]
    let rows: [[String]]
    @Environment(\.appTheme) private var theme
    @Environment(FontManager.self) private var fontManager
    // 最多展示 3 列、3 行，避免卡片过宽
    private var displayHeaders: [String] { Array(headers.prefix(3)) }
    private var displayRows: [[String]] {
        rows.prefix(3).map { Array($0.prefix(3)) }
    }
    private var colCount: Int { displayHeaders.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 表头
            tableRowView(cells: displayHeaders, isHeader: true)
            Divider().background(theme.colors.secondaryText.opacity(0.25))
            // 数据行
            ForEach(Array(displayRows.enumerated()), id: \.offset) { idx, row in
                tableRowView(cells: row, isHeader: false)
                if idx < displayRows.count - 1 {
                    Divider().background(theme.colors.secondaryText.opacity(0.12))
                }
            }
            // 省略提示
            if rows.count > 3 || headers.count > 3 {
                Text("… 共 \(rows.count) 行")
                    .font(.system(size: 9))
                    .foregroundColor(theme.colors.secondaryText.opacity(0.5))
                    .padding(.top, 3)
            }
        }
        .padding(6)
        .background(theme.colors.cardSecondary.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func tableRowView(cells: [String], isHeader: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(0 ..< colCount, id: \.self) { col in
                let cell = col < cells.count ? cells[col] : ""
                Text(cell)
                    .font(isHeader
                          ? Font(fontManager.bodyFont(size: 10)).weight(.semibold)
                          : Font(fontManager.bodyFont(size: 10)))
                    .foregroundColor(isHeader
                                     ? theme.colors.primaryText
                                     : theme.colors.secondaryText)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 3)
                if col < colCount - 1 {
                    Divider().background(theme.colors.secondaryText.opacity(0.15))
                }
            }
        }
    }
}

// MARK: - 卡片缩略图（异步加载 + 渐入）

private struct CardThumbnail: View {
    let attachment: AttachmentItem
    @Environment(NoteStore.self) private var noteStore
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geo in
            Group {
                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        // 固定为容器的精确尺寸，让 SwiftUI 以中心为基准裁切
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .transition(.opacity.animation(.easeIn(duration: 0.2)))
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.10))
                        .frame(width: geo.size.width, height: geo.size.height)
                        .overlay(
                            Image(systemName: attachment.type.iconName)
                                .font(.system(size: 22))
                                .foregroundColor(.secondary.opacity(0.4))
                        )
                }
            }
        }
        .onAppear { load() }
    }

    private func load() {
        guard image == nil else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            var loaded: UIImage?

            if let thumbURL = noteStore.thumbnailURL(for: attachment),
               let data = try? Data(contentsOf: thumbURL)
            {
                loaded = UIImage(data: data)
            }

            if loaded == nil {
                let url = noteStore.attachmentURL(for: attachment)
                if let data = try? Data(contentsOf: url) {
                    loaded = UIImage(data: data)
                }
            }

            if let result = loaded {
                DispatchQueue.main.async { image = result }
            }
        }
    }
}

// MARK: - 附件小图标（供其他视图复用）

struct AttachmentMiniIcon: View {
    let type: AttachmentType
    @Environment(\.appTheme) private var theme

    var body: some View {
        Image(systemName: type.iconName)
            .font(.system(size: 10))
            .foregroundColor(.secondary)
            .frame(width: 22, height: 22)
            .background(theme.colors.cardSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

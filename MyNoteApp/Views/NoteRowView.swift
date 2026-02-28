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

            // ── 标签行 ──────────────────────────────────────
            if !note.tags.isEmpty {
                tagsRow
                    .padding(.bottom, 8)
            }

            // ── 渲染内容预览 ─────────────────────────────────
            NoteCardPreview(content: note.content)
                .padding(.bottom, 10)

            // ── 图片 / 视频马赛克 ─────────────────────────────
            if !visualAttachments.isEmpty {
                visualGrid
                    .padding(.bottom, otherAttachments.isEmpty ? 8 : 6)
            }

            // ── 其他附件 chips ────────────────────────────────
            if !otherAttachments.isEmpty {
                otherChipsRow
                    .padding(.bottom, 8)
            }

            // ── 底部日期 ──────────────────────────────────────
            if showDateFooter {
                Spacer(minLength: 0)
                HStack {
                    Spacer()
                    Text(note.updatedAt.formattedAbsolute)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(12)
        .frame(minHeight: 140)
        .background(theme.colors.card)
        .cornerRadius(12)
    }

    // MARK: - 标签 Pills

    @ViewBuilder
    private var tagsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(Array(note.tags.prefix(6)), id: \.id) { tag in
                    HStack(spacing: 3) {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 8))
                        Text(tag.name)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(theme.colors.accentSoft)
                    .foregroundColor(theme.colors.accent)
                    .clipShape(Capsule())
                }
                if note.tags.count > 6 {
                    Text("+\(note.tags.count - 6)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
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

// MARK: - 卡片内容预览（按块解析 Markdown + 底部渐隐）

struct NoteCardPreview: View {
    let content: String
    @Environment(\.appTheme) private var theme

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
                .font(.subheadline.weight(.semibold))
                .foregroundColor(theme.colors.primaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

        case .heading(_, let text):
            Text(inline(text))
                .font(.footnote.weight(.semibold))
                .foregroundColor(theme.colors.primaryText)
                .lineLimit(1)

        case .paragraph(let text):
            Text(inline(text))
                .font(.footnote)
                .foregroundColor(theme.colors.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("•")
                    .font(.footnote)
                    .foregroundColor(theme.colors.secondaryText)
                Text(inline(text))
                    .font(.footnote)
                    .foregroundColor(theme.colors.secondaryText)
                    .lineLimit(1)
            }

        case .numbered(let idx, let text):
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(idx)
                    .font(.footnote)
                    .foregroundColor(theme.colors.secondaryText)
                    .frame(minWidth: 16, alignment: .trailing)
                Text(inline(text))
                    .font(.footnote)
                    .foregroundColor(theme.colors.secondaryText)
                    .lineLimit(1)
            }

        case .checkbox(let checked, let text):
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 11))
                    .foregroundColor(checked ? theme.colors.accent : theme.colors.secondaryText)
                Text(inline(text))
                    .font(.footnote)
                    .foregroundColor(checked
                        ? theme.colors.secondaryText.opacity(0.5)
                        : theme.colors.secondaryText)
                    .strikethrough(checked, color: theme.colors.secondaryText.opacity(0.4))
                    .lineLimit(1)
            }

        case .blockquote(let text):
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(theme.colors.accent.opacity(0.7))
                    .frame(width: 3)
                Text(inline(text))
                    .font(.footnote.italic())
                    .foregroundColor(theme.colors.secondaryText.opacity(0.8))
                    .lineLimit(1)
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
                          ? .system(size: 10, weight: .semibold)
                          : .system(size: 10))
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

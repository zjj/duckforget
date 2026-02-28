import SwiftUI
import SwiftData

// MARK: - Widget 单条记录卡片

/// 用于 TagWidget / RecentNotesWidget 横向滚动区域的单张卡片
/// 根据 WidgetSize 自适应尺寸、内容密度和图片渲染
struct WidgetNoteCard: View {
    let note: NoteItem
    let size: WidgetSize
    @Environment(NoteStore.self) private var noteStore
    @Environment(\.appTheme) private var theme

    // 第一个可视附件（用于图片卡）
    private var visualAttachment: AttachmentItem? {
        note.attachments
            .filter { [.photo, .video, .scannedDocument, .drawing].contains($0.type) }
            .sorted { $0.createdAt < $1.createdAt }
            .first
    }

    // 非可视附件图标（large 模式展示 chips）
    private var otherAttachments: [AttachmentItem] {
        note.attachments
            .filter { ![.photo, .video, .scannedDocument, .drawing].contains($0.type) }
    }

    // ── 卡片尺寸 ────────────────────────────────────────
    private var cardWidth: CGFloat {
        switch size {
        case .small:    return 105
        case .medium:   return 145
        case .large:    return 160
        case .fullPage: return 160
        }
    }
    private var cardHeight: CGFloat {
        switch size {
        case .small:    return 50
        case .medium:   return 95
        case .large:    return 128
        case .fullPage: return 128
        }
    }

    var body: some View {
        if size == .small {
            // small：紧凑文字卡
            Group {
                if let att = visualAttachment {
                    photoCard(attachment: att)
                } else {
                    textCard
                }
            }
            .frame(width: cardWidth, height: cardHeight)
            .background(theme.colors.card)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            // medium / large：与列表网格卡片样式一致，固定尺寸裁切
            NoteRowView(note: note)
                .environment(noteStore)
                .frame(width: cardWidth, height: cardHeight, alignment: .top)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // ── 有图片：图片全填 + 渐变遮罩 + 文字底部 ────────────
    @ViewBuilder
    private func photoCard(attachment att: AttachmentItem) -> some View {
        ZStack(alignment: .bottom) {
            // 图片：GeometryReader 确保等比 center-crop
            GeometryReader { geo in
                WidgetCardThumbnail(attachment: att)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }

            // 底部渐变遮罩
            LinearGradient(
                colors: [.black.opacity(0.72), .black.opacity(0.15), .clear],
                startPoint: .bottom,
                endPoint: .top
            )
            .frame(height: cardHeight * (size == .large ? 0.6 : 0.75))

            // 文字层
            VStack(alignment: .leading, spacing: 2) {
                Text(inlineText(noteTitle))
                    .font(.system(size: titleFontSize, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(size == .large ? 2 : 1)
                    .fixedSize(horizontal: false, vertical: true)

                if size == .large, let body = noteBodyText {
                    Text(inlineText(body))
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(note.updatedAt.formattedAbsolute)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.55))
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // ── 无图片（或 small）：纯文字卡片 ────────────────────
    @ViewBuilder
    private var textCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 标题
            Text(inlineText(noteTitle))
                .font(.system(size: titleFontSize, weight: .semibold))
                .foregroundColor(theme.colors.primaryText)
                .lineLimit(size == .small ? 2 : (size == .medium ? 2 : 3))
                .fixedSize(horizontal: false, vertical: true)

            // 正文（medium / large）
            if size != .small, let body = noteBodyText {
                Text(inlineText(body))
                    .font(.system(size: 11))
                    .foregroundColor(theme.colors.secondaryText)
                    .lineLimit(size == .medium ? 2 : 4)
                    .fixedSize(horizontal: false, vertical: true)
                    .mask(
                        VStack(spacing: 0) {
                            Color.black
                            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                                .frame(height: 12)
                        }
                    )
            }

            Spacer(minLength: 0)

            // 其他附件 chips（large 模式）
            if size == .large, !otherAttachments.isEmpty {
                HStack(spacing: 4) {
                    ForEach(otherAttachments.prefix(3)) { att in
                        Image(systemName: att.type.iconName)
                            .font(.system(size: 9))
                            .padding(4)
                            .background(theme.colors.cardSecondary)
                            .foregroundColor(theme.colors.secondaryText)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }

            // 日期
            Text(note.updatedAt.formattedAbsolute)
                .font(.system(size: 9))
                .foregroundColor(theme.colors.secondaryText.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(8)
    }

    // ── 辅助 ─────────────────────────────────────────────
    private var titleFontSize: CGFloat {
        switch size {
        case .small:  return 11
        case .medium: return 12
        default:      return 13
        }
    }

    /// 从 content 提取首行标题（去掉 # 前缀）
    private var noteTitle: String {
        for line in note.content.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { continue }
            if t.hasPrefix("```") || t.hasPrefix("~~~") { break }
            if t.allSatisfy({ $0 == "-" || $0 == "_" || $0 == "*" || $0 == " " }) { continue }
            if t.hasPrefix("#") {
                return t.replacingOccurrences(of: #"^#{1,6} "#, with: "", options: .regularExpression)
            }
            return t
        }
        return note.preview
    }

    /// 从 content 提取紧随标题之后的第一个有效正文行
    private var noteBodyText: String? {
        var titleSeen = false
        var lines: [String] = []
        for line in note.content.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { continue }
            if t.hasPrefix("```") || t.hasPrefix("~~~") { break }
            if !titleSeen { titleSeen = true; continue }
            let cleaned = t
                .replacingOccurrences(of: #"^#{1,6} "#,   with: "", options: .regularExpression)
                .replacingOccurrences(of: #"^[>\-\*\+] "#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"^\d+\. "#,     with: "", options: .regularExpression)
                .replacingOccurrences(of: #"^- \[[ xX]\] "#, with: "", options: .regularExpression)
            if !cleaned.isEmpty { lines.append(cleaned) }
            if lines.count >= 3 { break }
        }
        return lines.isEmpty ? nil : lines.joined(separator: " ")
    }

    private func inlineText(_ raw: String) -> AttributedString {
        let opts = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: raw, options: opts)) ?? AttributedString(raw)
    }
}

// MARK: - Widget 卡片缩略图（异步加载，等比 center-crop）

private struct WidgetCardThumbnail: View {
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
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .transition(.opacity.animation(.easeIn(duration: 0.15)))
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.12))
                        .frame(width: geo.size.width, height: geo.size.height)
                        .overlay(
                            Image(systemName: attachment.type.iconName)
                                .font(.system(size: 18))
                                .foregroundColor(.secondary.opacity(0.35))
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
            if let url = noteStore.thumbnailURL(for: attachment),
               let data = try? Data(contentsOf: url) {
                loaded = UIImage(data: data)
            }
            if loaded == nil {
                let url = noteStore.attachmentURL(for: attachment)
                if let data = try? Data(contentsOf: url) { loaded = UIImage(data: data) }
            }
            if let result = loaded {
                DispatchQueue.main.async { image = result }
            }
        }
    }
}

// MARK: - 附件缩略图组件 (复用 NoteRowView 的逻辑)

struct WidgetAttachmentThumbnail: View {
    let attachment: AttachmentItem
    @Environment(NoteStore.self) var noteStore
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                AttachmentMiniIcon(type: attachment.type)
            }
        }
        .onAppear {
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        guard [.photo, .video, .scannedDocument, .scannedText, .drawing, .location].contains(attachment.type) else { return }
        
        DispatchQueue.global(qos: .userInitiated).async {
            var loadedImage: UIImage?
            
            // 优先加载缩略图
            if let thumbURL = noteStore.thumbnailURL(for: attachment),
               let data = try? Data(contentsOf: thumbURL) {
                loadedImage = UIImage(data: data)
            }
            
            // 回退到原图
            if loadedImage == nil {
                let url = noteStore.attachmentURL(for: attachment)
                if let data = try? Data(contentsOf: url) {
                    loadedImage = UIImage(data: data)
                }
            }
            
            if let result = loadedImage {
                DispatchQueue.main.async {
                    self.image = result
                }
            }
        }
    }
}

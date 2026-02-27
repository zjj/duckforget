import SwiftUI

// MARK: - Markdown 渲染视图

struct MarkdownRenderView: View {
    let content: String
    @Environment(\.appTheme) private var theme

    // 链接跳转确认
    @State private var pendingLinkURL: URL?
    @State private var showLinkConfirmation = false

    // Parsed block model
    private enum Block {
        case heading(level: Int, text: String)
        case codeBlock(lang: String, code: String)
        case blockquote(text: String)
        case bullet(text: String, indent: Int)
        case numbered(index: String, text: String)
        case checkbox(checked: Bool, text: String)
        case divider
        case paragraph(text: String)
        case blank
    }

    private var blocks: [Block] {
        var result: [Block] = []
        var lines = content.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]

            // Precompute trimmed info for bullet/checkbox detection (supports indented items)
            let leadingSpaces = line.prefix(while: { $0 == " " }).count
            let trimmedLine = leadingSpaces > 0 ? String(line.dropFirst(leadingSpaces)) : line

            // Code block
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                let fencePrefix = line.hasPrefix("```") ? "```" : "~~~"
                let lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].hasPrefix(fencePrefix) {
                    codeLines.append(lines[i])
                    i += 1
                }
                result.append(.codeBlock(lang: lang, code: codeLines.joined(separator: "\n")))
                i += 1
                continue
            }

            // Heading
            if line.hasPrefix("###### ") {
                result.append(.heading(level: 6, text: String(line.dropFirst(7))))
            } else if line.hasPrefix("##### ") {
                result.append(.heading(level: 5, text: String(line.dropFirst(6))))
            } else if line.hasPrefix("#### ") {
                result.append(.heading(level: 4, text: String(line.dropFirst(5))))
            } else if line.hasPrefix("### ") {
                result.append(.heading(level: 3, text: String(line.dropFirst(4))))
            } else if line.hasPrefix("## ") {
                result.append(.heading(level: 2, text: String(line.dropFirst(3))))
            } else if line.hasPrefix("# ") {
                result.append(.heading(level: 1, text: String(line.dropFirst(2))))

            // Blockquote
            } else if line.hasPrefix("> ") {
                result.append(.blockquote(text: String(line.dropFirst(2))))

            // Checkbox (must check before bullet; supports indented checkboxes)
            } else if trimmedLine.hasPrefix("- [ ] ") {
                result.append(.checkbox(checked: false, text: String(trimmedLine.dropFirst(6))))
            } else if trimmedLine.hasPrefix("- [x] ") || trimmedLine.hasPrefix("- [X] ") {
                result.append(.checkbox(checked: true, text: String(trimmedLine.dropFirst(6))))

            // Bullet list (supports indented bullets)
            } else if trimmedLine.hasPrefix("- ") || trimmedLine.hasPrefix("* ") || trimmedLine.hasPrefix("+ ") {
                result.append(.bullet(text: String(trimmedLine.dropFirst(2)), indent: leadingSpaces / 2))

            // Numbered list
            } else if let matchRange = line.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                let prefix = String(line[matchRange])
                let idx = String(prefix.dropLast(2))
                let text = String(line[matchRange.upperBound...])
                result.append(.numbered(index: idx + ".", text: text))

            // Divider
            } else if line == "---" || line == "***" || line == "___" {
                result.append(.divider)

            // Blank
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                result.append(.blank)

            // Paragraph
            } else {
                result.append(.paragraph(text: line))
            }

            i += 1
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .alert("即将离开应用", isPresented: $showLinkConfirmation) {
            Button("取消", role: .cancel) {
                pendingLinkURL = nil
            }
            Button("继续前往") {
                if let url = pendingLinkURL {
                    UIApplication.shared.open(url)
                }
                pendingLinkURL = nil
            }
        } message: {
            Text("您即将打开外部链接:\n\n \(pendingLinkURL?.absoluteString ?? "")\n\n本应用对外部网站的内容不承担任何责任，请注意个人信息安全。")
        }
    }

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {

        case .heading(let level, let text):
            inlineText(text)
                .font(headingFont(level))
                .fontWeight(level <= 2 ? .bold : .semibold)
                .foregroundColor(.primary)
                .padding(.top, level == 1 ? 8 : level == 2 ? 4 : 2)

        case .codeBlock(_, let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code.isEmpty ? " " : code)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundColor(.primary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(theme.colors.card)
            .cornerRadius(8)
            .padding(.vertical, 4)

        case .blockquote(let text):
            HStack(alignment: .top, spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(theme.colors.accent)
                    .frame(width: 3)
                inlineText(text)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 10)
            }
            .padding(.vertical, 2)

        case .bullet(let text, let indent):
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .foregroundColor(.secondary)
                    .padding(.leading, CGFloat(indent) * 16)
                inlineText(text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .numbered(let index, let text):
            HStack(alignment: .top, spacing: 6) {
                Text(index)
                    .foregroundColor(.secondary)
                    .frame(minWidth: 20, alignment: .trailing)
                inlineText(text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .checkbox(let checked, let text):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .foregroundColor(checked ? theme.colors.accent : theme.colors.secondaryText)
                    .font(.system(size: 15))
                inlineText(text)
                    .strikethrough(checked, color: .secondary)
                    .foregroundColor(checked ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .divider:
            Divider()
                .padding(.vertical, 6)

        case .blank:
            Color.clear.frame(height: 6)

        case .paragraph(let text):
            inlineText(text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Renders inline text with custom markdown formatting (bold, italic, strikethrough, code, links, images).
    @ViewBuilder
    private func inlineText(_ raw: String) -> some View {
        renderInlineMarkdown(raw)
    }
    
    /// Render inline markdown with actual interactive links and embedded images
    @ViewBuilder
    private func renderInlineMarkdown(_ raw: String) -> some View {
        let segments = parseInlineSegments(raw)
        
        if segments.isEmpty {
            Text("")
        } else {
            // Use HStack with wrapping for inline flow
            // For multiline content, wrap each segment in its own view
            flowLayout(segments: segments)
        }
    }
    
    /// Build a single AttributedString from inline text+link segments so they flow together.
    private func buildInlineAttributedString(from segments: [InlineSegment]) -> AttributedString {
        var result = AttributedString("")
        for segment in segments {
            switch segment {
            case .text(let attr):
                result += attr
            case .link(let displayText, let url):
                var linkAttr = AttributedString(displayText)
                linkAttr.foregroundColor = .blue
                if let parsed = URL(string: url) {
                    linkAttr.link = parsed
                }
                result += linkAttr
            case .image:
                break
            }
        }
        return result
    }

    @ViewBuilder
    private func flowLayout(segments: [InlineSegment]) -> some View {
        // Group inline (text+link) segments together; images break the flow into separate blocks
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(groupSegments(segments).enumerated()), id: \.offset) { _, group in
                switch group {
                case .inlineContent(let inlineSegments):
                    let combined = buildInlineAttributedString(from: inlineSegments)
                    Text(combined)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .environment(\.openURL, OpenURLAction { url in
                            pendingLinkURL = url
                            showLinkConfirmation = true
                            return .handled
                        })
                case .image(let alt, let url):
                    VStack(alignment: .leading, spacing: 4) {
                        // Only load local file:// URLs to avoid silent network requests.
                        // Remote http(s):// image URLs show a static placeholder instead.
                        if let parsed = URL(string: url), parsed.isFileURL {
                            AsyncImage(url: parsed) { phase in
                                switch phase {
                                case .empty:
                                    ProgressView()
                                        .frame(height: 200)
                                        .frame(maxWidth: .infinity)
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(maxWidth: .infinity)
                                        .cornerRadius(8)
                                case .failure:
                                    HStack {
                                        Image(systemName: "photo.badge.exclamationmark")
                                            .foregroundColor(.red)
                                        Text("图片加载失败")
                                            .foregroundColor(.secondary)
                                    }
                                    .frame(height: 100)
                                    .frame(maxWidth: .infinity)
                                @unknown default:
                                    EmptyView()
                                }
                            }
                        } else {
                            // Remote URL — show placeholder, never make spontaneous network requests
                            HStack(spacing: 6) {
                                Image(systemName: "photo")
                                    .foregroundColor(.secondary)
                                Text(alt.isEmpty ? url : alt)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(theme.colors.cardSecondary)
                            .cornerRadius(8)
                        }
                        if !alt.isEmpty {
                            Text(alt)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .italic()
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
    
    private enum SegmentGroup {
        /// Consecutive text and link segments rendered inline in a single Text view
        case inlineContent([InlineSegment])
        case image(alt: String, url: String)
    }
    
    /// Group segments so that text + links flow inline together; images break the flow.
    private func groupSegments(_ segments: [InlineSegment]) -> [SegmentGroup] {
        var groups: [SegmentGroup] = []
        var currentInline: [InlineSegment] = []
        
        for segment in segments {
            switch segment {
            case .text, .link:
                currentInline.append(segment)
            case .image(let alt, let url):
                if !currentInline.isEmpty {
                    groups.append(.inlineContent(currentInline))
                    currentInline = []
                }
                groups.append(.image(alt: alt, url: url))
            }
        }
        
        if !currentInline.isEmpty {
            groups.append(.inlineContent(currentInline))
        }
        
        return groups
    }
    
    private enum InlineSegment {
        case text(AttributedString)
        case link(displayText: String, url: String)
        case image(alt: String, url: String)
    }
    
    /// Parse inline markdown into segments (text, links, images)
    private func parseInlineSegments(_ raw: String) -> [InlineSegment] {
        var segments: [InlineSegment] = []
        var currentPos = raw.startIndex
        
        // First, find all links and images with their positions
        struct Match {
            let range: Range<String.Index>
            let type: MatchType
        }
        
        enum MatchType {
            case link(text: String, url: String)
            case image(alt: String, url: String)
        }
        
        var matches: [Match] = []
        
        // Find all links: [text](url)
        let linkPattern = #"(?<!!)\[([^\]]+)\]\(([^)]+)\)"#
        if let linkRegex = try? NSRegularExpression(pattern: linkPattern) {
            let nsString = raw as NSString
            let results = linkRegex.matches(in: raw, range: NSRange(location: 0, length: nsString.length))
            for match in results where match.numberOfRanges >= 3 {
                if let range = Range(match.range, in: raw),
                   let textRange = Range(match.range(at: 1), in: raw),
                   let urlRange = Range(match.range(at: 2), in: raw) {
                    let text = String(raw[textRange])
                    let url = String(raw[urlRange])
                    matches.append(Match(range: range, type: .link(text: text, url: url)))
                }
            }
        }
        
        // Find all images: ![alt](url)
        let imagePattern = #"!\[([^\]]*)\]\(([^)]+)\)"#
        if let imageRegex = try? NSRegularExpression(pattern: imagePattern) {
            let nsString = raw as NSString
            let results = imageRegex.matches(in: raw, range: NSRange(location: 0, length: nsString.length))
            for match in results where match.numberOfRanges >= 3 {
                if let range = Range(match.range, in: raw),
                   let altRange = Range(match.range(at: 1), in: raw),
                   let urlRange = Range(match.range(at: 2), in: raw) {
                    let alt = String(raw[altRange])
                    let url = String(raw[urlRange])
                    matches.append(Match(range: range, type: .image(alt: alt, url: url)))
                }
            }
        }
        
        // Sort matches by position
        matches.sort { $0.range.lowerBound < $1.range.lowerBound }
        
        // Build segments
        for match in matches {
            // Add text before this match
            if currentPos < match.range.lowerBound {
                let textPart = String(raw[currentPos..<match.range.lowerBound])
                if !textPart.isEmpty {
                    segments.append(.text(parseTextMarkdown(textPart)))
                }
            }
            
            // Add the match
            switch match.type {
            case .link(let text, let url):
                segments.append(.link(displayText: text, url: url))
            case .image(let alt, let url):
                segments.append(.image(alt: alt, url: url))
            }
            
            currentPos = match.range.upperBound
        }
        
        // Add remaining text
        if currentPos < raw.endIndex {
            let textPart = String(raw[currentPos..<raw.endIndex])
            if !textPart.isEmpty {
                segments.append(.text(parseTextMarkdown(textPart)))
            }
        }
        
        return segments
    }
    
    /// Parse text markdown (bold, italic, strikethrough, code) to AttributedString
    /// This is used for text segments that don't contain links or images
    /// In preview mode, markers are completely removed
    private func parseTextMarkdown(_ raw: String) -> AttributedString {
        let baseFont = UIFont.preferredFont(forTextStyle: .body)

        func boldItalicFont() -> UIFont {
            let traits: UIFontDescriptor.SymbolicTraits = [.traitBold, .traitItalic]
            let desc = baseFont.fontDescriptor.withSymbolicTraits(traits) ?? baseFont.fontDescriptor
            return UIFont(descriptor: desc, size: baseFont.pointSize)
        }
        func boldFont() -> UIFont {
            let desc = baseFont.fontDescriptor.withSymbolicTraits(.traitBold) ?? baseFont.fontDescriptor
            return UIFont(descriptor: desc, size: baseFont.pointSize)
        }
        func italicFont() -> UIFont {
            let desc = baseFont.fontDescriptor.withSymbolicTraits(.traitItalic) ?? baseFont.fontDescriptor
            return UIFont(descriptor: desc, size: baseFont.pointSize)
        }
        let codeFont = UIFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.9, weight: .regular)

        // Process markdown by removing markers and applying formatting
        var result = raw
        var ranges: [(range: NSRange, attrs: [NSAttributedString.Key: Any])] = []
        
        // Helper to process a markdown pattern and collect formatted ranges
        func processPattern(open: String, close: String, attrs: [NSAttributedString.Key: Any]) {
            func esc(_ s: String) -> String { NSRegularExpression.escapedPattern(for: s) }
            let pattern = "\(esc(open))(.+?)\(esc(close))"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return }
            
            var offset = 0
            let nsString = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsString.length))
            
            for match in matches.reversed() {
                guard match.numberOfRanges >= 2 else { continue }
                let fullRange = match.range
                let contentRange = match.range(at: 1)
                
                guard let fullSwiftRange = Range(fullRange, in: result),
                      let contentSwiftRange = Range(contentRange, in: result) else { continue }
                
                let content = String(result[contentSwiftRange])
                
                // Calculate new position after removing markers
                let openLen = (open as NSString).length
                let newStart = fullRange.location - offset
                let newRange = NSRange(location: newStart, length: content.count)
                
                // Store the attributes to apply later
                ranges.append((range: newRange, attrs: attrs))
                
                // Remove the markdown markers from the string
                result.replaceSubrange(fullSwiftRange, with: content)
                offset += openLen + (close as NSString).length
            }
        }
        
        // Process in longest-first order so ***x*** is caught before **x** or *x*
        processPattern(open: "***", close: "***", attrs: [.font: boldItalicFont()])
        processPattern(open: "___", close: "___", attrs: [.font: boldItalicFont()])
        processPattern(open: "**", close: "**", attrs: [.font: boldFont()])
        processPattern(open: "__", close: "__", attrs: [.font: boldFont()])
        processPattern(open: "*", close: "*", attrs: [.font: italicFont()])
        processPattern(open: "_", close: "_", attrs: [.font: italicFont()])
        processPattern(open: "~~", close: "~~", attrs: [
            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
            .foregroundColor: UIColor.secondaryLabel
        ])
        processPattern(open: "`", close: "`", attrs: [
            .font: codeFont,
            .backgroundColor: UIColor.tertiarySystemFill,
            .foregroundColor: UIColor.systemOrange
        ])
        
        // Build the final attributed string
        let nsAttr = NSMutableAttributedString(string: result)
        for (range, attrs) in ranges.reversed() {
            if range.location >= 0 && range.location + range.length <= nsAttr.length {
                nsAttr.addAttributes(attrs, range: range)
            }
        }
        
        return AttributedString(nsAttr)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title
        case 2: return .title2
        case 3: return .title3
        case 4: return .headline
        case 5: return .subheadline
        default: return .footnote
        }
    }
}

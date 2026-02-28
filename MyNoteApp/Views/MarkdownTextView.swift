import SwiftUI
import UIKit

// MARK: - MarkdownTextView

/// UITextView wrapper with live Markdown syntax highlighting and smart editing.
/// - Non-cursor lines: rich text rendering (headings large, prefixes subtle, bold/italic applied)
/// - Cursor line: syntax-highlighted raw markdown (prefixes colored, content in body font)
/// - Smart Enter: auto-continue lists, quotes, checkboxes
/// - Smart Backspace: delete entire prefix when cursor is right after it
struct MarkdownTextView: UIViewRepresentable {
    @Binding var text: String
    var isEditable: Bool = true
    var onFocusChange: ((Bool) -> Void)?
    var onLongPress: ((CGPoint) -> Void)?
    var onCoordinatorReady: ((Coordinator) -> Void)?
    var onCursorLineChanged: (() -> Void)?
    @Environment(\.appTheme) var theme

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.backgroundColor = .clear
        // Extra bottom padding to ensure cursor is visible above keyboard/toolbar
        tv.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 120, right: 4)
        tv.isScrollEnabled = true
        tv.alwaysBounceVertical = true
        tv.keyboardDismissMode = .interactive
        tv.isEditable = isEditable
        tv.allowsEditingTextAttributes = false
        tv.font = UIFont.preferredFont(forTextStyle: .body)
        tv.textColor = .label
        tv.autocorrectionType = .default
        context.coordinator.textView = tv

        // Long press gesture for format menu
        if onLongPress != nil {
            let lp = UILongPressGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coordinator.handleLongPress(_:))
            )
            lp.minimumPressDuration = 0.5  // Shorter than system's selection gesture
            lp.delegate = context.coordinator
            tv.addGestureRecognizer(lp)
            context.coordinator.longPressGesture = lp
        }

        // Initial content
        tv.text = text
        context.coordinator.applyHighlighting(tv)

        DispatchQueue.main.async {
            self.onCoordinatorReady?(context.coordinator)
        }
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.parent = self

        // Ensure delegate is always set correctly (e.g. after Settings changes cause
        // SwiftUI to re-invoke updateUIView, UIKit may have cleared the delegate).
        if uiView.delegate !== context.coordinator {
            uiView.delegate = context.coordinator
        }

        if uiView.isEditable != isEditable {
            uiView.isEditable = isEditable
        }

        // Re-apply highlighting when theme changes
        if context.coordinator.lastAppliedTheme != theme {
            context.coordinator.lastAppliedTheme = theme
            context.coordinator.applyHighlighting(uiView)
        }

        // Only update if text differs (external change, e.g. undo or voice input)
        guard uiView.text != text else { return }

        // 输入法合成期间不覆盖 UITextView 的文本，避免打断拼音/注音候选字显示
        if uiView.markedTextRange != nil { return }

        context.coordinator.isUpdatingFromBinding = true
        let saved = uiView.selectedRange

        // Use replace to preserve undo stack
        let fullLen = (uiView.text as NSString).length
        if let start = uiView.position(from: uiView.beginningOfDocument, offset: 0),
           let end = uiView.position(from: uiView.beginningOfDocument, offset: fullLen),
           let range = uiView.textRange(from: start, to: end) {
            uiView.replace(range, withText: text)
        }

        let maxPos = (text as NSString).length
        uiView.selectedRange = NSRange(location: min(saved.location, maxPos), length: 0)

        context.coordinator.applyHighlighting(uiView)
        context.coordinator.isUpdatingFromBinding = false
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var parent: MarkdownTextView
        weak var textView: UITextView?
        weak var longPressGesture: UILongPressGestureRecognizer?
        var isUpdatingFromBinding = false
        var isHighlighting = false
        private var previousCursorLine: Int = -1
        var lastAppliedTheme: AppTheme?

        var syntaxUIColor: UIColor {
            parent.theme == .system ? .systemOrange : UIColor(parent.theme.colors.syntaxKeyword)
        }
        var primaryUIColor: UIColor {
            parent.theme == .system ? .label : UIColor(parent.theme.colors.primaryText)
        }

        // Fonts (cached)
        private let bodyFont = UIFont.preferredFont(forTextStyle: .body)

        private lazy var h1Font: UIFont = UIFont.systemFont(ofSize: bodyFont.pointSize * 1.6, weight: .bold)
        private lazy var h2Font: UIFont = UIFont.systemFont(ofSize: bodyFont.pointSize * 1.35, weight: .bold)
        private lazy var h3Font: UIFont = UIFont.systemFont(ofSize: bodyFont.pointSize * 1.15, weight: .semibold)
        private lazy var h4Font: UIFont = UIFont.systemFont(ofSize: bodyFont.pointSize * 1.05, weight: .semibold)
        private lazy var h5Font: UIFont = UIFont.systemFont(ofSize: bodyFont.pointSize, weight: .semibold)
        private lazy var h6Font: UIFont = UIFont.systemFont(ofSize: bodyFont.pointSize * 0.95, weight: .semibold)

        private lazy var mdBoldFont: UIFont = {
            let desc = bodyFont.fontDescriptor.withSymbolicTraits(.traitBold) ?? bodyFont.fontDescriptor
            return UIFont(descriptor: desc, size: bodyFont.pointSize)
        }()

        private lazy var mdItalicFont: UIFont = {
            let desc = bodyFont.fontDescriptor.withSymbolicTraits(.traitItalic) ?? bodyFont.fontDescriptor
            return UIFont(descriptor: desc, size: bodyFont.pointSize)
        }()

        private lazy var mdBoldItalicFont: UIFont = {
            let traits: UIFontDescriptor.SymbolicTraits = [.traitBold, .traitItalic]
            let desc = bodyFont.fontDescriptor.withSymbolicTraits(traits) ?? bodyFont.fontDescriptor
            return UIFont(descriptor: desc, size: bodyFont.pointSize)
        }()

        private lazy var codeFont: UIFont = UIFont.monospacedSystemFont(ofSize: bodyFont.pointSize * 0.9, weight: .regular)

        private lazy var smallPrefixFont: UIFont = UIFont.systemFont(ofSize: bodyFont.pointSize * 0.55)

        init(_ parent: MarkdownTextView) {
            self.parent = parent
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let tv = textView else { return }
            // Convert press location to the text view's window coordinate space
            let locationInTV = gesture.location(in: tv)
            // Convert to the SwiftUI coordinate space via the window
            if let window = tv.window {
                let locationInWindow = tv.convert(locationInTV, to: window)
                parent.onLongPress?(locationInWindow)
            } else {
                parent.onLongPress?(locationInTV)
            }
        }

        // MARK: UIGestureRecognizerDelegate

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            // Allow our long press to work alongside system gestures
            return true
        }

        // MARK: UITextViewDelegate

        func textViewDidChange(_ textView: UITextView) {
            guard !isUpdatingFromBinding && !isHighlighting else { return }
            // 输入法合成期间（markedTextRange != nil）不回写 binding，
            // 避免将拼音/注音字母作为独立 undo 快照记录到 UndoRedoManager
            guard textView.markedTextRange == nil else { return }
            renumberLists(textView)
            parent.text = textView.text
            applyHighlighting(textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isUpdatingFromBinding && !isHighlighting else { return }
            let line = lineIndex(at: textView.selectedRange.location, in: textView.text as NSString)
            if line != previousCursorLine {
                previousCursorLine = line
                applyHighlighting(textView)
                parent.onCursorLineChanged?()
            }
            // Always scroll to keep cursor visible above toolbar
            scrollToCursor(textView)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.onFocusChange?(true)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.onFocusChange?(false)
            // Re-highlight all lines as rendered (no cursor line)
            previousCursorLine = -1
            applyHighlighting(textView)
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if text == "\n" {
                return handleEnterKey(textView, at: range)
            }
            if text.isEmpty && range.length == 1 {
                return handleBackspace(textView, at: range)
            }
            return true
        }

        // MARK: - Smart Enter

        private func handleEnterKey(_ textView: UITextView, at range: NSRange) -> Bool {
            let nsText = textView.text as NSString
            let lineRange = nsText.lineRange(for: range)
            let line = nsText.substring(with: lineRange).replacingOccurrences(of: "\n", with: "")

            // === Empty prefix → exit (delete prefix, leave empty line) ===

            let emptyPrefixes = ["- [ ] ", "- [x] ", "- [X] ", "- ", "* ", "+ ", "> "]
            for prefix in emptyPrefixes {
                if line == prefix {
                    let clearRange = NSRange(location: lineRange.location, length: (line as NSString).length)
                    replaceRange(textView, range: clearRange, with: "", cursorAt: lineRange.location)
                    return false
                }
            }

            // Empty numbered list "1. " etc.
            if line.range(of: #"^\d+\. $"#, options: .regularExpression) != nil {
                let clearRange = NSRange(location: lineRange.location, length: (line as NSString).length)
                replaceRange(textView, range: clearRange, with: "", cursorAt: lineRange.location)
                return false
            }

            // === Continue list/quote ===

            let cursorAtLineStart = range.location == lineRange.location

            if line.hasPrefix("- [ ] ") || line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") {
                // Cursor at line start: plain newline (no list marker on new line)
                if cursorAtLineStart { return true }
                insertAtCursor(textView, "\n- [ ] ")
                return false
            }

            if line.hasPrefix("- ") {
                // Cursor at line start: plain newline (no list marker on new line)
                if cursorAtLineStart { return true }
                insertAtCursor(textView, "\n- ")
                return false
            }

            if line.hasPrefix("* ") {
                // Cursor at line start: plain newline (no list marker on new line)
                if cursorAtLineStart { return true }
                insertAtCursor(textView, "\n* ")
                return false
            }

            if line.hasPrefix("+ ") {
                // Cursor at line start: plain newline (no list marker on new line)
                if cursorAtLineStart { return true }
                insertAtCursor(textView, "\n+ ")
                return false
            }

            // Numbered list: extract number using regex capture group
            if let regex = try? NSRegularExpression(pattern: #"^(\d+)\. "#),
               let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)),
               match.numberOfRanges > 1 {
                let numRange = match.range(at: 1)
                let numPart = (line as NSString).substring(with: numRange)
                if let num = Int(numPart) {
                    if cursorAtLineStart {
                        // Check whether this is the first line of the ordered list block
                        let isFirstListLine: Bool = {
                            guard lineRange.location > 0 else { return true }
                            let prevRange = nsText.lineRange(for: NSRange(location: lineRange.location - 1, length: 0))
                            let prevLine = nsText.substring(with: prevRange)
                            let orderedPattern = try? NSRegularExpression(pattern: #"^\d+\. "#)
                            return orderedPattern?.firstMatch(
                                in: prevLine,
                                range: NSRange(location: 0, length: (prevLine as NSString).length)
                            ) == nil
                        }()

                        if isFirstListLine {
                            // First line: plain newline before the list block
                            return true
                        } else {
                            // Non-first line: insert blank line to split the list into two;
                            // renumberLists will reset the second list's numbering from 1.
                            replaceRange(textView, range: NSRange(location: lineRange.location, length: 0),
                                         with: "\n", cursorAt: lineRange.location)
                            renumberLists(textView)
                            parent.text = textView.text
                            applyHighlighting(textView)
                            return false
                        }
                    }
                    insertAtCursor(textView, "\n\(num + 1). ")
                    return false
                }
            }

            if line.hasPrefix("> ") {
                insertAtCursor(textView, "\n> ")
                return false
            }

            // ── Table handling ──────────────────────────────────────────────────
            if line.contains("|") {
                // Use actual line text length so EOF lines (without trailing '\n') are handled correctly.
                let lineContentEnd = lineRange.location + (line as NSString).length
                let cursorAtLineStart = range.location == lineRange.location
                let cursorAtLineEnd   = range.location == lineContentEnd

                let isSepRow = isTableSeparatorLine(line)
                let colCount = max(1, tableColumnCount(line))

                // ── Separator row ───────────────────────────────────────────
                if isSepRow {
                    if cursorAtLineStart {
                        // Shift separator (and everything below) down: plain newline
                        return true
                    } else {
                        // Any non-start position on a separator row → insert empty data row after it
                        let cells  = Array(repeating: "  ", count: colCount).joined(separator: " | ")
                        let newRow = "| " + cells + " |"
                        // Move cursor to line end first so we insert after the whole line
                        textView.selectedRange = NSRange(location: lineRange.location + (line as NSString).length, length: 0)
                        insertAtCursor(textView, "\n" + newRow)
                        let cursorPos      = textView.selectedRange.location
                        let firstCellStart = cursorPos - (newRow as NSString).length + 2
                        if firstCellStart >= 0 {
                            textView.selectedRange = NSRange(location: firstCellStart, length: 0)
                        }
                        return false
                    }
                }

                // ── Non-separator table row (header or data) ────────────────

                // Detect header row: the line above is not a table row
                let isHeaderRow: Bool = {
                    if lineRange.location == 0 { return true }
                    let prevRange = nsText.lineRange(for: NSRange(location: lineRange.location - 1, length: 0))
                    let prevLine  = nsText.substring(with: prevRange).trimmingCharacters(in: .newlines)
                    return !prevLine.contains("|")
                }()

                // Detect empty data row (all cells blank) — always exits table regardless of cursor
                let isEmptyDataRow: Bool = {
                    if isHeaderRow { return false }
                    var t = line.trimmingCharacters(in: .whitespaces)
                    if t.hasPrefix("|") { t = String(t.dropFirst()) }
                    if t.hasSuffix("|") { t = String(t.dropLast()) }
                    return t.components(separatedBy: "|").allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
                }()

                if isEmptyDataRow {
                    // Empty data row + Enter → delete row and exit table
                    replaceRange(textView, range: NSRange(location: lineRange.location, length: lineRange.length),
                                 with: "", cursorAt: lineRange.location)
                    insertAtCursor(textView, "\n")
                    return false
                }

                if isHeaderRow {
                    if cursorAtLineStart {
                        // Shift entire table down: plain newline before header
                        return true
                    } else {
                        // Any non-start position on a header row → insert separator + first data row
                        let dashCells    = Array(repeating: " --- ", count: colCount).joined(separator: "|")
                        let separatorRow = "|" + dashCells + "|"
                        let emptyCells   = Array(repeating: "  ", count: colCount).joined(separator: " | ")
                        let dataRow      = "| " + emptyCells + " |"
                        // Move cursor to line end first so we insert after the whole header line
                        textView.selectedRange = NSRange(location: lineRange.location + (line as NSString).length, length: 0)
                        insertAtCursor(textView, "\n" + separatorRow + "\n" + dataRow)
                        let cursorPos      = textView.selectedRange.location
                        let firstCellStart = cursorPos - (dataRow as NSString).length + 2
                        if firstCellStart >= 0 {
                            textView.selectedRange = NSRange(location: firstCellStart, length: 0)
                        }
                        return false
                    }
                }

                // ── Regular data row ────────────────────────────────────────
                if cursorAtLineStart {
                    // Insert a new empty row BEFORE the current row; current row shifts down
                    let cells  = Array(repeating: "  ", count: colCount).joined(separator: " | ")
                    let newRow = "| " + cells + " |"
                    // Insert "newRow\n" at the very start of this line
                    replaceRange(textView, range: NSRange(location: lineRange.location, length: 0),
                                 with: newRow + "\n", cursorAt: lineRange.location + 2)
                    return false
                } else {
                    // Cursor anywhere on the row (middle or end) → append new empty row after this row.
                    // Moving the cursor to line end first ensures the insert position is always after
                    // the current row, regardless of where within the cell the cursor was.
                    let cells  = Array(repeating: "  ", count: colCount).joined(separator: " | ")
                    let newRow = "| " + cells + " |"
                    textView.selectedRange = NSRange(location: lineRange.location + (line as NSString).length, length: 0)
                    insertAtCursor(textView, "\n" + newRow)
                    let cursorPos      = textView.selectedRange.location
                    let firstCellStart = cursorPos - (newRow as NSString).length + 2
                    if firstCellStart >= 0 {
                        textView.selectedRange = NSRange(location: firstCellStart, length: 0)
                    }
                    return false
                }
            }

            // Headings: do NOT continue
            // Default text: normal Enter behavior
            return true
        }

        // MARK: - Smart Backspace

        private func handleBackspace(_ textView: UITextView, at range: NSRange) -> Bool {
            let nsText = textView.text as NSString
            let lineRange = nsText.lineRange(for: range)
            let lineStart = lineRange.location
            // Cursor position is at range.location + range.length (end of deletion range)
            // For backspace, range.length is 1, so cursor is at range.location + 1
            let cursorInLine = range.location + range.length - lineStart
            let line = nsText.substring(with: lineRange).replacingOccurrences(of: "\n", with: "")

            // Ordered prefixes: check longest match first
            // Smart backspace only triggers when cursor is EXACTLY after the prefix (no content after it)
            let prefixes = [
                "###### ", "##### ", "#### ", "### ", "## ", "# ",
                "- [x] ", "- [X] ", "- [ ] ",
                "- ", "* ", "+ ", "> "
            ]

            for prefix in prefixes {
                if line.hasPrefix(prefix) && cursorInLine == prefix.count {
                    let pfxRange = NSRange(location: lineStart, length: prefix.count)
                    replaceRange(textView, range: pfxRange, with: "", cursorAt: lineStart)
                    return false
                }
            }

            // Numbered list
            if let match = line.range(of: #"^\d+\. "#, options: .regularExpression) {
                let prefixLen = line.distance(from: line.startIndex, to: match.upperBound)
                if cursorInLine == prefixLen {
                    let pfxRange = NSRange(location: lineStart, length: prefixLen)
                    replaceRange(textView, range: pfxRange, with: "", cursorAt: lineStart)
                    return false
                }
            }

            // Table rows: smart delete
            if line.contains("|") {
                let isHeaderRow: Bool = {
                    if lineRange.location == 0 { return true }
                    let prevRange = nsText.lineRange(for: NSRange(location: lineRange.location - 1, length: 0))
                    let prevLine = nsText.substring(with: prevRange).trimmingCharacters(in: .newlines)
                    return !prevLine.contains("|")
                }()

                let isEmptyDataRow: Bool = {
                    if isHeaderRow { return false }
                    var t = line.trimmingCharacters(in: .whitespaces)
                    if t.hasPrefix("|") { t = String(t.dropFirst()) }
                    if t.hasSuffix("|") { t = String(t.dropLast()) }
                    return t.components(separatedBy: "|").allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
                }()

                // Delete empty data row when cursor is at first cell start (cursorInLine == 2, after "| ")
                // or when cursor is at line end for any non-header row
                let atFirstCell = isEmptyDataRow && cursorInLine == 2
                let atLineEnd = !isHeaderRow && cursorInLine == (line as NSString).length

                if atFirstCell || atLineEnd {
                    // Delete the line itself (location..location+length covers content + trailing \n).
                    // Cursor lands at lineRange.location, which after deletion is the start of the
                    // following content — visually staying at the deleted row's original position.
                    let deleteRange = NSRange(location: lineRange.location, length: lineRange.length)
                    let cursorAfter = lineRange.location
                    replaceRange(textView, range: deleteRange, with: "", cursorAt: cursorAfter)
                    return false
                }
            }

            return true
        }

        // MARK: - Text Mutation Helpers

        private func insertAtCursor(_ textView: UITextView, _ text: String) {
            isHighlighting = true
            textView.insertText(text)
            parent.text = textView.text
            isHighlighting = false
            applyHighlighting(textView)
            scrollToCursor(textView)
        }

        private func replaceRange(_ textView: UITextView, range: NSRange, with replacement: String, cursorAt: Int? = nil) {
            guard let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
                  let end = textView.position(from: textView.beginningOfDocument, offset: range.location + range.length),
                  let textRange = textView.textRange(from: start, to: end) else { return }
            isHighlighting = true
            textView.replace(textRange, withText: replacement)
            
            // Set cursor position if specified
            if let cursorPos = cursorAt {
                let maxPos = (textView.text as NSString).length
                textView.selectedRange = NSRange(location: min(cursorPos, maxPos), length: 0)
            }
            
            parent.text = textView.text
            isHighlighting = false
            applyHighlighting(textView)
            
            // Scroll to make cursor visible
            scrollToCursor(textView)
        }
        
        /// Scroll to ensure cursor is visible (not hidden by toolbar)
        private func scrollToCursor(_ textView: UITextView) {
            guard let selectedRange = textView.selectedTextRange else { return }
            let caretRect = textView.caretRect(for: selectedRange.start)
            // Add extra padding below caret for toolbar
            var visibleRect = caretRect
            visibleRect.size.height += 60
            textView.scrollRectToVisible(visibleRect, animated: false)
        }

        // MARK: - Numbered List Renumbering

        /// Renumber all consecutive numbered list items to be sequential (1, 2, 3...)
        private func renumberLists(_ textView: UITextView) {
            let nsText = textView.text as NSString
            guard nsText.length > 0 else { return }

            let savedCursor = textView.selectedRange
            var newText = ""
            var lineStart = 0
            var currentListNum = 0
            var cursorOffset = 0  // Track how cursor position changes due to renumbering

            let numPattern = try! NSRegularExpression(pattern: #"^(\d+)\. "#)

            while lineStart < nsText.length {
                let lineRange = nsText.lineRange(for: NSRange(location: lineStart, length: 0))
                let line = nsText.substring(with: lineRange)
                let lineNS = line as NSString

                if let match = numPattern.firstMatch(in: line, range: NSRange(location: 0, length: lineNS.length)),
                   match.numberOfRanges > 1 {
                    // This is a numbered list item
                    currentListNum += 1
                    let numRange = match.range(at: 1)
                    let oldNum = lineNS.substring(with: numRange)
                    let newNum = "\(currentListNum)"

                    // Replace the number
                    let updatedLine = lineNS.replacingCharacters(in: numRange, with: newNum)
                    newText += updatedLine

                    // Adjust cursor if it's after this change
                    let changeInLength = newNum.count - oldNum.count
                    if savedCursor.location > lineRange.location + numRange.location {
                        cursorOffset += changeInLength
                    }
                } else {
                    // Not a numbered list item - reset counter
                    currentListNum = 0
                    newText += line
                }

                lineStart = NSMaxRange(lineRange)
            }

            // Only update if changed
            if newText != textView.text {
                isHighlighting = true

                // Use replace to preserve undo stack
                let fullLen = (textView.text as NSString).length
                if let start = textView.position(from: textView.beginningOfDocument, offset: 0),
                   let end = textView.position(from: textView.beginningOfDocument, offset: fullLen),
                   let range = textView.textRange(from: start, to: end) {
                    textView.replace(range, withText: newText)
                }

                // Restore cursor with offset adjustment
                let newCursorLoc = max(0, min(savedCursor.location + cursorOffset, (newText as NSString).length))
                textView.selectedRange = NSRange(location: newCursorLoc, length: 0)

                parent.text = textView.text
                isHighlighting = false
            }
        }

        // MARK: - Public API

        /// Focus the text view
        func focus() { textView?.becomeFirstResponder() }

        /// Dismiss keyboard
        func blur() { textView?.resignFirstResponder() }

        /// Move the cursor to the given character offset
        func setCursorPosition(_ position: Int) {
            guard let tv = textView else { return }
            let maxPos = (tv.text as NSString).length
            tv.selectedRange = NSRange(location: min(position, maxPos), length: 0)
            scrollToCursor(tv)
        }

        /// Select all text
        func selectAll() {
            textView?.selectAll(nil)
        }

        /// Get the text of the line at the current cursor position
        func getCurrentLineText() -> String {
            guard let tv = textView else { return "" }
            let nsText = tv.text as NSString
            guard nsText.length > 0 else { return "" }
            let cursor = min(tv.selectedRange.location, nsText.length)
            let lineRange = nsText.lineRange(for: NSRange(location: cursor, length: 0))
            return nsText.substring(with: lineRange).trimmingCharacters(in: .newlines)
        }

        /// Toggle todo checkbox on the current line: - [ ] ↔ - [x]
        /// Cursor position is preserved after the toggle.
        func toggleTodoOnCurrentLine() {
            guard let tv = textView else { return }
            let nsText = tv.text as NSString
            guard nsText.length > 0 else { return }
            let cursor = min(tv.selectedRange.location, nsText.length)
            let lineRange = nsText.lineRange(for: NSRange(location: cursor, length: 0))
            let line = nsText.substring(with: lineRange)

            if line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") {
                let prefixRange = NSRange(location: lineRange.location, length: 6)
                replaceRange(tv, range: prefixRange, with: "- [ ] ", cursorAt: cursor)
            } else if line.hasPrefix("- [ ] ") {
                let prefixRange = NSRange(location: lineRange.location, length: 6)
                replaceRange(tv, range: prefixRange, with: "- [x] ", cursorAt: cursor)
            }
        }

        /// Insert text at the current cursor position
        func insertTextAtCursor(_ text: String) {
            guard let tv = textView else { return }
            insertAtCursor(tv, text)
        }

        /// Insert a block-level format (ensures newline before if cursor is not at line start)
        func insertBlockAtCursor(_ text: String) {
            guard let tv = textView else { return }
            let nsText = tv.text as NSString
            let cursor = tv.selectedRange.location
            let atLineStart = cursor == 0 ||
                nsText.substring(with: NSRange(location: cursor - 1, length: 1)) == "\n"
            if !atLineStart {
                insertAtCursor(tv, "\n" + text)
            } else {
                insertAtCursor(tv, text)
            }
        }

        /// Undo
        func undo() {
            guard let tv = textView, tv.undoManager?.canUndo == true else { return }
            tv.undoManager?.undo()
            parent.text = tv.text
            applyHighlighting(tv)
        }

        /// Redo
        func redo() {
            guard let tv = textView, tv.undoManager?.canRedo == true else { return }
            tv.undoManager?.redo()
            parent.text = tv.text
            applyHighlighting(tv)
        }

        /// Clear the undo stack
        func clearUndoStack() {
            textView?.undoManager?.removeAllActions()
        }

        var canUndo: Bool { textView?.undoManager?.canUndo ?? false }
        var canRedo: Bool { textView?.undoManager?.canRedo ?? false }

        // MARK: - Selection Handling

        /// Get the currently selected text (nil if no selection)
        var selectedText: String? {
            guard let tv = textView else { return nil }
            let range = tv.selectedRange
            guard range.length > 0 else { return nil }
            return (tv.text as NSString).substring(with: range)
        }

        /// Get the current selection range
        var selectedRange: NSRange? {
            guard let tv = textView else { return nil }
            let range = tv.selectedRange
            return range.length > 0 ? range : nil
        }

        /// Get the current cursor offset (always valid, even with no selection)
        var cursorOffset: Int {
            guard let tv = textView else { return 0 }
            return tv.selectedRange.location
        }

        /// Wrap the current selection with prefix and suffix (e.g., make bold: **selection**)
        /// If no selection, inserts prefix + placeholder + suffix at cursor
        func applyInlineFormat(prefix: String, suffix: String, placeholder: String) {
            guard let tv = textView else { return }
            let range = tv.selectedRange

            if range.length > 0 {
                // Has selection: wrap it
                let selectedText = (tv.text as NSString).substring(with: range)
                let replacement = prefix + selectedText + suffix
                replaceRange(tv, range: range, with: replacement)
                // Position cursor after the wrapped text
                let newCursor = range.location + replacement.count
                tv.selectedRange = NSRange(location: newCursor, length: 0)
            } else {
                // No selection: insert with placeholder
                let insertion = prefix + placeholder + suffix
                insertAtCursor(tv, insertion)
                // Select the placeholder so user can type over it
                let placeholderStart = range.location + prefix.count
                tv.selectedRange = NSRange(location: placeholderStart, length: placeholder.count)
            }
        }

        /// Apply block-level format to current line or wrap selection
        /// For blocks like headers, quotes - replaces line prefix or wraps selection
        func applyBlockFormat(prefix: String) {
            guard let tv = textView else { return }
            let nsText = tv.text as NSString
            let range = tv.selectedRange

            if range.length > 0 {
                // Has selection: add prefix to each line of selection
                let selectedText = nsText.substring(with: range)
                let lines = selectedText.components(separatedBy: "\n")
                let prefixedLines = lines.map { prefix + $0 }
                let replacement = prefixedLines.joined(separator: "\n")
                replaceRange(tv, range: range, with: replacement)
            } else {
                // No selection: ensure at line start, then insert prefix
                let cursor = range.location
                let lineRange = nsText.lineRange(for: NSRange(location: cursor, length: 0))
                let lineStart = lineRange.location

                // Check if line already has this prefix
                let line = nsText.substring(with: lineRange).trimmingCharacters(in: .newlines)
                if line.hasPrefix(prefix) {
                    // Already has prefix, remove it (toggle off)
                    let prefixRange = NSRange(location: lineStart, length: prefix.count)
                    replaceRange(tv, range: prefixRange, with: "")
                } else {
                    // Add prefix at line start
                    let insertRange = NSRange(location: lineStart, length: 0)
                    replaceRange(tv, range: insertRange, with: prefix)
                }
            }
        }

        // MARK: - Syntax Highlighting

        func applyHighlighting(_ textView: UITextView) {
            guard !isHighlighting else { return }
            isHighlighting = true
            defer { isHighlighting = false }

            let nsText = textView.text as NSString
            guard nsText.length > 0 else { return }

            let savedRange = textView.selectedRange
            let cursorLoc = savedRange.location
            let fullRange = NSRange(location: 0, length: nsText.length)
            let storage = textView.textStorage

            storage.beginEditing()

            // 1. Reset everything to body style
            storage.setAttributes([
                .font: bodyFont,
                .foregroundColor: primaryUIColor
            ], range: fullRange)

            // 2. Walk lines
            var lineStart = 0
            var inCodeBlock = false

            while lineStart < nsText.length {
                let lineRange = nsText.lineRange(for: NSRange(location: lineStart, length: 0))
                let line = nsText.substring(with: lineRange)
                let trimmed = line.trimmingCharacters(in: .newlines)
                let trimmedLen = (trimmed as NSString).length

                // Content range (excluding trailing newline)
                let contentRange = NSRange(location: lineRange.location, length: min(trimmedLen, lineRange.length))

                let isCursorLine: Bool = {
                    if cursorLoc >= lineRange.location && cursorLoc < NSMaxRange(lineRange) {
                        return true
                    }
                    // Cursor at very end of text, on the last line
                    if cursorLoc == nsText.length && NSMaxRange(lineRange) == nsText.length {
                        return true
                    }
                    return false
                }()

                // Code block fences - check trimmed line (allow leading whitespace)
                // Supports both ``` and ~~~ fences
                let trimmedForFence = trimmed.trimmingCharacters(in: .whitespaces)
                if trimmedForFence.hasPrefix("```") || trimmedForFence.hasPrefix("~~~") {
                    inCodeBlock.toggle()
                    storage.addAttributes([
                        .font: codeFont,
                        .foregroundColor: syntaxUIColor
                    ], range: contentRange)
                    lineStart = NSMaxRange(lineRange)
                    continue
                }

                // Inside code block
                if inCodeBlock {
                    storage.addAttributes([
                        .font: codeFont,
                        .backgroundColor: UIColor.tertiarySystemFill
                    ], range: contentRange)
                    lineStart = NSMaxRange(lineRange)
                    continue
                }

                // Style the line
                if isCursorLine {
                    styleCursorLine(storage, trimmed: trimmed, range: contentRange)
                } else {
                    styleRenderedLine(storage, trimmed: trimmed, range: contentRange)
                }

                // Inline styles (bold, italic, strikethrough, code)
                if trimmedLen > 0 {
                    applyInlineStyles(storage, range: contentRange, isCursorLine: isCursorLine)
                }

                lineStart = NSMaxRange(lineRange)
            }

            storage.endEditing()

            // Restore cursor
            if textView.selectedRange != savedRange {
                textView.selectedRange = savedRange
            }
        }

        // MARK: - Cursor Line: syntax-aware coloring

        private func styleCursorLine(_ storage: NSTextStorage, trimmed: String, range: NSRange) {
            let syntaxColor = syntaxUIColor

            // Headings (check longest first)
            if trimmed.hasPrefix("###### ") {
                colorPrefix(storage, at: range.location, length: 7, color: syntaxColor)
                storage.addAttribute(.font, value: h6Font, range: range)
            } else if trimmed.hasPrefix("##### ") {
                colorPrefix(storage, at: range.location, length: 6, color: syntaxColor)
                storage.addAttribute(.font, value: h5Font, range: range)
            } else if trimmed.hasPrefix("#### ") {
                colorPrefix(storage, at: range.location, length: 5, color: syntaxColor)
                storage.addAttribute(.font, value: h4Font, range: range)
            } else if trimmed.hasPrefix("### ") {
                colorPrefix(storage, at: range.location, length: 4, color: syntaxColor)
                storage.addAttribute(.font, value: h3Font, range: range)
            } else if trimmed.hasPrefix("## ") {
                colorPrefix(storage, at: range.location, length: 3, color: syntaxColor)
                storage.addAttribute(.font, value: h2Font, range: range)
            } else if trimmed.hasPrefix("# ") {
                colorPrefix(storage, at: range.location, length: 2, color: syntaxColor)
                storage.addAttribute(.font, value: h1Font, range: range)
            } else if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
                colorPrefix(storage, at: range.location, length: 6, color: syntaxColor)
            } else if trimmed.hasPrefix("- [ ] ") {
                colorPrefix(storage, at: range.location, length: 6, color: syntaxColor)
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                colorPrefix(storage, at: range.location, length: 2, color: syntaxColor)
            } else if let match = trimmed.range(of: #"^\d+\. "#, options: .regularExpression) {
                let len = trimmed.distance(from: trimmed.startIndex, to: match.upperBound)
                colorPrefix(storage, at: range.location, length: len, color: syntaxColor)
            } else if trimmed.hasPrefix("> ") {
                colorPrefix(storage, at: range.location, length: 2, color: .systemTeal)
                let afterPrefix = NSRange(location: range.location + 2, length: max(0, range.length - 2))
                if afterPrefix.length > 0 {
                    storage.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: afterPrefix)
                }
            } else if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                storage.addAttribute(.foregroundColor, value: UIColor.systemGray2, range: range)
            } else if trimmed.contains("|") {
                // Table row: color each | with syntaxColor
                let isSep = isTableSeparatorLine(trimmed)
                if isSep {
                    storage.addAttribute(.foregroundColor, value: UIColor.systemGray2, range: range)
                } else {
                    colorTablePipes(storage, line: trimmed, lineStart: range.location, color: syntaxColor)
                }
            }
        }

        // MARK: - Rendered Line: rich-text styling

        private func styleRenderedLine(_ storage: NSTextStorage, trimmed: String, range: NSRange) {
            let subtle = UIColor.tertiaryLabel

            // Headings (check longest first)
            if trimmed.hasPrefix("###### ") {
                let pl = 7
                subtlePrefix(storage, at: range.location, length: pl, color: subtle)
                let cr = NSRange(location: range.location + pl, length: max(0, range.length - pl))
                if cr.length > 0 { storage.addAttribute(.font, value: h6Font, range: cr) }
            } else if trimmed.hasPrefix("##### ") {
                let pl = 6
                subtlePrefix(storage, at: range.location, length: pl, color: subtle)
                let cr = NSRange(location: range.location + pl, length: max(0, range.length - pl))
                if cr.length > 0 { storage.addAttribute(.font, value: h5Font, range: cr) }
            } else if trimmed.hasPrefix("#### ") {
                let pl = 5
                subtlePrefix(storage, at: range.location, length: pl, color: subtle)
                let cr = NSRange(location: range.location + pl, length: max(0, range.length - pl))
                if cr.length > 0 { storage.addAttribute(.font, value: h4Font, range: cr) }
            } else if trimmed.hasPrefix("### ") {
                let pl = 4
                subtlePrefix(storage, at: range.location, length: pl, color: subtle)
                let cr = NSRange(location: range.location + pl, length: max(0, range.length - pl))
                if cr.length > 0 { storage.addAttribute(.font, value: h3Font, range: cr) }
            } else if trimmed.hasPrefix("## ") {
                let pl = 3
                subtlePrefix(storage, at: range.location, length: pl, color: subtle)
                let cr = NSRange(location: range.location + pl, length: max(0, range.length - pl))
                if cr.length > 0 { storage.addAttribute(.font, value: h2Font, range: cr) }
            } else if trimmed.hasPrefix("# ") {
                let pl = 2
                subtlePrefix(storage, at: range.location, length: pl, color: subtle)
                let cr = NSRange(location: range.location + pl, length: max(0, range.length - pl))
                if cr.length > 0 { storage.addAttribute(.font, value: h1Font, range: cr) }
            } else if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
                subtlePrefix(storage, at: range.location, length: 6, color: subtle)
                let cr = NSRange(location: range.location + 6, length: max(0, range.length - 6))
                if cr.length > 0 {
                    storage.addAttributes([
                        .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                        .foregroundColor: UIColor.secondaryLabel
                    ], range: cr)
                }
            } else if trimmed.hasPrefix("- [ ] ") {
                subtlePrefix(storage, at: range.location, length: 6, color: subtle)
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                colorPrefix(storage, at: range.location, length: 2, color: .secondaryLabel)
            } else if let match = trimmed.range(of: #"^\d+\. "#, options: .regularExpression) {
                let len = trimmed.distance(from: trimmed.startIndex, to: match.upperBound)
                colorPrefix(storage, at: range.location, length: len, color: .secondaryLabel)
            } else if trimmed.hasPrefix("> ") {
                colorPrefix(storage, at: range.location, length: 2, color: .systemTeal)
                let cr = NSRange(location: range.location + 2, length: max(0, range.length - 2))
                if cr.length > 0 {
                    storage.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: cr)
                }
            } else if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                storage.addAttribute(.foregroundColor, value: UIColor.systemGray3, range: range)
            } else if trimmed.contains("|") {
                // Table separator row: muted + small font
                if isTableSeparatorLine(trimmed) {
                    storage.addAttributes([
                        .foregroundColor: UIColor.systemGray3,
                        .font: smallPrefixFont
                    ], range: range)
                } else {
                    // Normal table row: color pipes subtle
                    colorTablePipes(storage, line: trimmed, lineStart: range.location, color: UIColor.tertiaryLabel)
                }
            }
        }

        // MARK: - Inline Styles (bold, italic, strikethrough, code)

        private func applyInlineStyles(_ storage: NSTextStorage, range: NSRange, isCursorLine: Bool) {
            let text = (storage.string as NSString).substring(with: range)
            let markerColor = isCursorLine ? syntaxUIColor.withAlphaComponent(0.7) : UIColor.tertiaryLabel

            // Bold+Italic: ***text*** (must check before bold/italic)
            applyPattern(storage, text: text, lineStart: range.location,
                         pattern: #"\*\*\*(.+?)\*\*\*"#, markerLen: 3,
                         attrs: [.font: mdBoldItalicFont], markerColor: markerColor)

            // Bold+Italic alternative: ___text___
            applyPattern(storage, text: text, lineStart: range.location,
                         pattern: #"___(.+?)___"#, markerLen: 3,
                         attrs: [.font: mdBoldItalicFont], markerColor: markerColor)

            // Bold: **text**
            applyPattern(storage, text: text, lineStart: range.location,
                         pattern: #"(?<!\*)\*\*(?!\*)(.+?)(?<!\*)\*\*(?!\*)"#, markerLen: 2,
                         attrs: [.font: mdBoldFont], markerColor: markerColor)

            // Bold alternative: __text__
            applyPattern(storage, text: text, lineStart: range.location,
                         pattern: #"(?<!_)__(?!_)(.+?)(?<!_)__(?!_)"#, markerLen: 2,
                         attrs: [.font: mdBoldFont], markerColor: markerColor)

            // Italic: *text* (not preceded/followed by *)
            applyPattern(storage, text: text, lineStart: range.location,
                         pattern: #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#, markerLen: 1,
                         attrs: [.font: mdItalicFont], markerColor: markerColor)

            // Italic alternative: _text_ (not preceded/followed by _)
            applyPattern(storage, text: text, lineStart: range.location,
                         pattern: #"(?<!_)_(?!_)(.+?)(?<!_)_(?!_)"#, markerLen: 1,
                         attrs: [.font: mdItalicFont], markerColor: markerColor)

            // Strikethrough: ~~text~~
            applyPattern(storage, text: text, lineStart: range.location,
                         pattern: #"~~(.+?)~~"#, markerLen: 2,
                         attrs: [.strikethroughStyle: NSUnderlineStyle.single.rawValue], markerColor: markerColor)

            // Inline code: `text`
            applyPattern(storage, text: text, lineStart: range.location,
                         pattern: #"`([^`]+)`"#, markerLen: 1,
                         attrs: [.font: codeFont, .backgroundColor: UIColor.tertiarySystemFill],
                         markerColor: markerColor)

            // Links: [text](url) and Images: ![alt](url)
            applyLinkPattern(storage, text: text, lineStart: range.location, isCursorLine: isCursorLine)
        }

        /// Apply link/image patterns with special handling: text styled, brackets/url subdued
        private func applyLinkPattern(_ storage: NSTextStorage, text: String, lineStart: Int, isCursorLine: Bool) {
            let markerColor = isCursorLine ? syntaxUIColor.withAlphaComponent(0.6) : UIColor.tertiaryLabel
            let linkColor = UIColor.systemBlue

            // Image: ![alt](url)
            if let regex = try? NSRegularExpression(pattern: #"!\[([^\]]*)\]\(([^)]+)\)"#) {
                let nsText = text as NSString
                let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
                for match in matches where match.numberOfRanges >= 3 {
                    let fullRange = NSRange(location: lineStart + match.range.location, length: match.range.length)
                    let altRange = NSRange(location: lineStart + match.range(at: 1).location, length: match.range(at: 1).length)
                    // Color entire match as subtle
                    storage.addAttribute(.foregroundColor, value: markerColor, range: fullRange)
                    // Alt text in purple (image indicator)
                    if altRange.length > 0 {
                        storage.addAttribute(.foregroundColor, value: UIColor.systemPurple, range: altRange)
                    }
                }
            }

            // Link: [text](url) - but not ![
            if let regex = try? NSRegularExpression(pattern: #"(?<!!)\[([^\]]+)\]\(([^)]+)\)"#) {
                let nsText = text as NSString
                let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
                for match in matches where match.numberOfRanges >= 3 {
                    let fullRange = NSRange(location: lineStart + match.range.location, length: match.range.length)
                    let textRange = NSRange(location: lineStart + match.range(at: 1).location, length: match.range(at: 1).length)
                    // Color entire match as subtle
                    storage.addAttribute(.foregroundColor, value: markerColor, range: fullRange)
                    // Link text in blue + underline
                    if textRange.length > 0 {
                        storage.addAttributes([
                            .foregroundColor: linkColor,
                            .underlineStyle: NSUnderlineStyle.single.rawValue
                        ], range: textRange)
                    }
                }
            }
        }

        private func applyPattern(_ storage: NSTextStorage, text: String, lineStart: Int,
                                   pattern: String, markerLen: Int,
                                   attrs: [NSAttributedString.Key: Any], markerColor: UIColor) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            let nsText = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

            for match in matches {
                let full = match.range
                guard full.length > markerLen * 2 else { continue }

                let openRange = NSRange(location: lineStart + full.location, length: markerLen)
                let closeRange = NSRange(location: lineStart + full.location + full.length - markerLen, length: markerLen)
                let contentRange = NSRange(location: lineStart + full.location + markerLen,
                                            length: full.length - markerLen * 2)

                // Color markers
                storage.addAttribute(.foregroundColor, value: markerColor, range: openRange)
                storage.addAttribute(.foregroundColor, value: markerColor, range: closeRange)

                // Style content
                if contentRange.length > 0 {
                    storage.addAttributes(attrs, range: contentRange)
                }
            }
        }

        // MARK: - Attribute Helpers

        private func colorPrefix(_ storage: NSTextStorage, at location: Int, length: Int, color: UIColor) {
            guard length > 0 else { return }
            let range = NSRange(location: location, length: length)
            storage.addAttribute(.foregroundColor, value: color, range: range)
        }

        /// Make prefix small and subtle (for rendered headings / checkboxes)
        private func subtlePrefix(_ storage: NSTextStorage, at location: Int, length: Int, color: UIColor) {
            guard length > 0 else { return }
            let range = NSRange(location: location, length: length)
            storage.addAttributes([
                .foregroundColor: color,
                .font: smallPrefixFont
            ], range: range)
        }

        // MARK: - Line Utilities

        private func isTableSeparatorLine(_ line: String) -> Bool {
            var t = line.trimmingCharacters(in: .whitespaces)
            guard t.contains("|") else { return false }
            if t.hasPrefix("|") { t = String(t.dropFirst()) }
            if t.hasSuffix("|") { t = String(t.dropLast()) }
            let cells = t.components(separatedBy: "|")
            guard !cells.isEmpty else { return false }
            return cells.allSatisfy { cell in
                let c = cell.trimmingCharacters(in: .whitespaces)
                guard !c.isEmpty else { return false }
                let stripped = c.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
                return stripped.allSatisfy { $0 == "-" } && !stripped.isEmpty
            }
        }

        private func colorTablePipes(_ storage: NSTextStorage, line: String, lineStart: Int, color: UIColor) {
            let nsLine = line as NSString
            var pos = 0
            while pos < nsLine.length {
                if nsLine.character(at: pos) == ("|" as NSString).character(at: 0) {
                    let absRange = NSRange(location: lineStart + pos, length: 1)
                    storage.addAttribute(.foregroundColor, value: color, range: absRange)
                }
                pos += 1
            }
        }

        private func tableColumnCount(_ line: String) -> Int {
            var t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("|") { t = String(t.dropFirst()) }
            if t.hasSuffix("|") { t = String(t.dropLast()) }
            let cells = t.components(separatedBy: "|")
            return cells.count
        }

        private func lineIndex(at location: Int, in text: NSString) -> Int {
            var idx = 0
            var pos = 0
            while pos < text.length && pos < location {
                let lr = text.lineRange(for: NSRange(location: pos, length: 0))
                pos = NSMaxRange(lr)
                if pos <= location { idx += 1 }
            }
            return idx
        }
    }
}

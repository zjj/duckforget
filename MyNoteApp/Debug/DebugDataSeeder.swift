#if DEBUG
import Foundation
import SwiftData

/// Seeds the SwiftData store with randomly generated markdown notes for debugging.
/// All methods are no-ops in Release builds — this entire file is excluded by the compiler.
@MainActor
final class DebugDataSeeder {

    // MARK: - Markdown content pools

    private static let titles = [
        "Today's thoughts", "Meeting notes", "Book review", "Project ideas",
        "Travel plan", "Recipe experiment", "Reading list", "Weekly goals",
        "Coding snippet", "Random observation", "Dream journal", "Budget plan",
        "Workout log", "Learning notes", "Quote collection", "App idea",
        "Debug session", "Architecture thoughts", "UI feedback", "Interview prep"
    ]

    private static let tags = [
        "ideas", "work", "personal", "health", "finance",
        "coding", "reading", "travel", "food", "learning"
    ]

    private static let paragraphs = [
        "This is a **bold** statement about something important.",
        "Here is some `inline code` for reference.",
        "> A great quote worth remembering.",
        "- Item one\n- Item two\n- Item three",
        "1. First step\n2. Second step\n3. Third step",
        "## Section Header\n\nSome notes under this section.",
        "~~Strikethrough~~ and _italic_ text example.",
        "```swift\nlet x = 42\nprint(x)\n```",
        "A plain paragraph with no formatting, just some text to fill lines.",
        "**Important:** Remember to follow up on this tomorrow.",
        "| Column A | Column B |\n|---|---|\n| Value 1 | Value 2 |",
        "---\n\nHorizontal rule above.",
        "- [x] Done task\n- [ ] Pending task",
        "Check out [this link](https://example.com) for more details.",
        "![image alt](https://example.com/image.png)"
    ]

    // MARK: - Public API

    /// Inserts `count` randomly generated `NoteItem` objects into `modelContext`.
    /// Work is batched so the main thread stays responsive.
    ///
    /// - Parameters:
    ///   - count: Number of notes to generate (default 10 000).
    ///   - modelContext: The SwiftData context to insert into.
    ///   - batchSize: Notes committed per save to avoid large transaction spikes.
    ///   - progress: Called on each batch with `(inserted, total)`.
    static func seedNotes(
        count: Int = 10_00,
        into modelContext: ModelContext,
        batchSize: Int = 500,
        progress: @escaping (Int, Int) -> Void = { _, _ in }
    ) async {
        let calendar = Calendar.current
        let now = Date()
        // Spread creation dates over the past two years
        let twoYearsAgo = calendar.date(byAdding: .year, value: -2, to: now) ?? now
        let timeRange = now.timeIntervalSince(twoYearsAgo)

        var inserted = 0

        while inserted < count {
            let remaining = count - inserted
            let currentBatch = min(batchSize, remaining)

            for _ in 0 ..< currentBatch {
                let note = NoteItem(
                    content: randomContent(),
                    createdAt: Date(timeIntervalSinceNow: -Double.random(in: 0 ... timeRange)),
                    updatedAt: Date(timeIntervalSinceNow: -Double.random(in: 0 ... 86_400))
                )
                modelContext.insert(note)
            }

            try? modelContext.save()
            inserted += currentBatch
            progress(inserted, count)

            // Yield to the run loop so the UI stays responsive
            await Task.yield()
        }
    }

    /// Deletes every `NoteItem` (including trashed ones) from the context.
    static func deleteAllNotes(from modelContext: ModelContext) {
        try? modelContext.delete(model: NoteItem.self)
        try? modelContext.save()
    }

    // MARK: - Private helpers

    private static func randomContent() -> String {
        let title = titles.randomElement()!
        let paragraphCount = Int.random(in: 2 ... 6)
        let body = (0 ..< paragraphCount)
            .map { _ in paragraphs.randomElement()! }
            .joined(separator: "\n\n")
        return "# \(title)\n\n\(body)"
    }
}
#endif

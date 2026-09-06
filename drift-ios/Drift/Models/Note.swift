import Foundation

/// A plain Markdown file. The file URL is its identity; the first nonempty line is its title.
struct Note: Identifiable, Hashable, Codable, Sendable {
    let url: URL
    var modified: Date
    var title: String
    var preview: String
    /// A composer or recoverable draft that has not created a shared file yet.
    var isUnsaved: Bool = false

    var id: URL { url }
    static let untitled = "Untitled"

    static func derive(from body: String) -> (title: String, preview: String) {
        // Only inspect the first two nonempty lines, even in a very large document.
        var lines: [String] = []
        body.enumerateLines { line, stop in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { lines.append(trimmed) }
            stop = lines.count == 2
        }
        guard let first = lines.first else { return (untitled, "") }
        let cleaned = first
            .replacingOccurrences(of: #"^#+\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[<>:"/\\|?*\p{Cc}]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = String(cleaned.prefix(50)).trimmingCharacters(in: .whitespacesAndNewlines)
        let safeTitle = title.isEmpty || title == "." || title == ".." ? untitled : title
        return (safeTitle, lines.count > 1 ? String(lines[1].prefix(160)) : "")
    }
}

/// The exact text read from disk is retained separately when recovering an unsaved draft.
/// That baseline is what makes a later save safe in the presence of another device's edits.
struct NoteSnapshot: Sendable {
    let note: Note
    let text: String
    let recoveredDraft: Bool
    let baselineText: String
    let documentID: UUID
    var isUnsaved: Bool { note.isUnsaved }

    init(note: Note, text: String, baselineText: String? = nil, recoveredDraft: Bool = false, documentID: UUID = UUID()) {
        self.note = note
        self.text = text
        self.baselineText = baselineText ?? text
        self.recoveredDraft = recoveredDraft
        self.documentID = documentID
    }
}

struct NoteSaveResult: Sendable {
    let snapshot: NoteSnapshot
    let preservedConflict: Bool
}

struct NoteSearchHit: Identifiable, Sendable {
    let note: Note
    let snippet: String?
    var id: URL { note.id }
}

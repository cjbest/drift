import Foundation

struct Note: Identifiable, Hashable {
    let url: URL
    var modified: Date
    var title: String
    var preview: String

    var id: URL { url }

    static let untitled = "Untitled"

    /// First non-blank line (with `#` heading prefix stripped, filename-unsafe
    /// chars removed, capped at 50 chars) — matching desktop's `sanitizeFilename`.
    /// Second non-blank line becomes the preview.
    static func derive(from body: String) -> (title: String, preview: String) {
        let lines = body
            .split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard let first = lines.first else {
            return (untitled, "")
        }

        let stripped = first
            .replacingOccurrences(of: #"^#+\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[<>:"/\\|?*]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        let title = String(stripped.prefix(50)).trimmingCharacters(in: .whitespaces)
        let preview = lines.count > 1 ? String(lines[1].prefix(80)) : ""

        return (title.isEmpty ? untitled : title, preview)
    }
}

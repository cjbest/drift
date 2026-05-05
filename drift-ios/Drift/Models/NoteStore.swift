import Foundation
import Observation

@MainActor
@Observable
final class NoteStore {
    private let bookmarkKey = "drift.folderBookmark"

    var folderURL: URL?
    var notes: [Note] = []
    var errorMessage: String?

    private var folderAccessing = false
    private var enrichTask: Task<Void, Never>?
    /// Body text per note URL (original case), populated by the background
    /// enrichment pass. Used by `search(_:)` to match full document content
    /// and to extract a snippet of the matching line — without re-reading
    /// files on every keystroke.
    private var bodyCache: [URL: String] = [:]

    init() {
        if let testPath = ProcessInfo.processInfo.environment["DRIFT_TEST_FOLDER"] {
            let url = URL(fileURLWithPath: testPath, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            folderURL = url
            loadNotes()
            return
        }
        restoreFolder()
    }

    // No deinit cleanup: NoteStore lives for the lifetime of the app, so the
    // OS reclaims the security-scoped resource and pending tasks at exit.

    func setFolder(_ url: URL) {
        if folderAccessing, let current = folderURL {
            current.stopAccessingSecurityScopedResource()
            folderAccessing = false
        }

        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = "Couldn't access that folder. Try picking it again."
            return
        }
        folderAccessing = true
        folderURL = url

        do {
            let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        } catch {
            errorMessage = "Saved folder, but couldn't store bookmark: \(error.localizedDescription)"
        }

        loadNotes()
    }

    func clearFolder() {
        enrichTask?.cancel()
        if folderAccessing, let url = folderURL {
            url.stopAccessingSecurityScopedResource()
        }
        folderAccessing = false
        folderURL = nil
        notes = []
        bodyCache.removeAll()
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
    }

    /// Two-pass load. Fast pass (synchronous, on the main thread) lists the
    /// directory and creates `Note`s with the filename as a fallback title — so
    /// the list paints immediately even if the folder is large or some files
    /// live in iCloud and aren't downloaded yet. Slow pass (off the main
    /// thread) reads each body, derives real title/preview, and applies the
    /// cache back on main. Without the split, a launch from a fat iCloud
    /// folder would block the first frame past the iOS launch watchdog.
    func loadNotes() {
        guard let folderURL else {
            notes = []
            return
        }

        let fm = FileManager.default
        do {
            let urls = try fm.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            )

            let fastNotes: [Note] = urls.compactMap { url in
                guard url.pathExtension.lowercased() == "md" else { return nil }
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
                if values?.isRegularFile == false { return nil }
                let modified = values?.contentModificationDate ?? .distantPast
                let fallbackTitle = url.deletingPathExtension().lastPathComponent
                // Preserve any cache we already have for this URL so a refresh
                // doesn't flicker titles back to filenames before the slow pass.
                if let existing = notes.first(where: { $0.url == url }) {
                    return Note(url: url, modified: modified, title: existing.title, preview: existing.preview)
                }
                return Note(url: url, modified: modified, title: fallbackTitle, preview: "")
            }

            notes = fastNotes.sorted { $0.modified > $1.modified }
            errorMessage = nil

            enrichTask?.cancel()
            let urlsToEnrich = notes.map(\.url)
            enrichTask = Task { [weak self] in
                await self?.enrichTitlesAndPreviews(for: urlsToEnrich)
            }
        } catch {
            errorMessage = "Couldn't load folder: \(error.localizedDescription)"
            notes = []
        }
    }

    private func enrichTitlesAndPreviews(for urls: [URL]) async {
        struct Enriched {
            let title: String
            let preview: String
            let body: String
        }

        let derived: [URL: Enriched] = await Task.detached(priority: .userInitiated) {
            var result: [URL: Enriched] = [:]
            for url in urls {
                if Task.isCancelled { return result }
                // Skip iCloud files that aren't downloaded yet — touching them
                // would block on a network fetch. They'll get picked up next
                // time we reload.
                if let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus,
                   status == .notDownloaded {
                    continue
                }
                let body = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                let d = Note.derive(from: body)
                result[url] = Enriched(title: d.title, preview: d.preview, body: body)
            }
            return result
        }.value

        if Task.isCancelled { return }
        notes = notes.map { note in
            guard let d = derived[note.url] else { return note }
            var copy = note
            copy.title = d.title
            copy.preview = d.preview
            return copy
        }
        // Drop body cache entries for URLs that no longer exist in the folder
        // (e.g. deleted out-of-band) so search results stay clean.
        let liveURLs = Set(notes.map(\.url))
        bodyCache = bodyCache.filter { liveURLs.contains($0.key) }
        for (url, d) in derived {
            bodyCache[url] = d.body
        }
    }

    /// One search result: a matched note, plus an optional snippet of the
    /// body line that contained the first match. `snippet` is nil when the
    /// query was empty or matched only the title (in which case the row
    /// falls back to the note's regular preview line).
    struct SearchHit: Identifiable {
        let note: Note
        let snippet: String?
        var id: Note.ID { note.id }
    }

    /// Filters notes by query against title and full body content. The body
    /// is matched against an in-memory cache populated off-main during
    /// enrichment, so every keystroke is just `range(of:options:)` over
    /// already-resident strings — no disk I/O. When the match is in the
    /// body, attaches a snippet of the matching line for display.
    func search(_ query: String) -> [SearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return notes.map { SearchHit(note: $0, snippet: nil) }
        }
        return notes.compactMap { note in
            if note.title.range(of: trimmed, options: .caseInsensitive) != nil {
                return SearchHit(note: note, snippet: nil)
            }
            guard let body = bodyCache[note.url],
                  let matchRange = body.range(of: trimmed, options: .caseInsensitive)
            else { return nil }
            return SearchHit(note: note, snippet: Self.snippet(in: body, around: matchRange))
        }
    }

    /// Returns the line in `body` that contains `matchRange`, trimmed, and
    /// pre-windowed so the match itself is visible with ~18 chars of context
    /// before it. Without this, a match deep in a long line gets cut off by
    /// the row's `lineLimit(1)` truncation. Adds leading/trailing "…"
    /// markers when content was dropped on either side.
    private static func snippet(in body: String, around matchRange: Range<String.Index>) -> String {
        // Walk back to the start of the line.
        var lineStart = matchRange.lowerBound
        while lineStart > body.startIndex {
            let prev = body.index(before: lineStart)
            if body[prev].isNewline { break }
            lineStart = prev
        }
        // Walk forward to the end of the line.
        var lineEnd = matchRange.lowerBound
        while lineEnd < body.endIndex, !body[lineEnd].isNewline {
            lineEnd = body.index(after: lineEnd)
        }

        let line = String(body[lineStart..<lineEnd])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Re-locate the match within the trimmed line. Easier than juggling
        // index offsets across the trim, and robust to leading/trailing
        // whitespace shifts.
        let needle = String(body[matchRange])
        guard let inLine = line.range(of: needle, options: .caseInsensitive) else {
            return line.count <= 200 ? line : String(line.prefix(200)) + "…"
        }

        let prefixContext = 18
        let maxLength = 200

        let charsBefore = line.distance(from: line.startIndex, to: inLine.lowerBound)
        var working = line
        var leadingEllipsis = false
        if charsBefore > prefixContext {
            let dropCount = charsBefore - prefixContext
            let dropIdx = line.index(line.startIndex, offsetBy: dropCount)
            working = String(line[dropIdx...])
            leadingEllipsis = true
        }

        var trailingEllipsis = false
        if working.count > maxLength {
            working = String(working.prefix(maxLength))
            trailingEllipsis = true
        }

        return (leadingEllipsis ? "…" : "") + working + (trailingEllipsis ? "…" : "")
    }

    /// Used by tests: wait for the background enrichment pass to finish so
    /// assertions can read the final cached titles/previews.
    func awaitEnrichmentForTesting() async {
        await enrichTask?.value
    }

    func readContents(of note: Note) -> String {
        (try? String(contentsOf: note.url, encoding: .utf8)) ?? ""
    }

    @discardableResult
    func saveContents(_ text: String, for note: Note) -> Note {
        let derived = Note.derive(from: text)

        do {
            try text.write(to: note.url, atomically: true, encoding: .utf8)
        } catch {
            errorMessage = "Save failed: \(error.localizedDescription)"
            return note
        }

        var updated = Note(url: note.url, modified: Date(), title: derived.title, preview: derived.preview)

        let currentBaseName = note.url.deletingPathExtension().lastPathComponent
        if derived.title != currentBaseName, let folderURL {
            let target = uniqueURL(forBaseName: derived.title, in: folderURL, excluding: note.url)
            do {
                try FileManager.default.moveItem(at: note.url, to: target)
                updated = Note(url: target, modified: Date(), title: derived.title, preview: derived.preview)
            } catch {
                // Keep original URL if rename fails (e.g. permissions).
            }
        }

        if let idx = notes.firstIndex(where: { $0.id == note.id }) {
            notes[idx] = updated
            notes.sort { $0.modified > $1.modified }
        }
        // Keep the body cache in sync so the search results don't lag behind
        // the user's edits.
        if updated.url != note.url {
            bodyCache.removeValue(forKey: note.url)
        }
        bodyCache[updated.url] = text
        return updated
    }

    @discardableResult
    func createNote() -> Note? {
        guard let folderURL else { return nil }
        let url = uniqueURL(forBaseName: Note.untitled, in: folderURL, excluding: nil)
        do {
            try "".write(to: url, atomically: true, encoding: .utf8)
            let note = Note(url: url, modified: Date(), title: Note.untitled, preview: "")
            notes.insert(note, at: 0)
            bodyCache[url] = ""
            return note
        } catch {
            errorMessage = "Couldn't create note: \(error.localizedDescription)"
            return nil
        }
    }

    func delete(_ note: Note) {
        do {
            try FileManager.default.removeItem(at: note.url)
            notes.removeAll { $0.id == note.id }
            bodyCache.removeValue(forKey: note.url)
        } catch {
            errorMessage = "Delete failed: \(error.localizedDescription)"
        }
    }

    private func uniqueURL(forBaseName base: String, in folder: URL, excluding: URL?) -> URL {
        let candidate = folder.appendingPathComponent("\(base).md")
        if !exists(candidate, excluding: excluding) { return candidate }
        var counter = 2
        while true {
            let next = folder.appendingPathComponent("\(base) \(counter).md")
            if !exists(next, excluding: excluding) { return next }
            counter += 1
        }
    }

    private func exists(_ url: URL, excluding: URL?) -> Bool {
        if let excluding, url.standardizedFileURL == excluding.standardizedFileURL { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private func restoreFolder() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        var stale = false
        do {
            let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
            if url.startAccessingSecurityScopedResource() {
                folderAccessing = true
                folderURL = url
                loadNotes()
                if stale {
                    if let refreshed = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                        UserDefaults.standard.set(refreshed, forKey: bookmarkKey)
                    }
                }
            }
        } catch {
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
        }
    }
}

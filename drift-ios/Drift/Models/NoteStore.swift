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
        let derived: [URL: (title: String, preview: String)] = await Task.detached(priority: .userInitiated) {
            var result: [URL: (String, String)] = [:]
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
                result[url] = (d.title, d.preview)
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

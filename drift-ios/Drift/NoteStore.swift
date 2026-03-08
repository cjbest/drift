import Foundation
import Combine

struct Note: Identifiable, Equatable {
    var id: String { path }
    let path: String
    var title: String
    var preview: String
    var createdAt: Date?
    var modifiedAt: Date?
}

class NoteStore: ObservableObject {
    @Published var notes: [Note] = []
    @Published var currentNote: Note?
    @Published var currentContent: String = ""

    private let fileManager = FileManager.default
    private var saveTimer: Timer?
    private var accessTimes: [String: Date] = [:]

    var driftDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("Drift")
    }

    init() {
        ensureDriftDirectory()
        loadAccessTimes()
        refreshNotes()
    }

    private func ensureDriftDirectory() {
        if !fileManager.fileExists(atPath: driftDirectory.path) {
            try? fileManager.createDirectory(at: driftDirectory, withIntermediateDirectories: true)
        }
    }

    private func loadAccessTimes() {
        if let data = UserDefaults.standard.data(forKey: "drift-access-times"),
           let times = try? JSONDecoder().decode([String: Date].self, from: data) {
            accessTimes = times
        }
    }

    private func saveAccessTimes() {
        if let data = try? JSONEncoder().encode(accessTimes) {
            UserDefaults.standard.set(data, forKey: "drift-access-times")
        }
    }

    func recordAccess(for path: String) {
        accessTimes[path] = Date()
        saveAccessTimes()
    }

    func refreshNotes() {
        ensureDriftDirectory()
        guard let files = try? fileManager.contentsOfDirectory(
            at: driftDirectory,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        notes = files
            .filter { $0.pathExtension == "md" }
            .compactMap { url -> Note? in
                let path = url.path
                let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                let attrs = try? fileManager.attributesOfItem(atPath: path)
                let created = attrs?[.creationDate] as? Date
                let modified = attrs?[.modificationDate] as? Date
                return Note(
                    path: path,
                    title: Self.extractTitle(from: content, filename: url.deletingPathExtension().lastPathComponent),
                    preview: Self.extractPreview(from: content),
                    createdAt: created,
                    modifiedAt: modified
                )
            }
            .sorted { noteA, noteB in
                let timeA = max(
                    accessTimes[noteA.path]?.timeIntervalSince1970 ?? 0,
                    noteA.modifiedAt?.timeIntervalSince1970 ?? 0
                )
                let timeB = max(
                    accessTimes[noteB.path]?.timeIntervalSince1970 ?? 0,
                    noteB.modifiedAt?.timeIntervalSince1970 ?? 0
                )
                return timeA > timeB
            }
    }

    func openNote(_ note: Note) {
        let url = URL(fileURLWithPath: note.path)
        if let content = try? String(contentsOf: url, encoding: .utf8) {
            currentContent = content
            currentNote = note
            recordAccess(for: note.path)
        }
    }

    func newNote() {
        // Save current note first
        if currentContent.trimmingCharacters(in: .whitespacesAndNewlines).count > 0 {
            saveNow()
        }
        currentContent = ""
        currentNote = nil
    }

    func saveContent(_ content: String) {
        currentContent = content
        // Debounced save
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            self?.saveNow()
        }
    }

    func saveNow() {
        let content = currentContent
        guard content.trimmingCharacters(in: .whitespacesAndNewlines).count > 0 else { return }

        ensureDriftDirectory()

        if var filePath = currentNote?.path {
            // Existing note - check if title changed for rename
            let currentFilename = URL(fileURLWithPath: filePath).deletingPathExtension().lastPathComponent
            let newFilename = Self.sanitizeFilename(from: content)

            if currentFilename != newFilename {
                let newURL = driftDirectory.appendingPathComponent("\(newFilename).md")
                var newPath = newURL.path

                // Handle duplicates
                var counter = 1
                while fileManager.fileExists(atPath: newPath) && newPath != filePath {
                    let numberedURL = driftDirectory.appendingPathComponent("\(newFilename) \(counter).md")
                    newPath = numberedURL.path
                    counter += 1
                }

                if newPath != filePath {
                    try? fileManager.moveItem(atPath: filePath, toPath: newPath)
                    // Update access times
                    if let oldTime = accessTimes[filePath] {
                        accessTimes.removeValue(forKey: filePath)
                        accessTimes[newPath] = oldTime
                        saveAccessTimes()
                    }
                    filePath = newPath
                }
            }

            try? content.write(toFile: filePath, atomically: true, encoding: .utf8)
            currentNote = Note(
                path: filePath,
                title: Self.extractTitle(from: content, filename: URL(fileURLWithPath: filePath).deletingPathExtension().lastPathComponent),
                preview: Self.extractPreview(from: content),
                createdAt: currentNote?.createdAt,
                modifiedAt: Date()
            )
            recordAccess(for: filePath)
        } else {
            // New note
            let filename = Self.sanitizeFilename(from: content)
            var url = driftDirectory.appendingPathComponent("\(filename).md")

            var counter = 1
            while fileManager.fileExists(atPath: url.path) {
                url = driftDirectory.appendingPathComponent("\(filename) \(counter).md")
                counter += 1
            }

            try? content.write(to: url, atomically: true, encoding: .utf8)
            currentNote = Note(
                path: url.path,
                title: Self.extractTitle(from: content, filename: filename),
                preview: Self.extractPreview(from: content),
                createdAt: Date(),
                modifiedAt: Date()
            )
            recordAccess(for: url.path)
        }

        refreshNotes()
    }

    func deleteNote(_ note: Note) {
        try? fileManager.removeItem(atPath: note.path)
        accessTimes.removeValue(forKey: note.path)
        saveAccessTimes()
        if currentNote?.path == note.path {
            currentContent = ""
            currentNote = nil
        }
        refreshNotes()
    }

    // MARK: - Helpers

    static func sanitizeFilename(from content: String) -> String {
        let lines = content.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let first = lines.first else { return "Untitled" }

        var title = first
        // Remove markdown heading prefix
        if let range = title.range(of: #"^#+\s*"#, options: .regularExpression) {
            title.removeSubrange(range)
        }
        // Remove unsafe filename characters
        let unsafe = CharacterSet(charactersIn: "<>:\"/\\|?*")
        title = title.components(separatedBy: unsafe).joined()
        // Limit length
        if title.count > 50 {
            title = String(title.prefix(50))
        }
        title = title.trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? "Untitled" : title
    }

    static func extractTitle(from content: String, filename: String) -> String {
        let lines = content.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let first = lines.first else { return filename }
        var title = first
        if let range = title.range(of: #"^#+\s*"#, options: .regularExpression) {
            title.removeSubrange(range)
        }
        return title.trimmingCharacters(in: .whitespaces).isEmpty ? filename : title.trimmingCharacters(in: .whitespaces)
    }

    static func extractPreview(from content: String) -> String {
        let lines = content.components(separatedBy: "\n")
            .dropFirst()
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return String(lines.joined(separator: " ").prefix(200))
    }
}

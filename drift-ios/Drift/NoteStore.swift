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
    @Published var iCloudAvailable: Bool = false

    private let fileManager = FileManager.default
    private var saveTimer: Timer?
    private var accessTimes: [String: Date] = [:]
    private var metadataQuery: NSMetadataQuery?

    /// Returns the iCloud container Documents directory if available,
    /// otherwise falls back to the local app Documents directory.
    var driftDirectory: URL {
        if let iCloudURL = fileManager.url(forUbiquityContainerIdentifier: "iCloud.com.drift") {
            return iCloudURL.appendingPathComponent("Documents")
        }
        // Fallback to local storage
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("Drift")
    }

    init() {
        checkiCloudAvailability()
        ensureDriftDirectory()
        loadAccessTimes()
        refreshNotes()
        startMonitoringICloud()
    }

    deinit {
        stopMonitoringICloud()
    }

    // MARK: - iCloud

    private func checkiCloudAvailability() {
        iCloudAvailable = fileManager.ubiquityIdentityToken != nil
    }

    private func startMonitoringICloud() {
        guard iCloudAvailable else { return }

        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K LIKE '*.md'", NSMetadataItemFSNameKey)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(metadataQueryDidUpdate),
            name: .NSMetadataQueryDidUpdate,
            object: query
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(metadataQueryDidFinishGathering),
            name: .NSMetadataQueryDidFinishGathering,
            object: query
        )

        query.start()
        metadataQuery = query
    }

    private func stopMonitoringICloud() {
        metadataQuery?.stop()
        metadataQuery = nil
    }

    @objc private func metadataQueryDidFinishGathering(_ notification: Notification) {
        downloadPendingFiles()
        DispatchQueue.main.async { [weak self] in
            self?.refreshNotes()
        }
    }

    @objc private func metadataQueryDidUpdate(_ notification: Notification) {
        downloadPendingFiles()
        DispatchQueue.main.async { [weak self] in
            self?.refreshNotes()
            // If the current note was modified externally, reload it
            if let currentPath = self?.currentNote?.path,
               let content = try? String(contentsOfFile: currentPath, encoding: .utf8),
               content != self?.currentContent {
                self?.currentContent = content
            }
        }
    }

    /// Tells iCloud to download any files that exist in the cloud but
    /// haven't been pulled to the device yet.
    private func downloadPendingFiles() {
        guard let query = metadataQuery else { return }
        query.disableUpdates()

        for item in query.results {
            guard let mdItem = item as? NSMetadataItem,
                  let url = mdItem.value(forAttribute: NSMetadataItemURLKey) as? URL,
                  let status = mdItem.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String,
                  status != NSMetadataUbiquitousItemDownloadingStatusCurrent
            else { continue }

            try? fileManager.startDownloadingUbiquitousItem(at: url)
        }

        query.enableUpdates()
    }

    // MARK: - File Management

    private func ensureDriftDirectory() {
        let dir = driftDirectory
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
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
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey, .ubiquitousItemDownloadingStatusKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        notes = files
            .filter { $0.pathExtension == "md" }
            .compactMap { url -> Note? in
                let path = url.path
                // Skip files that haven't been downloaded yet
                let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                if let status = values?.ubiquitousItemDownloadingStatus,
                   status != .current {
                    // Trigger download but still show the note with filename as title
                    try? fileManager.startDownloadingUbiquitousItem(at: url)
                    let attrs = try? fileManager.attributesOfItem(atPath: path)
                    return Note(
                        path: path,
                        title: url.deletingPathExtension().lastPathComponent,
                        preview: "Downloading from iCloud…",
                        createdAt: attrs?[.creationDate] as? Date,
                        modifiedAt: attrs?[.modificationDate] as? Date
                    )
                }

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
        if currentContent.trimmingCharacters(in: .whitespacesAndNewlines).count > 0 {
            saveNow()
        }
        currentContent = ""
        currentNote = nil
    }

    func saveContent(_ content: String) {
        currentContent = content
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
            let currentFilename = URL(fileURLWithPath: filePath).deletingPathExtension().lastPathComponent
            let newFilename = Self.sanitizeFilename(from: content)

            if currentFilename != newFilename {
                let newURL = driftDirectory.appendingPathComponent("\(newFilename).md")
                var newPath = newURL.path

                var counter = 1
                while fileManager.fileExists(atPath: newPath) && newPath != filePath {
                    let numberedURL = driftDirectory.appendingPathComponent("\(newFilename) \(counter).md")
                    newPath = numberedURL.path
                    counter += 1
                }

                if newPath != filePath {
                    try? fileManager.moveItem(atPath: filePath, toPath: newPath)
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
        if let range = title.range(of: #"^#+\s*"#, options: .regularExpression) {
            title.removeSubrange(range)
        }
        let unsafe = CharacterSet(charactersIn: "<>:\"/\\|?*")
        title = title.components(separatedBy: unsafe).joined()
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

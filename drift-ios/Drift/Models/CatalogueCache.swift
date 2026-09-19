import Foundation
import CryptoKit

/// A local opening snapshot. Known bodies are retained verbatim as the baseline
/// for a later compare-and-write; unknown bodies are simply absent.
struct CachedCatalogue: Codable, Sendable {
    let folderURL: URL
    let notes: [Note]
    let bodies: [URL: String]
    let canUndoTrash: Bool
}

/// Lexical identities only. Keep permission-bearing URLs untouched and never
/// resolve arbitrary symlinks or ask the provider for resource identifiers.
enum FolderIdentity {
    static func directoryURL(_ url: URL) -> URL {
        let standardized = url.standardizedFileURL
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let standardizedComponents = URLComponents(url: standardized, resolvingAgainstBaseURL: true) else {
            return standardized
        }
        // Appending an empty component is not idempotent on every Foundation
        // runtime: a directory URL can acquire another slash on each call.
        // Edit the encoded path directly to retain host and escaped characters.
        var path = standardizedComponents.percentEncodedPath
        while path.hasSuffix("/") { path.removeLast() }
        components.percentEncodedPath = path + "/"
        return components.url ?? standardized
    }

    static func sameFolder(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.isFileURL && rhs.isFileURL && identity(lhs) == identity(rhs)
    }

    static func cacheKey(for folder: URL) -> String {
        digest(identity(folder))
    }

    /// Validate the entire snapshot before giving its rows the requested URL
    /// spelling. Alias normalization must never import a sibling folder's note.
    static func rebase(_ catalogue: CachedCatalogue, to folder: URL) -> CachedCatalogue? {
        guard sameFolder(catalogue.folderURL, folder) else { return nil }
        let destination = directoryURL(folder)
        var urlsByIdentity: [String: URL] = [:]
        var notes: [Note] = []
        for note in catalogue.notes {
            guard isChild(note.url, of: catalogue.folderURL) else { return nil }
            let key = identity(note.url)
            guard urlsByIdentity[key] == nil else { return nil }
            let url = destination.appendingPathComponent(note.url.lastPathComponent, isDirectory: false)
            urlsByIdentity[key] = url
            notes.append(Note(url: url, modified: note.modified, title: note.title,
                              preview: note.preview, isUnsaved: note.isUnsaved))
        }
        var bodies: [URL: String] = [:]
        for (source, text) in catalogue.bodies {
            guard isChild(source, of: catalogue.folderURL),
                  let url = urlsByIdentity[identity(source)], bodies[url] == nil else { return nil }
            bodies[url] = text
        }
        return CachedCatalogue(folderURL: destination, notes: notes, bodies: bodies,
                               canUndoTrash: catalogue.canUndoTrash)
    }

    private static func isChild(_ url: URL, of folder: URL) -> Bool {
        url.isFileURL && url == url.standardizedFileURL
            && sameFolder(url.deletingLastPathComponent(), folder)
    }

    private static func identity(_ url: URL) -> String {
        let standardized = url.standardizedFileURL
        var path = standardized.path
        // /var is the system alias for /private/var. Do not normalize any other
        // symlink, filename case, or provider-specific spelling.
        if path == "/private/var" || path.hasPrefix("/private/var/") {
            path.removeFirst("/private".count)
        }
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        if let host = url.host, !host.isEmpty { return "file://\(host)\(path)" }
        return path
    }

    fileprivate static func legacyKeys(for folder: URL) -> [String] {
        let standardized = folder.standardizedFileURL
        guard var components = URLComponents(url: folder, resolvingAgainstBaseURL: true),
              let standardizedComponents = URLComponents(url: standardized, resolvingAgainstBaseURL: true) else {
            return [digest(folder.absoluteString)]
        }
        components.percentEncodedPath = standardizedComponents.percentEncodedPath
        var spellings = [folder.absoluteString]
        if let url = components.url { spellings.append(url.absoluteString) }
        let encodedPath = components.percentEncodedPath
        var paths = [encodedPath]
        if encodedPath == "/private/var" || encodedPath.hasPrefix("/private/var/") {
            paths.append(String(encodedPath.dropFirst("/private".count)))
        } else if encodedPath == "/var" || encodedPath.hasPrefix("/var/") {
            paths.append("/private" + encodedPath)
        }
        for var path in paths {
            while path.hasSuffix("/") { path.removeLast() }
            for isDirectory in [false, true] {
                // Keep the original host and escapes while varying only the
                // known alias and directory slash. No filesystem inspection.
                components.percentEncodedPath = path + (isDirectory || path.isEmpty ? "/" : "")
                if let variant = components.url { spellings.append(variant.absoluteString) }
            }
        }
        var seen = Set<String>()
        return spellings.map(digest).filter { seen.insert($0).inserted }
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// The small launch index is durable and excluded from backup. Body snapshots
/// remain purgeable; the draft journal is responsible for unsaved writing.
/// Neither storage location reads provider metadata or note files.
actor CatalogueCache {
    static let shared = CatalogueCache()
    private nonisolated static let sequences = CatalogueWriteSequence()

    nonisolated static func reserveSequence() -> UInt64 { sequences.reserve() }

    private var latestSequence: [String: UInt64] = [:]

    private init() {}

    /// A small local index is safe to read before the first frame. Note bodies
    /// stay in the separate catalogue so a large notebook does not make launch
    /// decode every document on the main actor.
    nonisolated static func loadIndex(folder: URL) -> CachedCatalogue? {
        guard folder.isFileURL else { return nil }
        var candidates: [URL] = []
        if let durable = try? indexFile(for: folder, creatingDirectory: false) {
            candidates.append(durable)
        }
        candidates += legacyCacheFiles(for: folder, indexOnly: true)
        for file in candidates {
            guard let data = try? Data(contentsOf: file),
                  let catalogue = try? JSONDecoder().decode(CachedCatalogue.self, from: data),
                  catalogue.bodies.isEmpty,
                  let validated = validated(catalogue, for: folder) else { continue }
            return validated
        }
        return nil
    }

    func load(folder: URL) -> CachedCatalogue? {
        guard folder.isFileURL else { return nil }
        var candidates: [URL] = []
        if let current = try? Self.cacheFile(for: folder, creatingDirectory: false) {
            candidates.append(current)
        }
        candidates += Self.legacyCacheFiles(for: folder)
        for file in candidates {
            guard let data = try? Data(contentsOf: file),
                  let catalogue = try? JSONDecoder().decode(CachedCatalogue.self, from: data),
                  let validated = Self.validated(catalogue, for: folder) else { continue }
            return validated
        }
        // A missing, purged, older, or damaged body cache never blocks the folder.
        return nil
    }

    func store(_ catalogue: CachedCatalogue, sequence: UInt64) throws {
        guard catalogue.folderURL.isFileURL else { throw CacheError.invalidCatalogue }
        let folder = FolderIdentity.directoryURL(catalogue.folderURL)
        let key = FolderIdentity.cacheKey(for: folder)
        guard sequence >= latestSequence[key, default: 0] else { return }
        // Reserve the newer position even if this write fails: an older task
        // completing afterward must not put deleted or stale rows back on disk.
        latestSequence[key] = sequence

        let notes = catalogue.notes.filter { !$0.isUnsaved }
        let noteURLs = Set(notes.map(\.url))
        let persisted = CachedCatalogue(folderURL: folder, notes: notes,
                                        bodies: catalogue.bodies.filter { noteURLs.contains($0.key) },
                                        canUndoTrash: catalogue.canUndoTrash)
        guard let cached = Self.validated(persisted, for: folder) else { throw CacheError.invalidCatalogue }
        let index = CachedCatalogue(folderURL: folder, notes: cached.notes, bodies: [:],
                                    canUndoTrash: cached.canUndoTrash)
        // First-frame rows must survive a failed, slow, or interrupted body write.
        var indexFile = try Self.indexFile(for: folder, creatingDirectory: true)
        try JSONEncoder().encode(index).write(to: indexFile, options: [.atomic])
        try Self.excludeFromBackup(&indexFile)
        let file = try Self.cacheFile(for: folder, creatingDirectory: true)
        try JSONEncoder().encode(cached).write(to: file, options: [.atomic])
    }

    nonisolated private static func validated(_ catalogue: CachedCatalogue, for folder: URL) -> CachedCatalogue? {
        guard catalogue.notes.allSatisfy({ !$0.isUnsaved }) else { return nil }
        return FolderIdentity.rebase(catalogue, to: folder)
    }

    nonisolated private static func indexFile(for folder: URL, creatingDirectory: Bool) throws -> URL {
        let fileManager = FileManager.default
        let support = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                          appropriateFor: nil, create: creatingDirectory)
        var directory = support.appendingPathComponent("Drift", isDirectory: true)
            .appendingPathComponent("LaunchIndexes", isDirectory: true)
        if creatingDirectory {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try excludeFromBackup(&directory)
        }
        return directory.appendingPathComponent("\(FolderIdentity.cacheKey(for: folder)).json")
    }

    nonisolated private static func excludeFromBackup(_ url: inout URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    nonisolated private static func cacheDirectory(creating: Bool) throws -> URL {
        let fileManager = FileManager.default
        let caches = try fileManager.url(for: .cachesDirectory, in: .userDomainMask,
                                         appropriateFor: nil, create: creating)
        let directory = caches.appendingPathComponent("Drift", isDirectory: true)
            .appendingPathComponent("Catalogues", isDirectory: true)
        if creating {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    nonisolated private static func cacheFile(for folder: URL, creatingDirectory: Bool) throws -> URL {
        try cacheDirectory(creating: creatingDirectory)
            .appendingPathComponent("\(FolderIdentity.cacheKey(for: folder)).json")
    }

    nonisolated private static func legacyCacheFiles(for folder: URL, indexOnly: Bool = false) -> [URL] {
        guard let directory = try? cacheDirectory(creating: false) else { return [] }
        return FolderIdentity.legacyKeys(for: folder).map {
            directory.appendingPathComponent("\($0)\(indexOnly ? ".index" : "").json")
        }
    }

    private enum CacheError: Error { case invalidCatalogue }
}

private final class CatalogueWriteSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64 = 0

    func reserve() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}

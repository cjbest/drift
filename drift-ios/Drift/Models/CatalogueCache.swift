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

/// Purgeable, local-only catalogue storage. This never reads provider metadata
/// or note files, and the draft journal remains responsible for unsaved notes.
actor CatalogueCache {
    static let shared = CatalogueCache()
    private nonisolated static let sequences = CatalogueWriteSequence()

    nonisolated static func reserveSequence() -> UInt64 { sequences.reserve() }

    private let fileManager = FileManager.default
    private var latestSequence: [URL: UInt64] = [:]

    private init() {}

    func load(folder: URL) -> CachedCatalogue? {
        guard folder.isFileURL else { return nil }
        let canonicalFolder = folder.standardizedFileURL
        do {
            let file = try cacheFile(for: canonicalFolder, creatingDirectory: false)
            let data = try Data(contentsOf: file)
            let catalogue = try JSONDecoder().decode(CachedCatalogue.self, from: data)
            guard isValid(catalogue, for: canonicalFolder) else { return nil }
            return catalogue
        } catch {
            // A missing, purged, older, or damaged cache never blocks the folder.
            return nil
        }
    }

    func store(_ catalogue: CachedCatalogue, sequence: UInt64) throws {
        guard catalogue.folderURL.isFileURL else { throw CacheError.invalidCatalogue }
        let folder = catalogue.folderURL.standardizedFileURL
        guard sequence >= latestSequence[folder, default: 0] else { return }
        // Reserve the newer position even if this write fails: an older task
        // completing afterward must not put deleted or stale rows back on disk.
        latestSequence[folder] = sequence

        let notes = catalogue.notes.filter { !$0.isUnsaved }
        let noteURLs = Set(notes.map(\.url))
        let cached = CachedCatalogue(folderURL: folder, notes: notes,
                                     bodies: catalogue.bodies.filter { noteURLs.contains($0.key) },
                                     canUndoTrash: catalogue.canUndoTrash)
        guard isValid(cached, for: folder) else { throw CacheError.invalidCatalogue }
        let file = try cacheFile(for: folder, creatingDirectory: true)
        try JSONEncoder().encode(cached).write(to: file, options: [.atomic])
    }

    private func isValid(_ catalogue: CachedCatalogue, for folder: URL) -> Bool {
        guard catalogue.folderURL.isFileURL,
              catalogue.folderURL.standardizedFileURL == folder else { return false }
        let noteURLs = Set(catalogue.notes.map(\.url))
        guard noteURLs.count == catalogue.notes.count,
              catalogue.notes.allSatisfy({ !$0.isUnsaved && isChild($0.url, of: folder) }),
              catalogue.bodies.keys.allSatisfy({ isChild($0, of: folder) && noteURLs.contains($0) })
        else { return false }
        return true
    }

    private func isChild(_ url: URL, of folder: URL) -> Bool {
        // Standardization is lexical. Do not resolve symlinks or request any
        // resource values here; that would put provider I/O back in opening.
        url.isFileURL && url == url.standardizedFileURL
            && url.deletingLastPathComponent().standardizedFileURL == folder
    }

    private func cacheFile(for folder: URL, creatingDirectory: Bool) throws -> URL {
        let caches = try fileManager.url(for: .cachesDirectory, in: .userDomainMask,
                                         appropriateFor: nil, create: creatingDirectory)
        let directory = caches.appendingPathComponent("Drift", isDirectory: true)
            .appendingPathComponent("Catalogues", isDirectory: true)
        if creatingDirectory {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let key = SHA256.hash(data: Data(folder.absoluteString.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("\(key).json")
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

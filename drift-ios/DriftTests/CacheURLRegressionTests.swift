import Foundation
import Testing
@testable import Drift

/// Synthetic URLs only: no selected notebook or provider contents are accessed.
struct CacheURLRegressionTests {
    private func directory() -> URL {
        URL(fileURLWithPath: "/private/var/mobile/Drift-Cache-Regression-\(UUID().uuidString)",
            isDirectory: true)
    }

    private func withoutDirectorySlash(_ url: URL) throws -> URL {
        try #require(URL(string: String(url.absoluteString.dropLast())))
    }

    private func varAlias(_ url: URL) throws -> URL {
        try #require(URL(string: url.absoluteString.replacingOccurrences(
            of: "file:///private/var/", with: "file:///var/")))
    }

    private func catalogue(folder: URL, noteURL: URL? = nil) -> CachedCatalogue {
        let url = noteURL ?? folder.appendingPathComponent("Synthetic.md").standardizedFileURL
        return CachedCatalogue(folderURL: folder,
                               notes: [Note(url: url, modified: Date(timeIntervalSince1970: 1_700_000_000),
                                            title: "Synthetic", preview: "Disposable cache fixture")],
                               bodies: [url: "Synthetic\nDisposable cache fixture"],
                               canUndoTrash: false)
    }

    @Test
    func directoryNormalizationIsIdempotentAndHasOneTrailingSlash() throws {
        for spelling in [
            "file:///var/mobile/Synthetic%20folder",
            "file:///var/mobile/Synthetic%20folder/",
            "file:///var/mobile/Synthetic%20folder//",
            "file:///private/var/mobile/Synthetic%20folder/",
            "file://example.invalid/Synthetic%20folder/",
            "file:///"
        ] {
            let original = try #require(URL(string: spelling))
            let normalized = FolderIdentity.directoryURL(original)
            #expect(FolderIdentity.directoryURL(normalized) == normalized)
            let components = try #require(URLComponents(url: normalized, resolvingAgainstBaseURL: true))
            #expect(components.percentEncodedPath.hasSuffix("/"))
            #expect(!components.percentEncodedPath.hasSuffix("//"))
            #expect(normalized.host == original.host)
            #expect(normalized.path == original.standardizedFileURL.path)
        }
        let local = try #require(URL(string: "file:///var/mobile/Synthetic%20folder/"))
        let remote = try #require(URL(string: "file://example.invalid/var/mobile/Synthetic%20folder/"))
        #expect(!FolderIdentity.sameFolder(local, remote))
        #expect(FolderIdentity.cacheKey(for: local) != FolderIdentity.cacheKey(for: remote))
    }

    @Test
    func slashlessDirectoryCanPersistOpeningIndex() async throws {
        let folder = try withoutDirectorySlash(directory())
        try await CatalogueCache.shared.store(catalogue(folder: folder),
                                              sequence: CatalogueCache.reserveSequence())
        let index = try #require(CatalogueCache.loadIndex(folder: folder))
        #expect(index.notes.count == 1)
        #expect(index.bodies.isEmpty)
    }

    @Test
    func directorySlashDoesNotChangeOpeningIndexLookup() async throws {
        let folder = directory()
        try await CatalogueCache.shared.store(catalogue(folder: folder),
                                              sequence: CatalogueCache.reserveSequence())
        let alias = try withoutDirectorySlash(folder)
        let index = try #require(CatalogueCache.loadIndex(folder: alias))
        #expect(index.notes.count == 1)
    }

    @Test
    func varAliasDoesNotRejectAChildInTheSameDirectory() async throws {
        let folder = directory()
        let child = try varAlias(folder.appendingPathComponent("Synthetic.md"))
        try await CatalogueCache.shared.store(catalogue(folder: folder, noteURL: child),
                                              sequence: CatalogueCache.reserveSequence())
        let index = try #require(CatalogueCache.loadIndex(folder: folder))
        #expect(index.notes.count == 1)
    }

    @Test
    func varAliasesFindTheSameOpeningIndex() async throws {
        let folder = directory()
        try await CatalogueCache.shared.store(catalogue(folder: folder),
                                              sequence: CatalogueCache.reserveSequence())
        let alias = try varAlias(folder)
        let index = try #require(CatalogueCache.loadIndex(folder: alias))
        #expect(index.notes.count == 1)
    }

    @Test
    func aliasNormalizationStillRejectsChildrenOfADifferentDirectory() async throws {
        let folder = directory()
        let sibling = folder.deletingLastPathComponent()
            .appendingPathComponent(folder.lastPathComponent + "-sibling", isDirectory: true)
            .appendingPathComponent("Synthetic.md")
        let child = try varAlias(sibling)
        do {
            try await CatalogueCache.shared.store(catalogue(folder: folder, noteURL: child),
                                                  sequence: CatalogueCache.reserveSequence())
            Issue.record("A sibling-directory note must never be accepted as part of this cache")
        } catch {
            // Rejecting the catalogue preserves the selected-folder boundary.
        }
        #expect(CatalogueCache.loadIndex(folder: folder) == nil)
    }
}

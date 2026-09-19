import Foundation
import Testing
@testable import Drift

struct LaunchPreferencesTests {
    @Test func defaultsToListAndRemembersChoice() throws {
        let name = "drift-launch-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = LaunchPreferences(defaults: defaults)
        #expect(preferences.destination == .notesList)
        preferences.destination = .newNote
        #expect(LaunchPreferences(defaults: defaults).destination == .newNote)
        defaults.set("unknown-future-option", forKey: "drift.onLaunch")
        #expect(preferences.destination == .notesList)
    }

    @Test func lastNoteIsScopedToFolderAndLateRenamesCannotReplaceAnotherNote() throws {
        let name = "drift-launch-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = LaunchPreferences(defaults: defaults)
        let folder = URL(fileURLWithPath: "/tmp/first", isDirectory: true)
        let other = URL(fileURLWithPath: "/tmp/second", isDirectory: true)
        let first = Note(url: folder.appendingPathComponent("First.md"), modified: .now, title: "First", preview: "")
        let second = Note(url: folder.appendingPathComponent("Second.md"), modified: .now, title: "Second", preview: "")
        let pinned = Note(url: folder.appendingPathComponent("First.pinned.md"), modified: .now, title: "First", preview: "")
        preferences.remember(first, in: folder)
        #expect(preferences.lastNote(in: folder) == first.url)
        #expect(preferences.lastNote(in: other) == nil)
        preferences.remember(first, in: other)
        #expect(preferences.lastNote(in: other) == nil)
        defaults.set(["location": 27], forKey: "drift.editor.position." + first.url.absoluteString)
        preferences.relocate(from: first.url, to: pinned, in: folder)
        #expect(preferences.lastNote(in: folder) == pinned.url)
        #expect(defaults.dictionary(forKey: "drift.editor.position." + pinned.url.absoluteString)?["location"] as? Int == 27)
        preferences.remember(second, in: folder)
        preferences.relocate(from: pinned.url, to: first, in: folder)
        #expect(preferences.lastNote(in: folder) == second.url)
        #expect(defaults.dictionary(forKey: "drift.editor.position." + first.url.absoluteString)?["location"] as? Int == 27)
        #expect(defaults.dictionary(forKey: "drift.editor.position." + pinned.url.absoluteString) == nil)
    }
}

import Foundation

enum LaunchDestination: String, CaseIterable {
    case notesList, openLast, newNote

    var title: String {
        switch self {
        case .notesList: return "Notes List"
        case .openLast: return "Open Last"
        case .newNote: return "New Note"
        }
    }
}

/// Device preferences stay local; the notes and their pins travel with the folder.
struct LaunchPreferences {
    var defaults: UserDefaults = .standard

    var destination: LaunchDestination {
        get { LaunchDestination(rawValue: defaults.string(forKey: "drift.onLaunch") ?? "") ?? .notesList }
        nonmutating set { defaults.set(newValue.rawValue, forKey: "drift.onLaunch") }
    }

    func lastNote(in folder: URL) -> URL? {
        guard let value = defaults.string(forKey: key(folder)), let url = URL(string: value),
              url.isFileURL, url.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL else { return nil }
        return url
    }

    func remember(_ note: Note, in folder: URL) {
        guard note.url.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL else { return }
        defaults.set(note.url.absoluteString, forKey: key(folder))
    }

    func relocate(from oldURL: URL, to note: Note, in folder: URL) {
        guard oldURL != note.url,
              oldURL.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL,
              note.url.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL else { return }
        if lastNote(in: folder) == oldURL { remember(note, in: folder) }
        let oldKey = "drift.editor.position." + oldURL.absoluteString
        if let position = defaults.dictionary(forKey: oldKey) {
            defaults.set(position, forKey: "drift.editor.position." + note.url.absoluteString)
            defaults.removeObject(forKey: oldKey)
        }
    }

    private func key(_ folder: URL) -> String {
        "drift.lastNote." + folder.standardizedFileURL.absoluteString
    }
}

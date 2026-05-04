import Foundation

struct Note: Identifiable, Hashable {
    let url: URL
    var modified: Date

    var id: URL { url }

    var title: String {
        url.deletingPathExtension().lastPathComponent
    }
}

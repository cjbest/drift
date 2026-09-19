import SwiftUI

@main
struct DriftApp: App {
    @UIApplicationDelegateAdaptor(DriftApplicationDelegate.self) private var applicationDelegate

    init() {
        LaunchDiagnostics.record("app_init", once: true)
        FontLoader.registerAll()
        #if DEBUG && targetEnvironment(simulator)
        persistUITestFolderIfRequested()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .ignoresSafeArea()
                .tint(Theme.accent)
        }
    }

    #if DEBUG && targetEnvironment(simulator)
    /// SpringBoard launches do not inherit XCTest's launch environment. Opt-in
    /// simulator tests can remember their synthetic folder through the real
    /// bookmark path before exercising a Home Screen cold launch.
    private func persistUITestFolderIfRequested() {
        let environment = ProcessInfo.processInfo.environment
        guard environment["DRIFT_TEST_PERSIST_FOLDER"] == "1",
              let path = environment["DRIFT_TEST_FOLDER"], !path.isEmpty else { return }
        let folder = path == "__APP_TEMP__"
            ? FileManager.default.temporaryDirectory.appendingPathComponent("drift-ui-tests", isDirectory: true)
            : URL(fileURLWithPath: path, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let bookmark = try folder.bookmarkData(options: [.minimalBookmark],
                                                   includingResourceValuesForKeys: nil, relativeTo: nil)
            FolderBookmark.save(bookmark, folder: folder, in: .standard)
        } catch {
            assertionFailure("Could not register the synthetic UI-test folder")
        }
    }
    #endif
}

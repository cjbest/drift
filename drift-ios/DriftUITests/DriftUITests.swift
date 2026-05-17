import XCTest

final class DriftUITests: XCTestCase {

    var tempFolder: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        tempFolder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("drift-ui-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempFolder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempFolder)
    }

    /// Seeds a `.md` file whose first line matches `title` (so the derived
    /// in-app title equals `title`, since the desktop convention is "first
    /// line is the title"). Pass `extraBody` for everything after.
    private func seed(title: String, extraBody: String = "") throws {
        let url = tempFolder.appendingPathComponent("\(title).md")
        let body = extraBody.isEmpty ? title : "\(title)\n\(extraBody)"
        try body.write(to: url, atomically: true, encoding: .utf8)
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["DRIFT_TEST_FOLDER"] = tempFolder.path
        app.launch()
        return app
    }

    func testListShowsSeededNotes() throws {
        try seed(title: "First Note", extraBody: "This is the first note.")
        try seed(title: "Second Note", extraBody: "Just some content.")

        let app = launchApp()

        XCTAssertTrue(app.staticTexts["First Note"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Second Note"].exists)
    }

    func testTappingNoteOpensEditorWithContent() throws {
        try seed(title: "Welcome", extraBody: "A note editor.")

        let app = launchApp()
        let row = app.staticTexts["Welcome"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertEqual(editor.value as? String, "Welcome\nA note editor.")
    }

    func testCaptureScreenshots() throws {
        try seed(title: "Welcome to Drift", extraBody: "\nA simple note editor for iOS.\n\n- Notes sync via iCloud Drive\n- Each note is a plain `.md` file\n- Auto-saves as you type")
        try seed(title: "Grocery list", extraBody: "- milk\n- bread\n- coffee beans\n- eggs")
        try seed(title: "Meeting notes 2026-05-03", extraBody: "\n# Weekly sync\n\n- shipping iOS app overnight\n- iCloud Drive folder model is wildly simple\n- ship it")

        let app = launchApp()
        XCTAssertTrue(app.staticTexts["Welcome to Drift"].waitForExistence(timeout: 5))

        let listShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        listShot.name = "list"
        listShot.lifetime = .keepAlways
        add(listShot)

        app.staticTexts["Welcome to Drift"].tap()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        Thread.sleep(forTimeInterval: 0.4)

        let editorShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        editorShot.name = "editor"
        editorShot.lifetime = .keepAlways
        add(editorShot)
    }

    func testCaptureReadmeScreenshots() throws {
        try seed(title: "Welcome to Drift", extraBody: "\nPlain markdown notes that follow you everywhere.\n\nPick a folder. Drop it in iCloud Drive. Your phone, laptop, and iPad all see the same notes.\n\n- Auto-saves as you type\n- Search across every note\n- Tap the pencil to start a new one\n- Swipe left on a row to delete\n\nNo accounts. No lock-in. Just notes.")
        try seed(title: "Trip to Lisbon", extraBody: "\nThree days in May. Stay in Alfama.\n\nFood\n- Cervejaria Ramiro, go early\n- Pastéis de Belém, worth the line once\n\nWalks\n- Sunset at Miradouro da Senhora do Monte\n- Tram 28 end to end on a weekday morning")
        try seed(title: "Sourdough notes", extraBody: "\nThe 80% hydration loaf works at my altitude if I drop the bulk by 30 minutes.\n\n- Mix at 9am, autolyse 1hr\n- 4 sets of folds, 30 min apart\n- Bulk until 50% rise (about 4hr in summer)\n- Shape, cold proof overnight\n- Bake at 500F covered 20min, uncovered 20min")
        try seed(title: "Grocery list", extraBody: "\n- milk\n- bread\n- coffee beans\n- eggs\n- olive oil\n- tomatoes\n- garlic")

        let app = launchApp()
        XCTAssertTrue(app.staticTexts["Welcome to Drift"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 0.6) // let the list settle

        // Marker-file sync with the host orchestrator: simulator apps see the
        // host's /tmp, so we drop a sentinel and wait for the host to remove it
        // after taking a screencapture of the Simulator window (which includes
        // the device bezel — XCUIScreen.screenshot() does not).
        let listMarker = "/tmp/drift-marker-list"
        let editorMarker = "/tmp/drift-marker-editor"
        let fm = FileManager.default
        try? fm.removeItem(atPath: listMarker)
        try? fm.removeItem(atPath: editorMarker)

        fm.createFile(atPath: listMarker, contents: nil)
        let listDeadline = Date().addingTimeInterval(45)
        while fm.fileExists(atPath: listMarker) && Date() < listDeadline {
            Thread.sleep(forTimeInterval: 0.2)
        }

        app.staticTexts["Welcome to Drift"].tap()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.6)

        fm.createFile(atPath: editorMarker, contents: nil)
        let editorDeadline = Date().addingTimeInterval(45)
        while fm.fileExists(atPath: editorMarker) && Date() < editorDeadline {
            Thread.sleep(forTimeInterval: 0.2)
        }
    }

    func testCreateNoteAndType() throws {
        let app = launchApp()
        app.buttons["square.and.pencil"].tap()

        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.tap()
        editor.typeText("Shopping list")

        // Wait for autosave (400ms debounce) plus the file rename.
        Thread.sleep(forTimeInterval: 1.0)

        // The file should have been renamed from "Untitled.md" to "Shopping list.md".
        let renamed = tempFolder.appendingPathComponent("Shopping list.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.path))
        let body = (try? String(contentsOf: renamed, encoding: .utf8)) ?? ""
        XCTAssertEqual(body, "Shopping list")
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempFolder.appendingPathComponent("Untitled.md").path))
    }
}

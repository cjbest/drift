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

    func testSystemBackGestureReturnsToList() throws {
        try seed(title: "Swipe Back", extraBody: "The native edge gesture should pop.")

        let app = launchApp()
        let row = app.staticTexts["Swipe Back"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3))

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.50))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.50))
        start.press(forDuration: 0.05, thenDragTo: end)

        XCTAssertTrue(row.waitForExistence(timeout: 2))
        XCTAssertFalse(editor.exists)
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

    func testCreateNoteAndType() throws {
        let app = launchApp()
        app.buttons["New Note"].tap()

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

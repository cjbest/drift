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

    private func seed(_ name: String, body: String) throws {
        let url = tempFolder.appendingPathComponent("\(name).md")
        try body.write(to: url, atomically: true, encoding: .utf8)
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["DRIFT_TEST_FOLDER"] = tempFolder.path
        app.launch()
        return app
    }

    func testListShowsSeededNotes() throws {
        try seed("First Note", body: "# Hello\nThis is the first note.")
        try seed("Second Note", body: "Just some content.")

        let app = launchApp()

        XCTAssertTrue(app.staticTexts["First Note"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Second Note"].exists)
    }

    func testTappingNoteOpensEditorWithContent() throws {
        try seed("Welcome", body: "# Welcome to Drift\nA note editor.")

        let app = launchApp()
        let row = app.staticTexts["Welcome"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        XCTAssertTrue(app.navigationBars["Welcome"].waitForExistence(timeout: 3))
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertTrue(editor.value as? String == "# Welcome to Drift\nA note editor.")
    }

    func testCaptureScreenshots() throws {
        // Demo screenshots written to /tmp on the host (via simulator's tmp).
        try seed("Welcome to Drift", body: "# Welcome to Drift\n\nA simple note editor for iOS.\n\n- Notes sync via iCloud Drive\n- Each note is a plain `.md` file\n- Auto-saves as you type")
        try seed("Grocery list", body: "- milk\n- bread\n- coffee beans\n- eggs")
        try seed("Meeting notes 2026-05-03", body: "# Weekly sync\n\n- shipping iOS app overnight\n- iCloud Drive folder model is wildly simple\n- ship it")

        let app = launchApp()
        XCTAssertTrue(app.staticTexts["Welcome to Drift"].waitForExistence(timeout: 5))

        let listShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        listShot.name = "list"
        listShot.lifetime = .keepAlways
        add(listShot)

        app.staticTexts["Welcome to Drift"].tap()
        XCTAssertTrue(app.navigationBars["Welcome to Drift"].waitForExistence(timeout: 3))
        Thread.sleep(forTimeInterval: 0.4)

        let editorShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        editorShot.name = "editor"
        editorShot.lifetime = .keepAlways
        add(editorShot)
    }

    func testCreateNoteAndType() throws {
        let app = launchApp()
        // Empty state — tap the compose button (square.and.pencil).
        app.buttons["square.and.pencil"].tap()

        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.tap()
        editor.typeText("hello from the test")

        // Wait for autosave (400ms debounce).
        Thread.sleep(forTimeInterval: 0.8)

        // Verify file written to disk.
        let url = tempFolder.appendingPathComponent("Untitled.md")
        let body = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        XCTAssertEqual(body, "hello from the test")
    }
}

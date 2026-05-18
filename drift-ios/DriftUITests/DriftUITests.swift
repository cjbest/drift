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

    private func seedEmptyNote(named fileName: String) throws {
        let url = tempFolder.appendingPathComponent("\(fileName).md")
        try "".write(to: url, atomically: true, encoding: .utf8)
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["DRIFT_TEST_FOLDER"] = tempFolder.path
        app.launch()
        return app
    }

    private func launchAppBackedByAppTemp(focusDelayMS: Int? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["DRIFT_TEST_FOLDER"] = "__APP_TEMP__"
        app.launchEnvironment["DRIFT_RESET_TEST_FOLDER"] = "1"
        if let focusDelayMS {
            app.launchEnvironment["DRIFT_FOCUS_DELAY_MS"] = "\(focusDelayMS)"
        }
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

    func testCreateEmptyNoteThenBackDeletesIt() throws {
        let app = launchApp()
        app.buttons["New Note"].tap()

        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        app.buttons["Back"].tap()

        Thread.sleep(forTimeInterval: 0.5)

        XCTAssertFalse(FileManager.default.fileExists(atPath: tempFolder.appendingPathComponent("Untitled.md").path))
        XCTAssertTrue(app.staticTexts["No notes yet"].waitForExistence(timeout: 2))
    }

    func testOpeningEmptyNoteAutofocusesEditor() throws {
        try seedEmptyNote(named: "Blank")

        let app = launchApp()
        let fallbackRow = app.staticTexts["Blank"]
        let untitledRow = app.staticTexts["Untitled"]
        XCTAssertTrue(fallbackRow.waitForExistence(timeout: 2) || untitledRow.waitForExistence(timeout: 3))
        (fallbackRow.exists ? fallbackRow : untitledRow).tap()

        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        Thread.sleep(forTimeInterval: 0.4)
        editor.typeText("Empty opened")

        Thread.sleep(forTimeInterval: 1.0)

        let renamed = tempFolder.appendingPathComponent("Empty opened.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.path))
    }

    func testLongPressMenuDeletesNoteAfterConfirmation() throws {
        try seed(title: "Delete Me", extraBody: "This should go away.")

        let app = launchApp()
        let row = app.staticTexts["Delete Me"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.press(forDuration: 1.0)

        let deleteMenuItem = app.buttons["Delete"]
        XCTAssertTrue(deleteMenuItem.waitForExistence(timeout: 2))
        deleteMenuItem.tap()
        XCTAssertFalse(app.textViews.firstMatch.exists)

        let alert = app.alerts["Delete Note?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 2))
        alert.buttons["Delete"].tap()

        Thread.sleep(forTimeInterval: 0.5)

        XCTAssertFalse(FileManager.default.fileExists(atPath: tempFolder.appendingPathComponent("Delete Me.md").path))
        XCTAssertFalse(row.exists)
    }

    func testLongPressMenuDeletesShortNoteWithoutConfirmation() throws {
        try seed(title: "Short")

        let app = launchApp()
        let row = app.staticTexts["Short"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.press(forDuration: 1.0)

        let deleteMenuItem = app.buttons["Delete"]
        XCTAssertTrue(deleteMenuItem.waitForExistence(timeout: 2))
        deleteMenuItem.tap()

        XCTAssertFalse(app.alerts["Delete Note?"].waitForExistence(timeout: 0.7))
        XCTAssertFalse(app.textViews.firstMatch.exists)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempFolder.appendingPathComponent("Short.md").path))
        XCTAssertFalse(row.exists)
    }

    func testCaptureTopBarGlassWhileScrolled() throws {
        for i in 1...40 {
            try seed(title: String(format: "Note %02d", i), extraBody: "Body for note \(i).")
        }

        let app = launchApp()
        XCTAssertTrue(app.staticTexts["Note 40"].waitForExistence(timeout: 5))

        let table = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.tables.firstMatch
        XCTAssertTrue(table.exists)

        // Scroll the list up several times so the chrome floats over content.
        for _ in 0..<3 {
            table.swipeUp(velocity: .slow)
        }
        Thread.sleep(forTimeInterval: 0.5)

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "topbar-glass-scrolled"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testCaptureKeyboardPresentationFrames() throws {
        guard ProcessInfo.processInfo.environment["DRIFT_CAPTURE_KEYBOARD"] == "1" else {
            throw XCTSkip("Set DRIFT_CAPTURE_KEYBOARD=1 to capture keyboard presentation frames.")
        }

        let focusDelayMS = ProcessInfo.processInfo.environment["DRIFT_CAPTURE_FOCUS_DELAY_MS"]
            .flatMap(Int.init) ?? 350
        let frameCount = ProcessInfo.processInfo.environment["DRIFT_CAPTURE_FRAME_COUNT"]
            .flatMap(Int.init) ?? 72

        let app = launchAppBackedByAppTemp(focusDelayMS: focusDelayMS)
        app.buttons["New Note"].tap()

        for index in 0..<frameCount {
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = String(format: "keyboard-%02d", index)
            shot.lifetime = .keepAlways
            add(shot)
            Thread.sleep(forTimeInterval: 1.0 / 30.0)
        }

        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 3))
    }
}

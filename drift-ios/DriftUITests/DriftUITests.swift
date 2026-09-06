import XCTest

@MainActor
final class DriftUITests: XCTestCase {
    private var tempFolder: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        tempFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("drift-ui-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempFolder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempFolder)
    }

    @discardableResult
    private func seed(title: String, body: String = "") throws -> URL {
        let url = tempFolder.appendingPathComponent("\(title).md")
        let text = body.isEmpty ? title : "\(title)\n\n\(body)"
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["DRIFT_TEST_FOLDER"] = tempFolder.path
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        waitFor("Each test should begin with the app settled in portrait", timeout: 10) {
            let frame = app.frame
            return frame.height > frame.width
        }
        XCTAssertTrue(app.buttons["new-note"].waitForExistence(timeout: 10))
        return app
    }

    private func editor(in app: XCUIApplication) -> XCUIElement {
        // UIKit may expose the noneditable reading view with a different type.
        let editor = app.descendants(matching: .any).matching(identifier: "note-editor").firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        return editor
    }

    private func noteRow(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.tables["notes-list"].cells["note-row-\(title).md"]
    }

    private func open(_ title: String, in app: XCUIApplication) -> XCUIElement {
        let row = noteRow(title, in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        return editor(in: app)
    }

    private func waitFor(_ description: String, timeout: TimeInterval = 5,
                         file: StaticString = #filePath, line: UInt = #line,
                         condition: @escaping () -> Bool) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in condition() }, object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed,
                       description, file: file, line: line)
    }

    private func back(in app: XCUIApplication) {
        let back = app.buttons["editor-back"]
        XCTAssertTrue(back.waitForExistence(timeout: 3))
        XCTAssertTrue(back.isHittable)
        back.tap()
        XCTAssertTrue(app.tables["notes-list"].waitForExistence(timeout: 5))
    }

    private func edgeBack(in app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.45))
        let finish = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.45))
        start.press(forDuration: 0.05, thenDragTo: finish)
        XCTAssertTrue(app.tables["notes-list"].waitForExistence(timeout: 5))
    }

    private func pullFromTop(_ editor: XCUIElement) {
        let start = editor.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30))
        let finish = editor.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.88))
        start.press(forDuration: 0.05, thenDragTo: finish)
    }

    private func readIndicator(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "read-mode-indicator").firstMatch
    }

    private func waitForText(_ expected: String, at url: URL, timeout: TimeInterval = 5) {
        waitFor("The complete note must reach disk: \(url.lastPathComponent)", timeout: timeout) {
            (try? String(contentsOf: url, encoding: .utf8)) == expected
        }
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testListShowsNotesAndPopulatedNotesOpenWithoutTheKeyboard() throws {
        try seed(title: "Morning pages", body: "A quiet place to put a thought.")
        try seed(title: "Things to make", body: "A small table. A better cup of coffee.")
        let app = launchApp()
        XCTAssertTrue(noteRow("Morning pages", in: app).exists)
        XCTAssertTrue(noteRow("Things to make", in: app).exists)
        attachScreenshot(named: "notes-home")
        let editor = open("Morning pages", in: app)
        XCTAssertEqual(editor.value as? String, "Morning pages\n\nA quiet place to put a thought.")
        XCTAssertTrue(app.buttons["editor-back"].isHittable)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        attachScreenshot(named: "note-at-top")
    }

    func testLargeNotebookOpensAndReopensNotes() throws {
        for index in 0..<1_000 {
            try seed(title: "Earlier thought \(index)", body: String(repeating: "A small observation. ", count: 60))
        }
        let title = "An idea at hand"
        let text = "A note should open when I tap it."
        try seed(title: title, body: text)
        let app = launchApp()
        XCTAssertEqual(open(title, in: app).value as? String, "\(title)\n\n\(text)")
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        attachScreenshot(named: "large-notebook-open")
        back(in: app)
        app.tables["notes-list"].swipeUp()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.025)).tap()
        attachScreenshot(named: "large-notebook-scrolled-to-top")
        // Returning home starts a catalogue refresh. Opening again should not
        // wait for every unrelated note to be coordinated by the file provider.
        XCTAssertEqual(open(title, in: app).value as? String, "\(title)\n\n\(text)")
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        app.terminate()
        let restarted = launchApp()
        XCTAssertTrue(noteRow(title, in: restarted).waitForExistence(timeout: 5))
        XCTAssertEqual(open(title, in: restarted).value as? String, "\(title)\n\n\(text)")
        XCTAssertFalse(restarted.keyboards.firstMatch.exists)
        attachScreenshot(named: "large-notebook-restarted")
    }

    func testCreateFocusTypeBackAndReopenWithoutWaitingForAutosave() throws {
        let app = launchApp()
        app.buttons["new-note"].tap()
        let editor = editor(in: app)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3),
                      "Compose should arrive ready to type without a second tap")
        let text = "A new idea\n\nBuild a place for unhurried thoughts."
        editor.typeText(text)
        // Leaving immediately must flush the last edit, even before debounce.
        back(in: app)
        waitForText(text, at: tempFolder.appendingPathComponent("A new idea.md"))
        XCTAssertEqual(open("A new idea", in: app).value as? String, text)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
    }

    func testExistingEmptyNoteOpensReadyToWrite() throws {
        let url = tempFolder.appendingPathComponent("An empty page.md")
        try "".write(to: url, atomically: true, encoding: .utf8)
        let app = launchApp()
        let editor = open("An empty page", in: app)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        editor.typeText("A page begun")
        back(in: app)
        waitForText("A page begun", at: tempFolder.appendingPathComponent("A page begun.md"))
    }

    func testAbandoningNewEmptyNoteLeavesNoListDebris() throws {
        try seed(title: "Keep this note", body: "The only note in this folder.")
        let app = launchApp()
        app.buttons["new-note"].tap()
        // Return as soon as Compose opens, without waiting for keyboard, typing,
        // autosave, or a later cleanup operation to remove a blank file.
        app.buttons["editor-back"].tap()
        XCTAssertTrue(app.tables["notes-list"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.tables["notes-list"].cells.count, 1)
        XCTAssertTrue(noteRow("Keep this note", in: app).exists)
        let files = try FileManager.default.contentsOfDirectory(at: tempFolder, includingPropertiesForKeys: nil)
        XCTAssertEqual(Set(files.map(\.lastPathComponent)), ["Keep this note.md"],
                       "An untouched composer must leave neither an Untitled file nor a trash entry")
    }

    func testFloatingBackRetreatsWhileScrollingAndEdgeBackStillWorks() throws {
        let paragraphs = (1...45).map {
            "Observation \($0): leave enough room for an idea to become something useful."
        }.joined(separator: "\n\n")
        try seed(title: "Field notes", body: paragraphs)
        let app = launchApp()
        let editor = open("Field notes", in: app)
        let back = app.buttons["editor-back"]
        XCTAssertTrue(back.isHittable)
        editor.swipeUp(velocity: .slow)
        waitFor("The floating Back control should retreat when reading farther down") {
            !back.exists || !back.isHittable
        }
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        attachScreenshot(named: "note-scrolled-controls-retreated")
        // The status-bar gesture returns the long document to its true top and
        // flashes the native indicator for visual review of its upper inset.
        let statusBar = app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.025))
        statusBar.tap()
        XCTAssertTrue(back.isHittable)
        // A second tap waits for the first return gesture to settle, then
        // flashes the indicator at the top without another long scroll.
        statusBar.tap()
        attachScreenshot(named: "long-note-scrollbar-at-top")
        editor.swipeUp(velocity: .slow)
        waitFor("Back should retreat again before exercising the deep-note edge gesture") {
            !back.exists || !back.isHittable
        }
        edgeBack(in: app)
        XCTAssertFalse(editor.exists)
        XCTAssertTrue(noteRow("Field notes", in: app).exists)
    }

    func testShortNoteCanMoveUpAndItsBackControlReturnsAtTheTop() throws {
        try seed(title: "One thought", body: "Leave room around a thought.")
        let app = launchApp()
        let editor = open("One thought", in: app)
        let back = app.buttons["editor-back"]
        editor.swipeUp(velocity: .slow)
        waitFor("Short notes should retain enough space below the text to scroll upward") {
            !back.exists || !back.isHittable
        }
        editor.swipeDown(velocity: .slow)
        waitFor("Returning to the top should restore the floating Back control") {
            back.isHittable
        }
        attachScreenshot(named: "short-note-returned-to-top")
        self.back(in: app)
    }

    func testCancelledEdgeBackLeavesTheNoteEditableAndAllowsAnotherBackGesture() throws {
        let title = "A thought to stay with"
        let body = (1...24).map {
            "Observation \($0): the page should stay responsive when a gesture changes direction."
        }.joined(separator: "\n\n")
        let url = try seed(title: title, body: body)
        let app = launchApp()
        let editor = open(title, in: app)
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.45))
        let shortFinish = app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.45))

        // A slow, short movement followed by a hold cancels the transition;
        // releasing with flick velocity could legitimately finish navigation.
        start.press(forDuration: 0.05, thenDragTo: shortFinish,
                    withVelocity: .slow, thenHoldForDuration: 0.3)

        XCTAssertTrue(editor.exists)
        XCTAssertFalse(app.tables["notes-list"].exists)
        XCTAssertEqual(editor.value as? String, title + "\n\n" + body)
        attachScreenshot(named: "note-after-cancelled-edge-back")
        editor.swipeUp(velocity: .slow)
        let back = app.buttons["editor-back"]
        waitFor("The page must still scroll after cancelling its back transition") {
            !back.exists || !back.isHittable
        }
        editor.tap()
        let marker = " Keep this addition."
        editor.typeText(marker)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        let editedText = try XCTUnwrap(editor.value as? String)
        XCTAssertTrue(editedText.contains(marker))

        edgeBack(in: app)

        waitForText(editedText, at: url)
        XCTAssertEqual(open(title, in: app).value as? String, editedText)
    }

    func testPullToReadPreventsEditingAndExitDoesNotForceTheKeyboard() throws {
        let text = "Saturday, slowly\n\nCoffee by the window. A walk with no particular destination.\n\nGood work starts with noticing."
        let url = tempFolder.appendingPathComponent("Saturday, slowly.md")
        try text.write(to: url, atomically: true, encoding: .utf8)
        let app = launchApp()
        var editor = open("Saturday, slowly", in: app)
        let lock = readIndicator(in: app)
        // A small pull must not cross the deliberate 78-point trigger.
        let start = editor.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 30)))
        XCTAssertFalse(lock.exists)
        pullFromTop(editor)
        XCTAssertTrue(lock.waitForExistence(timeout: 3))
        editor = self.editor(in: app)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        attachScreenshot(named: "note-read-mode")
        let textPoint = editor.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.22))
        textPoint.tap()
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        textPoint.press(forDuration: 1.1)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        XCTAssertEqual(app.menuItems.count, 0, "Read Mode must not show text-selection callouts")
        XCTAssertFalse(app.buttons["Copy"].exists)
        XCTAssertFalse(app.buttons["Select All"].exists)
        XCTAssertEqual(editor.value as? String, text)
        pullFromTop(editor)
        waitFor("A second deliberate pull should leave Read Mode") { !lock.exists }
        XCTAssertFalse(app.keyboards.firstMatch.exists,
                       "Leaving Read Mode should allow editing without forcing the keyboard open")
        editor = self.editor(in: app)
        XCTAssertEqual(editor.value as? String, text)
        waitForText(text, at: url)
        textPoint.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3),
                      "The same text should become editable again after leaving Read Mode")
    }

    func testSearchCancelReplacesComposeAndRestoresTheUnfilteredList() throws {
        try seed(title: "Morning pages", body: "Coffee and a quiet thought.")
        try seed(title: "Evening pages", body: "A thought before sleep.")
        let app = launchApp()
        let compose = app.buttons["new-note"]
        let cancel = app.buttons["search-cancel"]
        let search = app.descendants(matching: .any).matching(identifier: "note-search").firstMatch
        search.tap()
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        XCTAssertTrue(cancel.isHittable)
        XCTAssertFalse(compose.exists && compose.isHittable)
        search.typeText("Coffee")
        XCTAssertTrue(noteRow("Morning pages", in: app).waitForExistence(timeout: 3))
        waitFor("Search should show only matching notes") {
            !self.noteRow("Evening pages", in: app).exists
        }
        attachScreenshot(named: "notes-search")
        cancel.tap()
        waitFor("Cancel must restore Compose") { compose.isHittable }
        XCTAssertFalse(cancel.exists && cancel.isHittable)
        waitFor("Cancel must dismiss the search keyboard") { !app.keyboards.firstMatch.exists }
        XCTAssertTrue(noteRow("Morning pages", in: app).exists)
        XCTAssertTrue(noteRow("Evening pages", in: app).exists)
        // The unfiltered rows verify clearing independently of UIKit's empty
        // text-field accessibility value, which can report the placeholder.
    }

    func testFullBodySearchFindsAndOpensTheMatchingNote() throws {
        let body = String(repeating: "An ordinary observation. ", count: 50)
            + "\nMeet beside the bluebird mural on Saturday."
        try seed(title: "Weekend plans", body: body)
        try seed(title: "Shopping list", body: "Oranges, bread, coffee.")
        let app = launchApp()
        let search = app.descendants(matching: .any).matching(identifier: "note-search").firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap()
        search.typeText("BLUEBIRD")
        let matchingTitle = noteRow("Weekend plans", in: app)
        XCTAssertTrue(matchingTitle.waitForExistence(timeout: 5))
        XCTAssertFalse(noteRow("Shopping list", in: app).exists)
        matchingTitle.tap()
        let editor = editor(in: app)
        XCTAssertEqual(editor.value as? String, "Weekend plans\n\n" + body)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        attachScreenshot(named: "note-search-match")
        edgeBack(in: app)
        XCTAssertTrue(noteRow("Weekend plans", in: app).exists)
        XCTAssertTrue(noteRow("Shopping list", in: app).exists)
        XCTAssertTrue(app.buttons["new-note"].isHittable)
        XCTAssertFalse(app.buttons["search-cancel"].exists && app.buttons["search-cancel"].isHittable)
    }

    func testDraggingDismissesKeyboardWithoutLosingWritingOrEnteringReadMode() throws {
        let app = launchApp()
        app.buttons["new-note"].tap()
        let editor = editor(in: app)
        let text = "At the window\n\nThe rain is finally here."
        editor.typeText(text)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        // Begin on the blank page below the paragraph. Starting beside the
        // insertion point invokes UIKit's caret drag instead of page scrolling.
        let start = editor.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        let finish = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
        start.press(forDuration: 0.05, thenDragTo: finish,
                    withVelocity: .slow, thenHoldForDuration: 0)
        waitFor("Dragging the page should dismiss the keyboard") { !app.keyboards.firstMatch.exists }
        XCTAssertEqual(editor.value as? String, text)
        XCTAssertFalse(readIndicator(in: app).exists,
                       "A drag begun while typing should dismiss the keyboard, not enter Read Mode")
        waitForText(text, at: tempFolder.appendingPathComponent("At the window.md"))
    }

    func testLongNoteRemainsEditableAboveTheKeyboard() throws {
        let paragraphs = (1...65).map {
            "Observation \($0): leave enough room for an idea to become something useful."
        }.joined(separator: "\n\n")
        try seed(title: "Field notes", body: paragraphs + "\n\nThe last observation.")
        let app = launchApp()
        let editor = open("Field notes", in: app)
        for _ in 0..<8 { editor.swipeUp(velocity: .fast) }
        editor.tap()
        let marker = " A little more to remember."
        editor.typeText(marker)
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 3))
        XCTAssertTrue((editor.value as? String)?.contains(marker) == true)
        XCTAssertGreaterThan(editor.frame.height, 100)
        XCTAssertLessThanOrEqual(editor.frame.maxY, keyboard.frame.minY + 2,
                                 "The editor viewport must stop above the keyboard")
        attachScreenshot(named: "long-note-writing-keyboard")
        let editedText = try XCTUnwrap(editor.value as? String)
        edgeBack(in: app)
        waitForText(editedText, at: tempFolder.appendingPathComponent("Field notes.md"))
        XCTAssertEqual(open("Field notes", in: app).value as? String, editedText)
    }

    func testLandscapeKeepsNavigationUsableAndWritingAboveTheKeyboard() throws {
        let title = "A thought with room to become something useful"
        let body = "Let the page turn with the phone.\n\nThere should still be room to write and a clear way home."
        let url = try seed(title: title, body: body)
        let app = launchApp()
        var editor = open(title, in: app)
        XCUIDevice.shared.orientation = .landscapeLeft
        defer {
            XCUIDevice.shared.orientation = .portrait
            waitFor("Restore the app to portrait before the next test", timeout: 10) {
                let frame = app.frame
                return frame.height > frame.width
            }
        }
        waitFor("The note should adopt the phone's landscape orientation") {
            let frame = app.frame
            return frame.width > frame.height
        }
        XCTAssertEqual(editor.value as? String, title + "\n\n" + body)
        XCTAssertTrue(app.buttons["editor-back"].isHittable)
        attachScreenshot(named: "landscape-note-and-floating-back")

        // An actual tap verifies the resting control remains usable beside the
        // screen cutout; screenshot evidence checks its visual clearance.
        back(in: app)
        editor = open(title, in: app)
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78)).tap()
        let marker = " A little more room."
        editor.typeText(marker)
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 3))
        XCTAssertTrue((editor.value as? String)?.contains(marker) == true)
        attachScreenshot(named: "landscape-writing-keyboard")
        // Each live AX frame lookup can take seconds on the simulator. Read
        // each once after UIKit is idle, outside a short predicate deadline,
        // and retain the actual geometry before making clearance assertions.
        let appFrame = app.frame
        let editorFrame = editor.frame
        let keyboardFrame = keyboard.frame
        let geometry = "orientation=\(XCUIDevice.shared.orientation.rawValue)\napp=\(appFrame)\neditor=\(editorFrame)\nkeyboard=\(keyboardFrame)"
        let geometryAttachment = XCTAttachment(string: geometry)
        geometryAttachment.name = "landscape-writing-geometry"
        geometryAttachment.lifetime = .keepAlways
        add(geometryAttachment)
        XCTAssertGreaterThan(appFrame.width, appFrame.height, geometry)
        XCTAssertGreaterThan(editorFrame.height, 80, geometry)
        XCTAssertLessThanOrEqual(editorFrame.maxY, keyboardFrame.minY + 2,
                                 "Landscape writing must remain above the keyboard.\n" + geometry)
        let editedText = try XCTUnwrap(editor.value as? String)
        edgeBack(in: app)
        waitForText(editedText, at: url)
    }

    func testBackgroundAndRelaunchPreserveTheLastEdit() throws {
        let app = launchApp()
        app.buttons["new-note"].tap()
        let editor = editor(in: app)
        let text = "On the way home\n\nRemember the thought before it disappears."
        editor.typeText(text)
        XCUIDevice.shared.press(.home)
        waitForText(text, at: tempFolder.appendingPathComponent("On the way home.md"))
        app.activate()
        let resumed = self.editor(in: app)
        XCTAssertEqual(resumed.value as? String, text)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["new-note"].waitForExistence(timeout: 10))
        XCTAssertEqual(open("On the way home", in: app).value as? String, text)
    }
}

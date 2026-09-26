import XCTest
import UIKit

/// Repeatable routes for an external screen recording, not a smoothness verdict.
/// Run each route with the simulator's system appearance set to light, then dark.
/// Review the recorded transitions and their settling tails per docs/JANK-AUDIT.md;
/// XCTest's idle waits and passing assertions cannot establish frame pacing or feel.
@MainActor
final class JankAuditUITests: XCTestCase {
    private var folder: URL!
    private var app: XCUIApplication!
    private let shortTitle = "Morning pages"
    private let shortText = "Morning pages\n\nCoffee beside the bluebird window.\n\nLeave room for another thought."

    override func setUpWithError() throws {
        continueAfterFailure = false
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("drift-jank-audit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        app?.terminate()
        if let data = try? Data(contentsOf: folder.appendingPathComponent("selection-audit.jsonl")),
           !data.isEmpty {
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            attachment.name = "selection-audit"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        try? FileManager.default.removeItem(at: folder)
    }

    private func launchFixture(selectionAudit: Bool = false) throws {
        let now = Date()
        let longBody = (1...36).map {
            "Observation \($0): the paper stays steady as a longer thought wraps across several lines."
        }.joined(separator: "\n\n")
        let notes = [(shortTitle, shortText), ("Long walk", "Long walk\n\n" + longBody)]
            + (1...16).map { index in
                let title = String(format: "Notebook page %02d", index)
                return (title, title + "\n\nA small observation, a quiet afternoon, and a little room to think.")
            }
        // Enough rows to fill the screen and continue below its lower edge.
        // Stable dates keep the same rows visible in before/after recordings.
        for (index, note) in notes.enumerated() {
            let url = folder.appendingPathComponent(note.0 + ".md")
            try note.1.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.modificationDate: now.addingTimeInterval(-Double(index) * 60)],
                ofItemAtPath: url.path)
        }
        app = XCUIApplication()
        app.launchEnvironment["DRIFT_TEST_FOLDER"] = folder.path
        if selectionAudit {
            app.launchEnvironment["DRIFT_SELECTION_AUDIT_LOG"] = folder.appendingPathComponent("selection-audit.jsonl").path
        }
        app.launchArguments = ["-drift.onLaunch", "notesList"]
        app.launch()
        XCTAssertTrue(app.buttons["new-note"].waitForExistence(timeout: 10))
        XCTAssertTrue(row(shortTitle).waitForExistence(timeout: 5))
    }

    private func row(_ title: String) -> XCUIElement {
        app.tables["notes-list"].cells["note-row-\(title).md"]
    }

    private func editor() -> XCUIElement {
        let result = app.descendants(matching: .any).matching(identifier: "note-editor").firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        return result
    }

    private func back() {
        let button = app.buttons["editor-back"]
        XCTAssertTrue(button.waitForExistence(timeout: 3))
        button.tap()
        XCTAssertTrue(app.tables["notes-list"].waitForExistence(timeout: 5))
    }

    private func waitFor(_ message: String, timeout: TimeInterval = 5,
                         condition: @escaping () -> Bool) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in condition() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed, message)
    }

    private func requireTypingKeyboard() {
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 3),
                      "The editor must be ready to type without another focus tap")
        // A fresh simulator can expose its slide-to-type introduction as a
        // keyboard. Dismiss that system overlay and record that it occurred;
        // keyboard existence alone does not prove that native keys are ready.
        let introduction = app.buttons["Continue"]
        if introduction.exists && introduction.isHittable {
            XCTContext.runActivity(named: "Dismiss one-time system keyboard introduction") { _ in
                introduction.tap()
            }
        }
        waitFor("The native typing keys must be visible and usable") {
            // UIKit's first accessibility key can be a noninteractive system
            // element. Check a visible letter on either Shift state instead.
            keyboard.keys.matching(NSPredicate(format: "label IN %@", ["q", "Q"]))
                .allElementsBoundByIndex.contains(where: \.isHittable)
        }
    }

    private func notebookContents() throws -> [String: String] {
        let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        return try Dictionary(uniqueKeysWithValues: urls.filter { $0.pathExtension == "md" }.map {
            ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8))
        })
    }

    private func recordingTail(_ name: String) {
        // Intentionally keep a second of the settled state in the recording so
        // late color, suggestion-bar, row, or caret changes cannot be missed.
        // This dwell happens after the action; it is not an app latency metric.
        Thread.sleep(forTimeInterval: 1.1)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private struct SelectionAuditEvent: Decodable {
        let offset: Double
        let activeGesture: Bool
        let location: Int
        let length: Int
        let viewportHeight: Double?
        let contentHeight: Double?
        let textContentHeight: Double?
        let bottomInset: Double?
    }

    private func selectionEvents(in data: Data) throws -> [SelectionAuditEvent] {
        try data.split(separator: 0x0A).map {
            try JSONDecoder().decode(SelectionAuditEvent.self, from: Data($0))
        }
    }

    private func tapEditMenuAction(_ title: String) {
        let item = app.menuItems[title].firstMatch
        let button = app.buttons[title].firstMatch
        waitFor("The native \(title) action must be available") {
            (item.exists && item.isHittable) || (button.exists && button.isHittable)
        }
        if item.exists && item.isHittable { item.tap() }
        else { button.tap() }
    }

    private func longPressKeepsPaperSteady(_ page: XCUIElement, at fraction: Double,
                                         name: String) throws {
        let log = folder.appendingPathComponent("selection-audit.jsonl")
        let before = try Data(contentsOf: log)
        let initial = try XCTUnwrap(try selectionEvents(in: before).last)
        let originalText = try XCTUnwrap(page.value as? String)
        // A short hold misses the reported failure: UIKit's loupe appeared
        // first, then native autoscroll accelerated all the way to blank paper.
        page.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: fraction)).press(forDuration: 3.2)
        recordingTail(name)
        let data = Data(try Data(contentsOf: log).dropFirst(before.count))
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = name + "-events"
        attachment.lifetime = .keepAlways
        add(attachment)
        let events = try selectionEvents(in: data)
        XCTAssertTrue(events.contains(where: \.activeGesture),
                      "Exercise a real active native gesture, not just an idle editor")
        let movement = events.map { abs($0.offset - initial.offset) }.max() ?? 0
        XCTAssertLessThanOrEqual(movement, 2,
                                 "Holding still inside the editor must not scroll the paper")
        XCTAssertEqual(page.value as? String, originalText,
                       "Beginning selection must preserve every character")
    }

    func testFocusedLongPressKeepsPaperSteadyRecording() throws {
        try launchFixture(selectionAudit: true)
        let originalContents = try notebookContents()
        for fraction in [0.32, 0.60, 0.80] {
            // Reopening resets the viewport so every hold starts on text,
            // even if a previous position accidentally scrolled to the end.
            row("Long walk").tap()
            let page = editor()
            page.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.25)).tap()
            requireTypingKeyboard()
            recordingTail("focused-before-long-press-\(fraction)")
            try longPressKeepsPaperSteady(page, at: fraction, name: "focused-long-press-\(fraction)")
            back()
        }
        XCTAssertEqual(try notebookContents(), originalContents)
    }

    func testReadingLongPressKeepsPaperSteadyRecording() throws {
        try launchFixture(selectionAudit: true)
        row("Long walk").tap()
        let page = editor()
        page.swipeUp(velocity: .slow)
        page.swipeUp(velocity: .slow)
        recordingTail("reading-before-long-press")
        XCTAssertFalse(app.keyboards.firstMatch.exists,
                       "This route must begin without a keyboard and with the old caret offscreen")
        try longPressKeepsPaperSteady(page, at: 0.32, name: "reading-long-press")
        requireTypingKeyboard()
    }

    func testNativeCopySurvivesSelectionScrollAndPastesExactTextRecording() throws {
        try launchFixture(selectionAudit: true)
        let originalContents = try notebookContents()
        row("Long walk").tap()
        let page = editor()
        page.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.25)).tap()
        requireTypingKeyboard()
        let originalText = try XCTUnwrap(page.value as? String)
        let log = folder.appendingPathComponent("selection-audit.jsonl")
        func currentSelection() -> SelectionAuditEvent? {
            guard let data = try? Data(contentsOf: log) else { return nil }
            return try? selectionEvents(in: data).last
        }

        // Select a word through UIKit, not by injecting a selected range or
        // writing the clipboard from the test runner.
        page.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.45)).doubleTap()
        waitFor("Double-tapping body text must form a native selection") {
            (currentSelection()?.length ?? 0) > 0
        }
        let selection = try XCTUnwrap(currentSelection())
        let range = NSRange(location: selection.location, length: selection.length)
        XCTAssertLessThanOrEqual(NSMaxRange(range), (originalText as NSString).length)
        let expectedCopy = (originalText as NSString).substring(with: range)
        XCTAssertFalse(expectedCopy.isEmpty)
        recordingTail("native-word-selection")
        tapEditMenuAction("Copy")

        // The margin belongs to the scroll view, away from the text and its
        // selection handles. Keep the selection while moving its viewport.
        let margin = page.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.76))
        margin.press(forDuration: 0.05,
                     thenDragTo: page.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.30)),
                     withVelocity: .slow, thenHoldForDuration: 0)
        waitFor("Scrolling must move the selected note") {
            (currentSelection()?.offset ?? selection.offset) > selection.offset + 40
        }
        let afterScroll = try XCTUnwrap(currentSelection())
        XCTAssertEqual(afterScroll.location, selection.location)
        XCTAssertEqual(afterScroll.length, selection.length)
        XCTAssertEqual(page.value as? String, originalText)
        recordingTail("native-selection-after-scroll")

        // Use the native edge-back route because the retreating Back control
        // is deliberately offscreen once the paper has scrolled.
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
        edge.press(forDuration: 0.05,
                   thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
        XCTAssertTrue(app.tables["notes-list"].waitForExistence(timeout: 5))
        XCTAssertEqual(try notebookContents(), originalContents)
        app.buttons["new-note"].tap()
        let composer = editor()
        requireTypingKeyboard()
        composer.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.25)).press(forDuration: 1.1)
        tapEditMenuAction("Paste")
        XCTAssertEqual(composer.value as? String, expectedCopy,
                       "Native Copy and Paste must preserve the exact selected substring")
        recordingTail("native-copy-pasted-into-disposable-note")
    }

    func testNativeSelectAllCopiesWholeNoteRecording() throws {
        try launchFixture(selectionAudit: true)
        let originalContents = try notebookContents()
        row("Long walk").tap()
        let page = editor()
        let originalText = try XCTUnwrap(page.value as? String)
        let log = folder.appendingPathComponent("selection-audit.jsonl")
        page.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.25)).tap()
        requireTypingKeyboard()
        let caret = page.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.45))
        caret.tap()
        // A long press can restore its original insertion point on release.
        // Place this caret explicitly, then make a separate same-caret tap.
        recordingTail("native-caret-placed")
        let placedCaret = try XCTUnwrap(try selectionEvents(in: Data(contentsOf: log)).last)
        XCTAssertEqual(placedCaret.length, 0)
        caret.tap()
        recordingTail("native-caret-menu-with-select-all")
        XCTAssertEqual(try selectionEvents(in: Data(contentsOf: log)).last?.location, placedCaret.location)
        tapEditMenuAction("Select All")
        waitFor("Native Select All must cover the complete note") {
            guard let data = try? Data(contentsOf: log),
                  let selection = try? self.selectionEvents(in: data).last else { return false }
            return selection.location == 0 && selection.length == (originalText as NSString).length
        }
        let selection = XCTAttachment(data: try Data(contentsOf: log), uniformTypeIdentifier: "public.json")
        selection.name = "native-select-all-range"
        selection.lifetime = .keepAlways
        add(selection)
        tapEditMenuAction("Copy")
        XCTAssertEqual(page.value as? String, originalText)
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
        edge.press(forDuration: 0.05,
                   thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
        XCTAssertTrue(app.tables["notes-list"].waitForExistence(timeout: 5))
        XCTAssertEqual(try notebookContents(), originalContents)
        app.buttons["new-note"].tap()
        let composer = editor()
        requireTypingKeyboard()
        composer.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.25)).press(forDuration: 1.1)
        tapEditMenuAction("Paste")
        XCTAssertEqual(composer.value as? String, originalText,
                       "Copying the entire native selection must preserve every character and newline")
        recordingTail("native-whole-note-pasted")
    }

    func testKeyboardScrollEndKeepsLastLineOnPaperRecording() throws {
        let attempts = 3
        try launchFixture(selectionAudit: true)
        let originalContents = try notebookContents()
        let log = folder.appendingPathComponent("selection-audit.jsonl")
        func latestEvent() -> SelectionAuditEvent? {
            guard let data = try? Data(contentsOf: log) else { return nil }
            return try? selectionEvents(in: data).last
        }
        func scrollToEnd(_ page: XCUIElement) throws {
            for _ in 0..<10 {
                let before = latestEvent()?.offset ?? 0
                // Stay inside the paper: the far-right scroll indicator owns
                // its own drag direction when visible after keyboard dismissal.
                let start = page.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.80))
                start.press(forDuration: 0.05,
                            thenDragTo: page.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.15)),
                            withVelocity: .fast, thenHoldForDuration: 0)
                let after = try XCTUnwrap(latestEvent()).offset
                if abs(after - before) < 1 { return }
            }
            XCTFail("The synthetic note must reach its scroll limit within ten swipes")
        }
        func capture(_ page: XCUIElement, _ name: String) throws {
            recordingTail(name)
            let snapshot = try XCTUnwrap(latestEvent())
            let height = try XCTUnwrap(snapshot.viewportHeight)
            let contentHeight = try XCTUnwrap(snapshot.contentHeight)
            let textHeight = try XCTUnwrap(snapshot.textContentHeight)
            let bottom = try XCTUnwrap(snapshot.bottomInset)
            XCTAssertEqual(height, page.frame.height, accuracy: 1)
            XCTAssertEqual(snapshot.offset, max(0, contentHeight - height), accuracy: 1,
                           "Exercise the actual scroll limit, not an arbitrary point in the note")
            let endY = textHeight - bottom - snapshot.offset
            let geometry = XCTAttachment(string: "viewportHeight=\(height)\noffset=\(snapshot.offset)\ntextContentHeight=\(textHeight)\nbottomInset=\(bottom)\nvisibleTextBottom=\(endY)\n")
            geometry.name = name + "-geometry"
            geometry.lifetime = .keepAlways
            add(geometry)
            XCTAssertGreaterThanOrEqual(endY, 40,
                                        "Scrolling to the end must leave the last line on the paper above the keyboard")
            XCTAssertLessThan(endY, height * 0.5,
                              "Keep the intentional space that lets the last line rise into a reading position")
        }
        for title in [shortTitle, "Long walk"] {
            row(title).tap()
            let page = editor()
            XCTAssertFalse(app.keyboards.firstMatch.exists)
            try scrollToEnd(page)
            try capture(page, title + "-reading-end")
            for attempt in 1...attempts {
                // The final line is near the top; tapping the paper just below
                // it places the native caret at the document end.
                page.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.15)).tap()
                requireTypingKeyboard()
                try scrollToEnd(page)
                try capture(page, title + "-writing-end-\(attempt)")
                if title == "Long walk" && attempt == 1 {
                    let before = try Data(contentsOf: log).count
                    let originalHeight = page.frame.height
                    // Pull only partway into the keyboard and pause. UIKit
                    // completes dismissal on release; intermediate viewport
                    // sizes must still preserve the scroll limit.
                    let start = page.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.98))
                    start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 55)),
                                withVelocity: .slow, thenHoldForDuration: 0.3)
                    waitFor("A partial keyboard drag must complete its native dismissal") {
                        !self.app.keyboards.firstMatch.exists
                    }
                    let data = Data(try Data(contentsOf: log).dropFirst(before))
                    let heights = try selectionEvents(in: data).compactMap(\.viewportHeight)
                    XCTAssertTrue(heights.contains { $0 > Double(originalHeight) + 20 && $0 < page.frame.height - 20 },
                                  "Exercise an intermediate viewport while the native keyboard is being dragged")
                    let gesture = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                    gesture.name = "partial-keyboard-dismissal-events"
                    gesture.lifetime = .keepAlways
                    add(gesture)
                    XCTAssertFalse(app.descendants(matching: .any)
                        .matching(identifier: "read-mode-indicator").firstMatch.exists)
                    recordingTail("partial-keyboard-dismissal-completed")
                    page.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.15)).tap()
                    requireTypingKeyboard()
                    try scrollToEnd(page)
                    try capture(page, "long-note-end-after-partial-dismissal")
                }
                if attempt < attempts {
                    let start = page.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.85))
                    start.press(forDuration: 0.05,
                                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.98)),
                                withVelocity: .slow, thenHoldForDuration: 0)
                    waitFor("Dragging the paper must dismiss the keyboard") { !self.app.keyboards.firstMatch.exists }
                    XCTAssertFalse(app.descendants(matching: .any)
                        .matching(identifier: "read-mode-indicator").firstMatch.exists,
                                   "A keyboard dismissal must not also enter Read Mode")
                    try scrollToEnd(page)
                    try capture(page, title + "-dismissed-end-\(attempt)")
                }
            }
            let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
            edge.press(forDuration: 0.05,
                       thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
            XCTAssertTrue(app.tables["notes-list"].waitForExistence(timeout: 5))
        }
        XCTAssertEqual(try notebookContents(), originalContents)
    }

    func testRepeatedBlankComposeAndReturnRecording() throws {
        try launchFixture()
        let originalContents = try notebookContents()
        recordingTail("initial-full-height-list")

        for attempt in 1...3 {
            XCTContext.runActivity(named: "Compose and return \(attempt)") { _ in
                app.buttons["new-note"].tap()
                let page = editor()
                requireTypingKeyboard()
                XCTAssertEqual(page.value as? String, "")
                recordingTail("compose-\(attempt)")
                back()
                XCTAssertTrue(app.buttons["new-note"].isHittable)
                recordingTail("returned-list-\(attempt)")
            }
            XCTAssertEqual(try notebookContents(), originalContents,
                           "Abandoning an empty composer must not create debris or alter existing notes")
        }
    }

    func testNewlinesKeepShortPageSteadyRecording() throws {
        try launchFixture()
        for attempt in 1...3 {
            app.buttons["new-note"].tap()
            let page = editor()
            requireTypingKeyboard()
            let title = "Return check \(attempt)"
            page.typeText(title)
            recordingTail("title-before-return-\(attempt)")
            page.typeText("\n")
            recordingTail("title-return-\(attempt)")
            XCTAssertTrue(app.buttons["editor-back"].isHittable,
                          "A newline that fits must not scroll the title and Back offscreen")
            page.typeText("A first body line.\n\nA second line.")
            recordingTail("body-and-blank-returns-\(attempt)")
            XCTAssertTrue(app.buttons["editor-back"].isHittable)
            // Reverse the newline immediately, then type through the next one.
            page.typeText("\n\u{8}\nStill writing.")
            let expected = title + "\nA first body line.\n\nA second line.\nStill writing."
            XCTAssertEqual(page.value as? String, expected)
            recordingTail("reversed-return-and-immediate-typing-\(attempt)")
            XCTAssertTrue(app.buttons["editor-back"].isHittable)
            back()
            row(title).tap()
            XCTAssertEqual(editor().value as? String, expected)
            recordingTail("saved-page-reopened-\(attempt)")
            back()
        }
    }

    func testSearchCancelledBackAndKeyboardDismissalRecording() throws {
        try launchFixture()
        let originalContents = try notebookContents()
        let search = app.descendants(matching: .any).matching(identifier: "note-search").firstMatch
        search.tap()
        requireTypingKeyboard()
        search.typeText("bluebird")
        XCTAssertTrue(row(shortTitle).waitForExistence(timeout: 5))
        waitFor("Search must filter unrelated notes") { !self.row("Long walk").exists }
        recordingTail("search-keyboard")

        row(shortTitle).tap()
        let page = editor()
        XCTAssertEqual(page.value as? String, shortText)
        waitFor("Opening a populated search result must dismiss the search keyboard") {
            !self.app.keyboards.firstMatch.exists
        }
        recordingTail("search-to-populated-editor")

        page.tap()
        requireTypingKeyboard()
        // The first focus tap can leave UIKit's initial insertion position at
        // the title. Once editing, explicitly tap the blank space below this
        // short document to put the caret at its end before cancelling Back.
        page.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.80)).tap()
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.45))
        let partial = app.coordinate(withNormalizedOffset: CGVector(dx: 0.30, dy: 0.45))
        // A slow short pull and hold cancels; flick velocity may validly pop.
        edge.press(forDuration: 0.05, thenDragTo: partial,
                   withVelocity: .slow, thenHoldForDuration: 0.3)
        XCTAssertTrue(page.exists)
        XCTAssertFalse(app.tables["notes-list"].exists)
        XCTAssertEqual(page.value as? String, shortText)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        recordingTail("cancelled-back-while-writing")

        let marker = " A fresh line of thought."
        page.typeText(marker)
        let editedText = try XCTUnwrap(page.value as? String)
        XCTAssertEqual(editedText, shortText + marker,
                       "Cancelling navigation must preserve the chosen caret and every character of the note")
        // Start below the text so UIKit scrolls rather than dragging the caret.
        let dragStart = page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        let dragEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
        dragStart.press(forDuration: 0.05, thenDragTo: dragEnd,
                        withVelocity: .slow, thenHoldForDuration: 0)
        waitFor("Dragging the page must dismiss the keyboard") { !self.app.keyboards.firstMatch.exists }
        XCTAssertEqual(page.value as? String, editedText)
        XCTAssertFalse(app.descendants(matching: .any)
            .matching(identifier: "read-mode-indicator").firstMatch.exists,
                       "A keyboard dismissal must not also enter Read Mode")
        recordingTail("interactive-keyboard-dismissal")

        back()
        waitFor("Returning from search must restore the unfiltered list") { self.row("Long walk").exists }
        var expectedContents = originalContents
        expectedContents[shortTitle + ".md"] = editedText
        waitFor("Only the intended edit must reach disk") { (try? self.notebookContents()) == expectedContents }
        row(shortTitle).tap()
        XCTAssertEqual(editor().value as? String, editedText)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        recordingTail("reopened-written-note")
        back()
        recordingTail("final-full-height-list")
    }

    func testReduceMotionRepeatedComposeAndReturnRecording() throws {
        // Exercise the real accessibility preference, rather than a launch
        // flag that would only test our interpretation of the system setting.
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        let reduceMotion = settings.switches["Reduce Motion"]
        if !reduceMotion.exists {
            // Settings may restore a previously visited subpage. Return to its
            // root before finding Accessibility in the ordinary settings list.
            for _ in 0..<5 {
                if settings.navigationBars["Settings"].exists { break }
                let backButton = settings.navigationBars.buttons.firstMatch
                if !backButton.exists { break }
                backButton.tap()
            }
            let accessibility = settings.staticTexts["Accessibility"].firstMatch
            for _ in 0..<6 {
                if accessibility.exists && accessibility.isHittable { break }
                settings.swipeUp()
            }
            XCTAssertTrue(accessibility.exists && accessibility.isHittable,
                          "The real system Accessibility settings must be reachable")
            accessibility.tap()
            let motion = settings.staticTexts["Motion"].firstMatch
            XCTAssertTrue(motion.waitForExistence(timeout: 5))
            motion.tap()
        }
        XCTAssertTrue(reduceMotion.waitForExistence(timeout: 5))
        let originalValue = try XCTUnwrap(reduceMotion.value as? String)
        XCTAssertTrue(["0", "1"].contains(originalValue), "The system switch must expose a known state")

        // XCTest runs teardown blocks even if a route assertion fails. Register
        // restoration before mutation so later audits retain their own setting.
        addTeardownBlock {
            settings.activate()
            XCTAssertTrue(reduceMotion.waitForExistence(timeout: 5))
            if reduceMotion.value as? String != originalValue {
                reduceMotion.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            }
            let restored = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in (reduceMotion.value as? String) == originalValue },
                object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed,
                           "Restore the simulator's original Reduce Motion setting")
            settings.terminate()
        }
        // Settings exposes the entire row as the switch's accessibility frame;
        // hit the visible toggle at its trailing edge, not the row's label.
        if originalValue == "0" {
            reduceMotion.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
        waitFor("System Reduce Motion must actually be enabled") { reduceMotion.value as? String == "1" }
        recordingTail("system-reduce-motion-enabled")

        try launchFixture()
        let originalContents = try notebookContents()
        recordingTail("reduce-motion-initial-list")
        for attempt in 1...3 {
            XCTContext.runActivity(named: "Reduce Motion compose and return \(attempt)") { _ in
                app.buttons["new-note"].tap()
                XCTAssertEqual(editor().value as? String, "")
                requireTypingKeyboard()
                recordingTail("reduce-motion-compose-\(attempt)")
                back()
                XCTAssertTrue(app.buttons["new-note"].isHittable)
                recordingTail("reduce-motion-return-\(attempt)")
            }
            XCTAssertEqual(try notebookContents(), originalContents,
                           "Reduced motion must preserve empty-draft cleanup and every existing note")
        }
    }

    func testDeepSearchKeyboardReturnAndReentryRecording() throws {
        let now = Date()
        for index in 1...28 {
            let title = String(format: "Search page %02d", index)
            let url = folder.appendingPathComponent(title + ".md")
            try (title + "\n\nAn orchard observation for a quiet afternoon.")
                .write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.modificationDate: now.addingTimeInterval(-Double(index) * 60)],
                ofItemAtPath: url.path)
        }
        try launchFixture()
        let originalContents = try notebookContents()
        let table = app.tables["notes-list"]
        let search = app.descendants(matching: .any).matching(identifier: "note-search").firstMatch
        search.tap()
        requireTypingKeyboard()
        search.typeText("orchard")
        waitFor("Search must contain the matching catalogue without unrelated notes") {
            table.cells.count == 28 && !self.row(self.shortTitle).exists
        }

        let anchor = row("Search page 26")
        func captureGeometry(_ stage: String) {
            let keyboard = app.keyboards.firstMatch
            let anchorFrame = anchor.frame
            let tableFrame = table.frame
            // A fixed row's screen Y records any list offset change without
            // adding test-only production instrumentation. Bottom clamping may
            // legitimately move that row as the viewport grows; its timing and
            // continuity still need review in the accompanying recording.
            let attachment = XCTAttachment(string: """
                stage=\(stage)
                anchor=Search page 26.md
                anchorFrame=\(String(describing: anchorFrame))
                anchorYWithinTable=\(anchorFrame.minY - tableFrame.minY)
                anchorHittable=\(anchor.isHittable)
                tableFrame=\(String(describing: tableFrame))
                keyboardFrame=\(keyboard.exists ? String(describing: keyboard.frame) : "absent")
                query=\(search.value as? String ?? "unknown")
                """)
            attachment.name = stage + "-geometry"
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        for attempt in 1...3 {
            let finalResult = row("Search page 28")
            for _ in 0..<12 {
                if finalResult.exists && finalResult.isHittable { break }
                table.swipeUp(velocity: .fast)
            }
            XCTAssertTrue(finalResult.isHittable, "Exercise the bottom of a genuinely scrollable result list")
            requireTypingKeyboard()
            XCTAssertTrue(anchor.isHittable)
            captureGeometry("deep-search-\(attempt)-before-return")
            recordingTail("deep-search-\(attempt)-before-return")

            search.typeText("\n")
            waitFor("Return must dismiss the search keyboard") { !self.app.keyboards.firstMatch.exists }
            XCTAssertEqual(search.value as? String, "orchard", "Return must preserve the search query")
            captureGeometry("deep-search-\(attempt)-keyboard-hidden")
            recordingTail("deep-search-\(attempt)-keyboard-hidden")

            search.tap()
            requireTypingKeyboard()
            XCTAssertEqual(search.value as? String, "orchard")
            XCTAssertEqual(table.cells.count, 28)
            captureGeometry("deep-search-\(attempt)-reentered")
            recordingTail("deep-search-\(attempt)-reentered")
        }
        app.buttons["search-cancel"].tap()
        waitFor("Cancel must dismiss the keyboard and restore Compose") {
            !self.app.keyboards.firstMatch.exists && self.app.buttons["new-note"].isHittable
        }
        XCTAssertEqual(try notebookContents(), originalContents,
                       "Searching and repeated keyboard handoffs must not change any note")
        recordingTail("deep-search-final-list")
    }
}

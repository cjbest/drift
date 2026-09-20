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
        try? FileManager.default.removeItem(at: folder)
    }

    private func launchFixture() throws {
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
        return try Dictionary(uniqueKeysWithValues: urls.map {
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

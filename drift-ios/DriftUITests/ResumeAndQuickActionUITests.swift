import XCTest
import UIKit

/// Every scenario has a new disposable notebook and runs on the isolated QA
/// simulator. Short timeouts exercise the real background/foreground events;
/// production retains its five-minute timeout.
@MainActor
final class ResumeAndQuickActionUITests: XCTestCase {
    private var folder: URL!
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("drift-resume-ui-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        app?.terminate()
        try? FileManager.default.removeItem(at: folder)
    }

    @discardableResult
    private func seed(_ title: String, body: String) throws -> URL {
        let url = folder.appendingPathComponent(title + ".md")
        try (title + "\n\n" + body).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func launch(destination: String = "notesList", interval: TimeInterval? = nil,
                        persistSyntheticFolder: Bool = false) {
        app = XCUIApplication()
        app.launchEnvironment["DRIFT_TEST_FOLDER"] = folder.path
        if let interval {
            app.launchEnvironment["DRIFT_TEST_RESUME_INTERVAL"] = String(interval)
        }
        if persistSyntheticFolder {
            app.launchEnvironment["DRIFT_TEST_PERSIST_FOLDER"] = "1"
        }
        // Process-local arguments isolate the preference from other UI tests.
        app.launchArguments = ["-drift.onLaunch", destination]
        app.launch()
        if destination == "newNote" {
            _ = editor()
        } else {
            XCTAssertTrue(app.tables["notes-list"].waitForExistence(timeout: 10))
        }
    }

    private func editor(file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let value = app.descendants(matching: .any).matching(identifier: "note-editor").firstMatch
        XCTAssertTrue(value.waitForExistence(timeout: 8), file: file, line: line)
        return value
    }

    private func row(_ title: String) -> XCUIElement {
        app.tables["notes-list"].cells["note-row-\(title).md"]
    }

    private func open(_ title: String) -> XCUIElement {
        XCTAssertTrue(row(title).waitForExistence(timeout: 5))
        row(title).tap()
        return editor()
    }

    private func back() {
        let button = app.buttons["editor-back"]
        XCTAssertTrue(button.waitForExistence(timeout: 3))
        button.tap()
        XCTAssertTrue(app.tables["notes-list"].waitForExistence(timeout: 5))
    }

    private func waitFor(_ description: String, timeout: TimeInterval = 5,
                         file: StaticString = #filePath, line: UInt = #line,
                         condition: @escaping () -> Bool) {
        let predicate = NSPredicate { _, _ in condition() }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)],
                                     timeout: timeout), .completed, description, file: file, line: line)
    }

    private func waitForText(_ text: String, title: String) {
        let url = folder.appendingPathComponent(title + ".md")
        waitFor("The complete draft must be saved before navigation") {
            (try? String(contentsOf: url, encoding: .utf8)) == text
        }
    }

    private func markdownFiles() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0.hasSuffix(".md") }.sorted()
    }

    private func background(for duration: TimeInterval) {
        XCUIDevice.shared.press(.home)
        waitFor("The app must actually leave the foreground") {
            self.app.state == .runningBackground || self.app.state == .runningBackgroundSuspended
        }
        // The deliberately short fixture timeout keeps this an end-to-end
        // lifecycle test without a five-minute wall-clock delay.
        Thread.sleep(forTimeInterval: duration)
        app.activate()
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testLongBackgroundReturnsToNotesListAndSavesTheDraft() throws {
        launch(interval: 1)
        app.buttons["new-note"].tap()
        let text = "A thought before leaving\n\nKeep every word when returning to the list."
        editor().typeText(text)

        background(for: 1.2)

        XCTAssertTrue(app.tables["notes-list"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "note-editor").firstMatch.exists)
        waitForText(text, title: "A thought before leaving")
        XCTAssertEqual(open("A thought before leaving").value as? String, text)
        XCTAssertEqual(try markdownFiles(), ["A thought before leaving.md"])
        screenshot("resume-list-preserved-draft")
    }

    func testLongBackgroundStartsNewNoteAfterSavingThePreviousDraft() throws {
        launch(destination: "newNote", interval: 1)
        let text = "A draft to keep\n\nA fresh page must leave this one intact."
        editor().typeText(text)

        background(for: 1.2)

        XCTAssertEqual(editor().value as? String, "")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        waitForText(text, title: "A draft to keep")
        XCTAssertEqual(try markdownFiles(), ["A draft to keep.md"])
        screenshot("resume-new-note-preserved-draft")
        // Returning again from an untouched composer must not leave a blank
        // file, nor a second note from a duplicate activation notification.
        background(for: 1.2)
        XCTAssertEqual(editor().value as? String, "")
        XCTAssertEqual(try markdownFiles(), ["A draft to keep.md"])
    }

    func testLongBackgroundOpensLastFromTheListAndRestoresReadMode() throws {
        let title = "A page to return to"
        let body = "A note can wait on the list while its place is remembered."
        try seed(title, body: body)
        launch(destination: "openLast", interval: 1)
        let reading = open(title)
        let start = reading.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30))
        start.press(forDuration: 0.05,
                    thenDragTo: reading.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.88)))
        let indicator = app.descendants(matching: .any).matching(identifier: "read-mode-indicator").firstMatch
        XCTAssertTrue(indicator.waitForExistence(timeout: 3))
        back()

        background(for: 1.2)

        XCTAssertEqual(editor().value as? String, title + "\n\n" + body)
        XCTAssertTrue(indicator.waitForExistence(timeout: 3))
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        screenshot("resume-open-last-read-mode")
    }

    func testBriefBackgroundPreservesTheWritingSessionWithNewNotePreference() throws {
        // No timeout override: a normal quick switch must retain the active
        // editor even when the selected eventual destination is New Note.
        launch(destination: "newNote")
        let text = "Still writing\n\nKeep this sentence in the same editor."
        editor().typeText(text)

        background(for: 0.2)

        XCTAssertEqual(editor().value as? String, text)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        let addition = " And keep its insertion point."
        editor().typeText(addition)
        XCTAssertEqual(editor().value as? String, text + addition)
        back()
        waitForText(text + addition, title: "Still writing")
        XCTAssertEqual(try markdownFiles(), ["Still writing.md"])
    }

    func testBriefBackgroundPreservesTheReadingPlace() throws {
        let title = "A longer page"
        let body = (1...50).map { "Paragraph \($0): keep this exact place when switching away briefly." }
            .joined(separator: "\n\n")
        try seed(title, body: body)
        launch()
        let reading = open(title)
        reading.swipeUp(velocity: .slow)
        let backButton = app.buttons["editor-back"]
        waitFor("The document must be scrolled away from its beginning") {
            !backButton.exists || !backButton.isHittable
        }

        background(for: 0.2)

        XCTAssertEqual(editor().value as? String, title + "\n\n" + body)
        XCTAssertFalse(backButton.exists && backButton.isHittable,
                       "A quick switch must not reopen the document at its beginning")
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        screenshot("brief-resume-keeps-reading-place")
    }

    func testControlCenterInterruptionDoesNotStartANewSession() throws {
        launch(destination: "newNote", interval: 1)
        let text = "A thought through an interruption\n\nControl Center should leave this editor alone."
        editor().typeText(text)
        let topRight = app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.001))
        topRight.press(forDuration: 0.05,
                       thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)))
        // Keep visual evidence of the real system interruption. Some simulator
        // runtimes expose an empty Control Center and stale underlying-app AX
        // nodes, so its optional controls are not a dependable test assertion.
        screenshot("resume-control-center-interruption")
        Thread.sleep(forTimeInterval: 1.2)
        let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.99))
        bottom.press(forDuration: 0.05,
                     thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)))

        XCTAssertEqual(editor().value as? String, text)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        XCTAssertEqual(try markdownFiles(), ["A thought through an interruption.md"])
        screenshot("resume-after-control-center")
    }

    func testHomeScreenNewNoteShortcutWorksWarmAndColdWithoutLosingDrafts() throws {
        try seed("An existing page", body: "The shortcut must open a fresh page instead.")
        // This opt-in simulator-only hook persists a bookmark to this test's
        // UUID folder. A genuine SpringBoard cold launch has no test env vars.
        launch(persistSyntheticFolder: true)
        app.buttons["new-note"].tap()
        let text = "Before using the shortcut\n\nKeep the draft when starting another note."
        editor().typeText(text)

        invokeHomeScreenNewNote()

        XCTAssertEqual(editor().value as? String, "")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        waitForText(text, title: "Before using the shortcut")
        XCTAssertEqual(try markdownFiles(), ["An existing page.md", "Before using the shortcut.md"])
        screenshot("home-screen-new-note-warm")

        app.terminate()
        invokeHomeScreenNewNote()

        XCTAssertEqual(editor().value as? String, "")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        XCTAssertEqual(try markdownFiles(), ["An existing page.md", "Before using the shortcut.md"])
        screenshot("home-screen-new-note-cold")
        back()
        XCTAssertTrue(row("An existing page").exists)
        XCTAssertEqual(open("Before using the shortcut").value as? String, text)
    }

    private func invokeHomeScreenNewNote() {
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let icon = springboard.icons["Drift"].firstMatch
        // The dedicated test simulator can put a newly installed app on the
        // second home page. Stay in the Home Screen rather than using a URL or
        // another entry point that would bypass the shortcut delegate.
        for _ in 0..<4 {
            if icon.exists && icon.isHittable { break }
            springboard.swipeLeft()
        }
        XCTAssertTrue(icon.waitForExistence(timeout: 5))
        XCTAssertTrue(icon.isHittable)
        icon.press(forDuration: 1.2)
        let newNote = springboard.buttons["New Note"]
        XCTAssertTrue(newNote.waitForExistence(timeout: 5))
        screenshot("home-screen-new-note-menu")
        newNote.tap()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }
}

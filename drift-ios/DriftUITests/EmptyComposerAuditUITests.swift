import XCTest

/// Functional guards around a retained motion recording; review every Back and
/// its settling tail to assess row continuity, not only these final assertions.
@MainActor
final class EmptyComposerAuditUITests: XCTestCase {
    private var folder: URL!
    private var app: XCUIApplication!
    private var original: [String: String] = [:]

    override func setUpWithError() throws {
        continueAfterFailure = false
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("empty-composer-audit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for index in 1...18 {
            let title = String(format: "Notebook page %02d", index)
            let text = title + "\n\nA quiet afternoon and a little room to think."
            let url = folder.appendingPathComponent(title + ".md")
            try text.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1780000000 - Double(index)*60)], ofItemAtPath: url.path)
            original[url.lastPathComponent] = text
        }
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchEnvironment["DRIFT_TEST_FOLDER"] = folder.path
        app.launchArguments = ["-drift.onLaunch", "notesList"]
        app.launch()
        XCTAssertTrue(app.buttons["new-note"].waitForExistence(timeout: 10))
        tail("initial-list")
    }

    override func tearDownWithError() throws {
        app?.terminate()
        try? FileManager.default.removeItem(at: folder)
    }

    private func tail(_ name: String) {
        Thread.sleep(forTimeInterval: 1.1)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertFalse(app.buttons["Couldn’t save. Tap to retry."].exists)
    }

    private func openComposer() -> XCUIElement {
        app.buttons["new-note"].tap()
        let page = app.textViews["note-editor"]
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 3))
        let letters = keyboard.buttons["ABC"]
        if letters.exists && letters.isHittable { letters.tap() }
        XCTAssertTrue(keyboard.keys.matching(NSPredicate(format: "label IN %@", ["q", "Q"]))
            .allElementsBoundByIndex.contains(where: \.isHittable))
        return page
    }

    private func files() throws -> [String: String] {
        let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        return try Dictionary(uniqueKeysWithValues: urls.filter { $0.pathExtension == "md" }.map {
            ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8))
        })
    }

    func testTypeDeleteAndReturnThreeTimesRecording() throws {
        for cycle in 1...3 {
            let page = openComposer()
            page.typeText("x")
            XCTAssertEqual((page.value as? String)?.lowercased(), "x")
            tail("typed-\(cycle)")
            XCTAssertEqual(try files().count, original.count + 1, "Exercise an actually materialized composer")
            page.typeText(XCUIKeyboardKey.delete.rawValue)
            XCTAssertEqual(page.value as? String, "")
            // No intentional settling wait between the last deletion and Back.
            // The hosted test separately enforces same-run-loop timing because
            // XCTest's system idling can exceed the app's save debounce here.
            app.buttons["editor-back"].tap()
            XCTAssertTrue(app.tables["notes-list"].waitForExistence(timeout: 3))
            tail("returned-list-\(cycle)")
            XCTAssertEqual(try files(), original)
            XCTAssertEqual(app.tables["notes-list"].cells.count, original.count)
        }
    }

    func testNativeCancelledBackThenContinuedWritingRecording() throws {
        let page = openComposer()
        page.typeText("x")
        tail("before-clear")
        page.typeText(XCUIKeyboardKey.delete.rawValue)
        tail("saved-empty-before-edge")
        // Dismiss the keyboard so the native edge interaction is visible and
        // can be distinguished from a gesture that never began.
        page.swipeDown(velocity: .slow)
        tail("before-native-cancel")
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.42))
        let partial = app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.42))
        start.press(forDuration: 0.05, thenDragTo: partial, withVelocity: .slow, thenHoldForDuration: 0.5)
        XCTAssertTrue(page.exists)
        tail("cancelled-edge-returned-editor")
        page.tap()
        page.typeText("Still here")
        XCTAssertEqual(page.value as? String, "Still here")
        app.buttons["editor-back"].tap()
        tail("resumed-note-preserved")
        let saved = try files()
        XCTAssertEqual(saved.count, original.count + 1)
        XCTAssertEqual(saved["Still here.md"], "Still here")
        for (name, text) in original { XCTAssertEqual(saved[name], text) }
    }
}

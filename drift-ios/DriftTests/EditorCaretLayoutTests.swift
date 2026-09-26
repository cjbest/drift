import XCTest
import UIKit
@testable import Drift

@MainActor
final class EditorCaretLayoutTests: XCTestCase {
    func testPaperExtentDoesNotAccumulateAcrossRelayoutAndWidthChanges() {
        let editor = EditorTextView()
        editor.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        editor.configurePageInsets(top: 117, horizontal: 20, bottom: 58, pageHeight: 844)
        let text = "Field notes\n\n" + String(repeating: "A thought that wraps across the page.\n\n", count: 30)
        editor.loadText(text)
        editor.layoutManager.ensureLayout(for: editor.textContainer)
        editor.layoutIfNeeded()
        let originalSize = editor.contentSize
        for _ in 0..<3 {
            for width in [CGFloat(600), 320, 390] {
                editor.frame.size.width = width
                editor.setNeedsLayout()
                editor.layoutIfNeeded()
                editor.layoutManager.ensureLayout(for: editor.textContainer)
                editor.layoutIfNeeded()
            }
            XCTAssertEqual(editor.contentSize.height, originalSize.height, accuracy: 1,
                           "Returning to the same page width must not add another page of paper")
        }
        XCTAssertEqual(editor.text, text)
    }

    func testReopeningRetainsReadingPositionInPaperAfterLastLine() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("drift-reading-position-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let text = "Field notes\n\n" + (1...36).map {
            "Observation \($0): leave room to read the final paragraph near the top of the page."
        }.joined(separator: "\n\n")
        try text.write(to: folder.appendingPathComponent("Field notes.md"), atomically: true, encoding: .utf8)
        let store = NoteStore(folderURL: folder)
        await store.refresh()
        let snapshot = try await store.openForEditing(XCTUnwrap(store.notes.first))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive }))
        let window = try XCTUnwrap(scene.windows.first(where: \.isKeyWindow))
        let originalRoot = window.rootViewController
        window.endEditing(true)
        let controller = NoteEditorViewController(store: store, snapshot: snapshot)
        window.rootViewController = controller
        defer {
            window.endEditing(true)
            window.rootViewController = originalRoot
            window.layoutIfNeeded()
        }
        window.layoutIfNeeded()
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while controller.view.keyboardLayoutGuide.layoutFrame.height > 1, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        let editor = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? EditorTextView }.first)
        editor.layoutManager.ensureLayout(for: editor.textContainer)
        editor.selectedRange = NSRange(location: (text as NSString).length, length: 0)
        let caret = editor.caretRect(for: try XCTUnwrap(editor.selectedTextRange?.end))
        let readingOffset = caret.minY - 140
        editor.setContentOffset(CGPoint(x: 0, y: readingOffset), animated: false)
        await drainMainQueue()
        XCTAssertGreaterThan(readingOffset, caret.maxY - editor.bounds.height + 100,
                             "The chosen position must use blank paper after the last line")
        controller.viewWillDisappear(false)

        let reopened = NoteEditorViewController(store: store, snapshot: snapshot)
        window.rootViewController = reopened
        window.layoutIfNeeded()
        await drainMainQueue()
        let restored = try XCTUnwrap(reopened.view.subviews.compactMap { $0 as? EditorTextView }.first)
        XCTAssertEqual(restored.contentOffset.y, readingOffset, accuracy: 1,
                       "Reopening must include the paper beyond the text when restoring the viewport")
        XCTAssertEqual(restored.selectedRange, editor.selectedRange)
        XCTAssertEqual(restored.text, text)
        await store.flushCatalogueCache()
    }

    func testCaretMaintenanceDoesNotScrollAwayFromStartOfLongSelection() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive }))
        let window = try XCTUnwrap(scene.windows.first(where: \.isKeyWindow))
        let originalRoot = window.rootViewController
        let controller = UIViewController()
        let editor = EditorTextView()
        editor.translatesAutoresizingMaskIntoConstraints = false
        controller.view.addSubview(editor)
        NSLayoutConstraint.activate([
            editor.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
            editor.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
            editor.topAnchor.constraint(equalTo: controller.view.topAnchor),
            editor.bottomAnchor.constraint(equalTo: controller.view.keyboardLayoutGuide.topAnchor),
        ])
        window.endEditing(true)
        window.rootViewController = controller
        defer {
            window.endEditing(true)
            window.rootViewController = originalRoot
            window.layoutIfNeeded()
        }
        let text = "Field notes\n\n" + (1...45).map {
            "Observation \($0): a quiet paragraph with enough words to wrap across several lines."
        }.joined(separator: "\n\n")
        editor.loadText(text)
        editor.configurePageInsets(top: 140, horizontal: 20, bottom: 24, pageHeight: window.bounds.height)
        window.layoutIfNeeded()
        XCTAssertTrue(editor.becomeFirstResponder())
        try? await Task.sleep(for: .milliseconds(500))
        window.layoutIfNeeded()
        editor.layoutManager.ensureLayout(for: editor.textContainer)
        let start = (text as NSString).range(of: "Observation 14:").location
        let end = (text as NSString).range(of: "Observation 42:").location
        let selection = NSRange(location: start, length: end - start)
        editor.selectedRange = selection
        await drainMainQueue()
        let startPosition = try XCTUnwrap(editor.selectedTextRange?.start)
        let endPosition = try XCTUnwrap(editor.selectedTextRange?.end)
        let startCaret = editor.caretRect(for: startPosition)
        let endCaret = editor.caretRect(for: endPosition)
        let chosenOffset = startCaret.minY - 140
        XCTAssertGreaterThan(endCaret.minY - startCaret.minY, editor.bounds.height * 2,
                             "Exercise a selection spanning several screens")

        for attempt in 0..<3 {
            editor.setContentOffset(CGPoint(x: 0, y: chosenOffset), animated: false)
            editor.keepCaretVisibleAfterLayout()
            await drainMainQueue()
            XCTAssertEqual(editor.contentOffset.y, chosenOffset, accuracy: 1,
                           "Caret maintenance must leave the active selection handle to UIKit (attempt \(attempt))")
            XCTAssertEqual(editor.selectedRange, selection)
        }

        // A queued insertion-point update must also yield if a selection begins
        // before it executes, as it can during a fast drag or Select All.
        editor.selectedRange = NSRange(location: start, length: 0)
        editor.setContentOffset(CGPoint(x: 0, y: chosenOffset), animated: false)
        editor.keepCaretVisibleAfterLayout()
        editor.selectedRange = selection
        await drainMainQueue()
        XCTAssertEqual(editor.contentOffset.y, chosenOffset, accuracy: 1,
                       "Pending caret work must not pull a new selection toward its ordered end")
        XCTAssertEqual(editor.selectedRange, selection)
    }

    func testFirstCaretUpdateKeepsScrolledPageAndCurrentLayoutEngine() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive }))
        let window = try XCTUnwrap(scene.windows.first(where: \.isKeyWindow))
        let originalRoot = window.rootViewController
        let controller = UIViewController()
        let editor = EditorTextView()
        editor.translatesAutoresizingMaskIntoConstraints = false
        controller.view.addSubview(editor)
        NSLayoutConstraint.activate([
            editor.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
            editor.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
            editor.topAnchor.constraint(equalTo: controller.view.topAnchor),
            editor.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor),
        ])
        window.endEditing(true)
        window.rootViewController = controller
        defer {
            window.endEditing(true)
            window.rootViewController = originalRoot
            window.layoutIfNeeded()
        }
        let text = "A long thought\n\n" + (1...40).map {
            "Observation \($0): a quiet paragraph with enough words to wrap and enough room to keep reading."
        }.joined(separator: "\n\n")
        editor.loadText(text)
        editor.configurePageInsets(top: 140, horizontal: 20, bottom: 24, pageHeight: window.bounds.height)
        window.layoutIfNeeded()
        await drainMainQueue()
        XCTAssertNil(editor.textLayoutManager, "The chosen writing engine must be active before focus")
        let layoutManager = editor.layoutManager
        layoutManager.ensureLayout(for: editor.textContainer)
        let location = (text as NSString).range(of: "Observation 14:").location
        XCTAssertNotEqual(location, NSNotFound)
        let selection = NSRange(location: location, length: 0)
        editor.selectedRange = selection
        let caretPosition = try XCTUnwrap(editor.selectedTextRange?.end)
        let caret = editor.caretRect(for: caretPosition)
        editor.setContentOffset(CGPoint(x: 0, y: caret.minY - 140), animated: false)
        XCTAssertGreaterThan(editor.contentOffset.y, 400, "Exercise a page well below its title")
        XCTAssertTrue(editor.becomeFirstResponder())
        let offsetBeforeMaintenance = editor.contentOffset

        editor.keepCaretVisibleAfterLayout()
        await drainMainQueue()

        XCTAssertTrue(editor.layoutManager === layoutManager,
                      "Caret maintenance must preserve the initial layout engine")
        XCTAssertEqual(editor.selectedRange, selection, "Keep the insertion point chosen in the scrolled page")
        XCTAssertEqual(editor.contentOffset.y, offsetBeforeMaintenance.y, accuracy: 1,
                       "A visible caret must not send the page back to its title")

        editor.insertText("Added here. ")
        editor.keepCaretVisibleAfterLayout()
        await drainMainQueue()
        XCTAssertTrue(editor.layoutManager === layoutManager)
        XCTAssertTrue(editor.text.contains("Added here. Observation 14:"),
                      "The next character must go at the chosen middle-document location")
        let typedPosition = try XCTUnwrap(editor.selectedTextRange?.end)
        let typedCaret = editor.caretRect(for: typedPosition)
        XCTAssertGreaterThanOrEqual(typedCaret.minY, editor.bounds.minY)
        XCTAssertLessThanOrEqual(typedCaret.maxY, editor.bounds.maxY - 18)
    }

    func testEditingAtReadingPageEndKeepsChosenViewportThroughKeyboardRiseAndDismissal() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("drift-end-viewport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let text = "Field notes\n\n" + (1...65).map {
            "Observation \($0): leave enough room for an idea to become something useful."
        }.joined(separator: "\n\n") + "\n\nThe last observation."
        try text.write(to: folder.appendingPathComponent("Field notes.md"), atomically: true, encoding: .utf8)
        let store = NoteStore(folderURL: folder)
        await store.refresh()
        let note = try XCTUnwrap(store.notes.first)
        let snapshot = try await store.openForEditing(note)
        let controller = NoteEditorViewController(store: store, snapshot: snapshot)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive }))
        let window = try XCTUnwrap(scene.windows.first(where: \.isKeyWindow))
        let originalRoot = window.rootViewController
        window.endEditing(true)
        window.rootViewController = controller
        defer {
            window.endEditing(true)
            window.rootViewController = originalRoot
            window.layoutIfNeeded()
        }
        window.layoutIfNeeded()
        await drainMainQueue()
        let editor = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? EditorTextView }.first)
        let initialDeadline = ContinuousClock.now.advanced(by: .seconds(3))
        while (controller.view.keyboardLayoutGuide.layoutFrame.height > 1 ||
               abs(editor.bounds.height - controller.view.bounds.height) > 1), ContinuousClock.now < initialDeadline {
            window.layoutIfNeeded()
            controller.view.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertLessThanOrEqual(controller.view.keyboardLayoutGuide.layoutFrame.height, 1)
        XCTAssertEqual(editor.bounds.height, controller.view.bounds.height, accuracy: 1)
        editor.layoutManager.ensureLayout(for: editor.textContainer)
        editor.selectedRange = NSRange(location: (text as NSString).length, length: 0)
        let selection = try XCTUnwrap(editor.selectedTextRange)
        let caret = editor.caretRect(for: selection.end)
        editor.setContentOffset(CGPoint(x: 0, y: caret.minY - 140), animated: false)
        await drainMainQueue()
        let chosenOffset = editor.contentOffset.y
        let chosenCaretY = editor.caretRect(for: selection.end).minY - chosenOffset
        XCTAssertGreaterThan(chosenOffset, 1000, "Exercise reading space after the document end")
        XCTAssertEqual(chosenCaretY, 140, accuracy: 1)
        var sampledFrames = 0
        var maximumOffsetDrift: CGFloat = 0
        var maximumCaretDrift: CGFloat = 0
        let sample = {
            guard let position = editor.selectedTextRange?.end else { return }
            sampledFrames += 1
            let caretY = editor.caretRect(for: position).minY - editor.contentOffset.y
            maximumOffsetDrift = max(maximumOffsetDrift, abs(editor.contentOffset.y - chosenOffset))
            maximumCaretDrift = max(maximumCaretDrift, abs(caretY - chosenCaretY))
        }
        let sampler = EditorViewportSampler(sample: sample)
        sampler.start()
        defer { sampler.stop() }
        XCTAssertTrue(editor.becomeFirstResponder())
        controller.view.layoutIfNeeded()
        sample()
        let settlingDeadline = ContinuousClock.now.advanced(by: .milliseconds(700))
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while (ContinuousClock.now < settlingDeadline || sampledFrames < 20 || controller.view.keyboardLayoutGuide.layoutFrame.height < 100),
              ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertGreaterThan(controller.view.keyboardLayoutGuide.layoutFrame.height, 100,
                             "An actual keyboard must reduce the editor viewport")
        XCTAssertGreaterThanOrEqual(sampledFrames, 20)
        XCTAssertLessThanOrEqual(maximumOffsetDrift, 1,
                                 "Focusing the end of a reading page must not clamp it down and jump back")
        XCTAssertLessThanOrEqual(maximumCaretDrift, 1,
                                 "The chosen final line must stay in place throughout keyboard rise")
        let framesBeforeTyping = sampledFrames
        for character in " More." {
            editor.insertText(String(character))
            editor.keepCaretVisibleAfterLayout()
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertGreaterThan(sampledFrames, framesBeforeTyping + 2,
                             "Inspect the first keystrokes across displayed frames")
        XCTAssertTrue(editor.text.hasSuffix("The last observation. More."))
        let typedCaret = editor.caretRect(for: try XCTUnwrap(editor.selectedTextRange?.end))
        XCTAssertGreaterThanOrEqual(typedCaret.minY, editor.bounds.minY + window.safeAreaInsets.top)
        XCTAssertLessThanOrEqual(typedCaret.maxY, editor.bounds.maxY - 18)
        let framesBeforeDismissal = sampledFrames
        editor.resignFirstResponder()
        let hiddenSettlingDeadline = ContinuousClock.now.advanced(by: .milliseconds(700))
        let hiddenDeadline = ContinuousClock.now.advanced(by: .seconds(3))
        while (ContinuousClock.now < hiddenSettlingDeadline || controller.view.keyboardLayoutGuide.layoutFrame.height > 1), ContinuousClock.now < hiddenDeadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        sampler.stop()
        XCTAssertLessThanOrEqual(controller.view.keyboardLayoutGuide.layoutFrame.height, 1,
                                 "Dismissal must actually complete")
        XCTAssertGreaterThan(sampledFrames, framesBeforeDismissal + 2,
                             "Inspect keyboard dismissal in motion")
        XCTAssertLessThanOrEqual(maximumOffsetDrift, 1,
                                 "Keyboard dismissal must also keep the same document position throughout motion")
        XCTAssertLessThanOrEqual(maximumCaretDrift, 1,
                                 "Typing and dismissal must keep the final line in its chosen position")
        XCTAssertEqual(editor.contentOffset.y, chosenOffset, accuracy: 1,
                       "Returning to reading must preserve the selected page position")

        XCTAssertTrue(editor.becomeFirstResponder())
        let secondFocusDeadline = ContinuousClock.now.advanced(by: .seconds(3))
        while controller.view.keyboardLayoutGuide.layoutFrame.height < 100, ContinuousClock.now < secondFocusDeadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        try? await Task.sleep(for: .milliseconds(350))
        let newlineOffset = editor.contentOffset.y
        var newlineFrames = 0
        var newlineOffsetDrift: CGFloat = 0
        var minimumCaretTop = CGFloat.greatestFiniteMagnitude
        var minimumCaretBottomClearance = CGFloat.greatestFiniteMagnitude
        let newlineSample = {
            guard let position = editor.selectedTextRange?.end else { return }
            let caret = editor.caretRect(for: position)
            newlineFrames += 1
            newlineOffsetDrift = max(newlineOffsetDrift, abs(editor.contentOffset.y - newlineOffset))
            minimumCaretTop = min(minimumCaretTop, caret.minY - editor.contentOffset.y)
            minimumCaretBottomClearance = min(minimumCaretBottomClearance, editor.bounds.maxY - caret.maxY)
        }
        let newlineSampler = EditorViewportSampler(sample: newlineSample)
        newlineSampler.start()
        defer { newlineSampler.stop() }
        editor.insertText("\n")
        newlineSample()
        try? await Task.sleep(for: .milliseconds(250))
        editor.insertText("A new paragraph.")
        newlineSample()
        try? await Task.sleep(for: .milliseconds(250))
        newlineSampler.stop()
        XCTAssertEqual(editor.text, text + " More.\nA new paragraph.")
        XCTAssertEqual(editor.selectedRange, NSRange(location: (editor.text as NSString).length, length: 0))
        XCTAssertGreaterThan(newlineFrames, 10)
        XCTAssertLessThanOrEqual(newlineOffsetDrift, 1,
                                 "Return at the end of a long page must retain its chosen reading position")
        XCTAssertGreaterThanOrEqual(minimumCaretTop, window.safeAreaInsets.top)
        XCTAssertGreaterThanOrEqual(minimumCaretBottomClearance, 18,
                                    "The new line must remain above the keyboard throughout Return and typing")

        // Near the keyboard, Return must still reveal the new insertion line.
        // Preventing the inflated request must not disable genuine scrolling.
        let endCaret = editor.caretRect(for: try XCTUnwrap(editor.selectedTextRange?.end))
        editor.setContentOffset(CGPoint(x: 0, y: endCaret.maxY - editor.bounds.height + 22), animated: false)
        let edgeOffset = editor.contentOffset.y
        var largestEdgeOffset = edgeOffset
        let edgeSampler = EditorViewportSampler { largestEdgeOffset = max(largestEdgeOffset, editor.contentOffset.y) }
        edgeSampler.start()
        defer { edgeSampler.stop() }
        editor.insertText("\n")
        try? await Task.sleep(for: .milliseconds(350))
        edgeSampler.stop()
        let edgeCaret = editor.caretRect(for: try XCTUnwrap(editor.selectedTextRange?.end))
        XCTAssertEqual(editor.text, text + " More.\nA new paragraph.\n")
        XCTAssertEqual(editor.selectedRange, NSRange(location: (editor.text as NSString).length, length: 0))
        XCTAssertGreaterThan(editor.contentOffset.y, edgeOffset + 1,
                             "A new line beyond the comfort margin must actually scroll into view")
        XCTAssertLessThanOrEqual(largestEdgeOffset - edgeOffset, Theme.bodyUIFont().lineHeight * 2 + 24,
                                 "Reveal only the new line and normal clearance, not all the blank paper")
        XCTAssertGreaterThanOrEqual(edgeCaret.minY, editor.bounds.minY + window.safeAreaInsets.top)
        XCTAssertLessThanOrEqual(edgeCaret.maxY, editor.bounds.maxY - 18 + 0.5)
        await store.flushCatalogueCache()
    }

    func testBlankComposerKeepsInitialCaretAndBackThroughFirstCharacterAndDeletion() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("drift-blank-viewport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = NoteStore(folderURL: folder)
        let snapshot = try await store.makeUnsavedNote()
        let controller = NoteEditorViewController(store: store, snapshot: snapshot, isNew: true)
        let navigation = PaperNavigationController(rootViewController: UIViewController())
        navigation.view.keyboardLayoutGuide.usesBottomSafeArea = false
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive }))
        let window = try XCTUnwrap(scene.windows.first(where: \.isKeyWindow))
        let originalRoot = window.rootViewController
        window.endEditing(true)
        window.rootViewController = navigation
        defer {
            window.endEditing(true)
            window.rootViewController = originalRoot
            window.layoutIfNeeded()
        }
        window.layoutIfNeeded()
        let hiddenDeadline = ContinuousClock.now.advanced(by: .seconds(3))
        while navigation.view.keyboardLayoutGuide.layoutFrame.height > 1, ContinuousClock.now < hiddenDeadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertLessThanOrEqual(navigation.view.keyboardLayoutGuide.layoutFrame.height, 1)
        controller.loadViewIfNeeded()
        let editor = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? EditorTextView }.first)
        var sampledFrames = 0
        var maximumOffset: CGFloat = 0
        let sampler = EditorViewportSampler {
            guard controller.view.window === window else { return }
            sampledFrames += 1
            maximumOffset = max(maximumOffset, abs(editor.contentOffset.y))
        }
        sampler.start()
        defer { sampler.stop() }
        navigation.pushViewController(controller, animated: true)
        let settled = ContinuousClock.now.advanced(by: .milliseconds(900))
        let focusDeadline = ContinuousClock.now.advanced(by: .seconds(3))
        while (ContinuousClock.now < settled || controller.view.keyboardLayoutGuide.layoutFrame.height < 100), ContinuousClock.now < focusDeadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(editor.isFirstResponder)
        XCTAssertGreaterThan(controller.view.keyboardLayoutGuide.layoutFrame.height, 100)
        XCTAssertGreaterThan(sampledFrames, 10)
        XCTAssertLessThanOrEqual(maximumOffset, 1, "A blank composer must retain its opening position throughout focus")
        let back = try XCTUnwrap(controller.view.subviews.flatMap(\.subviews)
            .compactMap { $0 as? UIButton }.first(where: { $0.accessibilityIdentifier == "editor-back" }))
        XCTAssertGreaterThan(back.alpha, 0.95)
        let initialCaret = editor.caretRect(for: try XCTUnwrap(editor.selectedTextRange?.end))
        XCTAssertGreaterThanOrEqual(initialCaret.minY, editor.bounds.minY + window.safeAreaInsets.top)
        XCTAssertLessThanOrEqual(initialCaret.maxY, editor.bounds.maxY - 18)
        editor.insertText("H")
        editor.keepCaretVisibleAfterLayout()
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(editor.text, "H")
        XCTAssertLessThanOrEqual(maximumOffset, 1, "The first character must not move the page")
        let typedCaret = editor.caretRect(for: try XCTUnwrap(editor.selectedTextRange?.end))
        XCTAssertEqual(typedCaret.minY, initialCaret.minY, accuracy: 1)
        editor.deleteBackward()
        editor.keepCaretVisibleAfterLayout()
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(editor.text, "")
        XCTAssertLessThanOrEqual(maximumOffset, 1,
                                "Removing the last character must not expose the pull-to-read hint")
        XCTAssertEqual(editor.contentOffset.y, 0, accuracy: 1,
                       "Deleting the final character must settle at the blank page's origin")
        let emptyCaret = editor.caretRect(for: try XCTUnwrap(editor.selectedTextRange?.end))
        XCTAssertGreaterThanOrEqual(emptyCaret.minY, editor.bounds.minY + window.safeAreaInsets.top)
        XCTAssertLessThanOrEqual(emptyCaret.maxY, editor.bounds.maxY - 18)
        XCTAssertGreaterThan(back.alpha, 0.95)
        await store.flushCatalogueCache()
    }

    func testTitleReturnKeepsPageAndTitleSteadyThroughBlankLinesAndImmediateBodyTyping() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("drift-title-return-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = NoteStore(folderURL: folder)
        let snapshot = try await store.makeUnsavedNote()
        let controller = NoteEditorViewController(store: store, snapshot: snapshot, isNew: true)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive }))
        let window = try XCTUnwrap(scene.windows.first(where: \.isKeyWindow))
        let originalRoot = window.rootViewController
        window.endEditing(true)
        window.rootViewController = controller
        defer {
            window.endEditing(true)
            window.rootViewController = originalRoot
            window.layoutIfNeeded()
        }
        window.layoutIfNeeded()
        let editor = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? EditorTextView }.first)
        XCTAssertTrue(editor.delegate === controller, "Exercise the real selection, styling, and caret callbacks")
        let focusDeadline = ContinuousClock.now.advanced(by: .seconds(3))
        while (!editor.isFirstResponder || controller.view.keyboardLayoutGuide.layoutFrame.height < 100),
              ContinuousClock.now < focusDeadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(editor.isFirstResponder)
        XCTAssertGreaterThan(controller.view.keyboardLayoutGuide.layoutFrame.height, 100)
        try? await Task.sleep(for: .milliseconds(400))

        // A short title, a wrapped title, then short again cover first use,
        // the larger heading layout, and repeated use of the same live editor.
        for (attempt, title) in ["A new thought", "A longer title with enough words to wrap onto another line", "Another thought"].enumerated() {
            editor.selectedRange = NSRange(location: 0, length: editor.textStorage.length)
            editor.insertText(title)
            try? await Task.sleep(for: .milliseconds(200))
            editor.setContentOffset(.zero, animated: false)
            XCTAssertEqual(editor.text, title)
            XCTAssertEqual(editor.selectedRange, NSRange(location: (title as NSString).length, length: 0))

            func titleRect() -> CGRect {
                let glyphs = editor.layoutManager.glyphRange(forCharacterRange: NSRange(location: 0, length: 1), actualCharacterRange: nil)
                let rect = editor.layoutManager.boundingRect(forGlyphRange: glyphs, in: editor.textContainer)
                return rect.offsetBy(dx: editor.textContainerInset.left, dy: editor.textContainerInset.top - editor.contentOffset.y)
            }
            let initialTitle = titleRect()
            let initialOffset = editor.contentOffset.y
            var phase = "first-return"
            var samples: [(phase: String, seconds: Double, titleY: CGFloat, titleHeight: CGFloat, caretY: CGFloat, offset: CGFloat, selection: Int, caretHeight: CGFloat, extraY: CGFloat, extraHeight: CGFloat)] = []
            let start = CACurrentMediaTime()
            let sample = {
                guard let caretPosition = editor.selectedTextRange?.end else { return }
                let titleFrame = titleRect()
                let caret = editor.caretRect(for: caretPosition)
                samples.append((phase, CACurrentMediaTime() - start, titleFrame.minY, titleFrame.height,
                                caret.minY - editor.contentOffset.y, editor.contentOffset.y, editor.selectedRange.location,
                                caret.height, editor.layoutManager.extraLineFragmentRect.minY,
                                editor.layoutManager.extraLineFragmentRect.height))
            }
            let sampler = EditorViewportSampler(sample: sample)
            sampler.start()
            editor.insertText("\n")
            sample()
            try? await Task.sleep(for: .milliseconds(250))
            XCTAssertEqual(editor.text, title + "\n")
            let firstBodyCaretY = editor.caretRect(for: try XCTUnwrap(editor.selectedTextRange?.end)).minY - editor.contentOffset.y

            phase = "blank-return"
            editor.insertText("\n")
            sample()
            try? await Task.sleep(for: .milliseconds(250))
            XCTAssertEqual(editor.text, title + "\n\n")
            let blankBodyCaretY = editor.caretRect(for: try XCTUnwrap(editor.selectedTextRange?.end)).minY - editor.contentOffset.y

            // Enter followed by typing without waiting must use the same final
            // body line immediately, including after an already blank paragraph.
            phase = "immediate-body"
            editor.insertText("\n")
            editor.insertText("The body starts here.")
            sample()
            try? await Task.sleep(for: .milliseconds(250))
            let immediateBodyCaretY = editor.caretRect(for: try XCTUnwrap(editor.selectedTextRange?.end)).minY - editor.contentOffset.y

            phase = "body-return"
            editor.insertText("\n")
            sample()
            try? await Task.sleep(for: .milliseconds(250))
            let bodyReturnCaretY = editor.caretRect(for: try XCTUnwrap(editor.selectedTextRange?.end)).minY - editor.contentOffset.y

            phase = "delete-reenter"
            editor.deleteBackward()
            editor.insertText("\n")
            editor.insertText("The next line.")
            sample()
            try? await Task.sleep(for: .milliseconds(250))
            let expected = title + "\n\n\nThe body starts here.\nThe next line."
            XCTAssertEqual(editor.text, expected)
            XCTAssertEqual(editor.selectedRange, NSRange(location: (expected as NSString).length, length: 0))
            let finalCaretY = editor.caretRect(for: try XCTUnwrap(editor.selectedTextRange?.end)).minY - editor.contentOffset.y

            phase = "middle-body"
            let splitLocation = (expected as NSString).range(of: "starts here.").location
            XCTAssertNotEqual(splitLocation, NSNotFound)
            editor.selectedRange = NSRange(location: splitLocation, length: 0)
            editor.insertText("\n")
            sample()
            try? await Task.sleep(for: .milliseconds(250))
            sampler.stop()
            XCTAssertEqual(editor.text, expected.replacingOccurrences(of: "body starts", with: "body \nstarts"),
                           "Return inside a populated paragraph must preserve all following text")
            XCTAssertEqual(editor.selectedRange, NSRange(location: splitLocation + 1, length: 0))
            let middleCaretY = editor.caretRect(for: try XCTUnwrap(editor.selectedTextRange?.end)).minY - editor.contentOffset.y
            let expectedCaretY = ["first-return": firstBodyCaretY, "blank-return": blankBodyCaretY,
                                  "immediate-body": immediateBodyCaretY, "body-return": bodyReturnCaretY,
                                  "delete-reenter": finalCaretY, "middle-body": middleCaretY]
            XCTAssertGreaterThan(samples.count, 15, "Observe Return and the settled tail across displayed frames")
            for (stage, expectedY) in expectedCaretY {
                let frames = samples.filter { $0.phase == stage }
                XCTAssertGreaterThan(frames.count, 3, "Sample displayed frames after \(stage)")
                XCTAssertLessThanOrEqual(frames.map { abs($0.offset - initialOffset) }.max() ?? 0, 1,
                                         "Return must not scroll an already visible short note: \(stage)")
                XCTAssertLessThanOrEqual(frames.map { abs($0.titleY - initialTitle.minY) }.max() ?? 0, 1,
                                         "The title must remain in place: \(stage)")
                XCTAssertLessThanOrEqual(frames.map { abs($0.titleHeight - initialTitle.height) }.max() ?? 0, 1,
                                         "Return must not temporarily restyle the title: \(stage)")
                XCTAssertLessThanOrEqual(frames.map { abs($0.caretY - expectedY) }.max() ?? 0, 1,
                                         "The body caret must occupy its final line immediately: \(stage)")
            }
            let attachment = XCTAttachment(string: "phase,seconds,titleY,titleHeight,caretY,offsetY,selection,caretHeight,extraY,extraHeight\n" + samples.map {
                "\($0.phase),\($0.seconds),\($0.titleY),\($0.titleHeight),\($0.caretY),\($0.offset),\($0.selection),\($0.caretHeight),\($0.extraY),\($0.extraHeight)"
            }.joined(separator: "\n"))
            attachment.name = "title-return-frames-\(attempt + 1)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        await store.flushCatalogueCache()
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}

@MainActor
private final class EditorViewportSampler: NSObject {
    private let sample: () -> Void
    private var displayLink: CADisplayLink?
    init(sample: @escaping () -> Void) { self.sample = sample }
    func start() {
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }
    func stop() { displayLink?.invalidate(); displayLink = nil }
    @objc private func tick() { sample() }
}

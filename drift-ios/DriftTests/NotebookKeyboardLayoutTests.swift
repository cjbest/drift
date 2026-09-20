import XCTest
import UIKit
@testable import Drift

@MainActor
final class NotebookKeyboardLayoutTests: XCTestCase {
    func testOnlySearchKeyboardShortensNotebookAndLowerRowsAreReadyAtFocusHandoff() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("drift-keyboard-layout-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for index in 0..<20 {
            let title = String(format: "Thought %02d", index)
            try "\(title)\nA quiet line of writing."
                .write(to: folder.appendingPathComponent(title + ".md"), atomically: true, encoding: .utf8)
        }
        let store = NoteStore(folderURL: folder)
        await store.refresh()
        let notebook = NotebookViewController(store: store)
        let navigation = PaperNavigationController(rootViewController: notebook)
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
        notebook.loadViewIfNeeded()
        window.layoutIfNeeded()
        notebook.view.layoutIfNeeded()
        let table = try XCTUnwrap(notebook.view.subviews.compactMap { $0 as? UITableView }.first)
        let search = try XCTUnwrap(descendants(of: notebook.view).compactMap { $0 as? UITextField }
            .first(where: { $0.accessibilityIdentifier == "note-search" }))
        table.layoutIfNeeded()
        let bottomRow = try XCTUnwrap(table.indexPathsForVisibleRows?.last)
        let bottomIdentifier = try XCTUnwrap(table.cellForRow(at: bottomRow)?.accessibilityIdentifier)
        let originalOffset = table.contentOffset
        XCTAssertEqual(table.frame.maxY, notebook.view.bounds.maxY, accuracy: 0.5)

        // Another responder keeps an actual keyboard on screen after Search
        // resigns, as the editor does during a navigation handoff. A held
        // keyboard makes premature viewport clipping deterministic instead of
        // depending on a screenshot landing in a 30 ms dismissal window.
        let otherInput = UITextField(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        otherInput.alpha = 0.01
        otherInput.autocorrectionType = .no
        notebook.view.addSubview(otherInput)

        // Let UIKit commit the replacement root before asking the system input
        // service to attach to its text field.
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }

        for _ in 0..<3 {
            XCTAssertTrue(search.becomeFirstResponder())
            let keyboardShown = await waitForLayout(window) {
                notebook.view.keyboardLayoutGuide.layoutFrame.height > 100
            }
            XCTAssertTrue(keyboardShown, "Exercise a real on-screen keyboard; an absent keyboard cannot verify avoidance")
            XCTAssertEqual(table.frame.maxY, notebook.view.keyboardLayoutGuide.layoutFrame.minY, accuracy: 1,
                           "Search results must stay above their keyboard")
            XCTAssertLessThan(table.frame.maxY, notebook.view.bounds.maxY - 100)
            XCTAssertFalse((table.indexPathsForVisibleRows ?? []).contains(bottomRow),
                           "The fixture must include a row below the search viewport")

            XCTAssertTrue(otherInput.becomeFirstResponder())
            notebook.view.layoutIfNeeded()
            table.layoutIfNeeded()
            XCTAssertFalse(search.isFirstResponder)
            XCTAssertGreaterThan(notebook.view.keyboardLayoutGuide.layoutFrame.height, 100,
                                 "Keep the keyboard present during the handoff assertion")
            XCTAssertEqual(table.frame.maxY, notebook.view.bounds.maxY, accuracy: 0.5,
                           "Another input's keyboard must not clip the notebook as it is uncovered")
            XCTAssertEqual(table.cellForRow(at: bottomRow)?.accessibilityIdentifier, bottomIdentifier,
                           "Lower rows must be laid out before the keyboard uncovers them")
            XCTAssertEqual(table.contentOffset.y, originalOffset.y, accuracy: 0.5,
                           "Changing keyboard ownership must preserve the notebook's position")
        }
        otherInput.resignFirstResponder()
        let keyboardHidden = await waitForLayout(window) {
            notebook.view.keyboardLayoutGuide.layoutFrame.height < 1
        }
        XCTAssertTrue(keyboardHidden)
        XCTAssertEqual(table.frame.maxY, notebook.view.bounds.maxY, accuracy: 0.5,
                       "The ordinary notebook must reach the physical bottom edge")
        await store.flushCatalogueCache()
    }

    private func descendants(of view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    private func waitForLayout(_ window: UIWindow, condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        repeat {
            window.layoutIfNeeded()
            window.rootViewController?.view.layoutIfNeeded()
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        } while ContinuousClock.now < deadline
        return false
    }
}

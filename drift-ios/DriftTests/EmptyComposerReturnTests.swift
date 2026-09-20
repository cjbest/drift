import XCTest
import UIKit
@testable import Drift

@MainActor
final class EmptyComposerReturnTests: XCTestCase {
    func testSavedEmptyComposerIsAbsentFromEveryReturningFrame() async throws {
        let fixture = try await Fixture()
        defer { fixture.close() }
        let session = EditorDocumentSession(store: fixture.store, snapshot: try await fixture.store.makeUnsavedNote())
        session.changed("A fleeting thought")
        await session.flush()
        session.changed("")
        await session.flush()
        XCTAssertFalse(session.isDirty)
        XCTAssertFalse(session.snapshot.isUnsaved)
        XCTAssertEqual(fixture.store.notes.count, 22)
        let editor = NoteEditorViewController(store: fixture.store, snapshot: session.snapshot, isNew: true)
        await fixture.push(editor)
        var rowCounts: [Int] = []
        var maximumHeightError: CGFloat = 0
        var maximumPositionError: CGFloat = 0
        let sampler = EmptyReturnFrameSampler {
            guard fixture.navigation.topViewController === fixture.notebook,
                  fixture.notebook.view.window === fixture.window else { return }
            rowCounts.append(fixture.table.numberOfRows(inSection: 0))
            for cell in fixture.table.visibleCells {
                guard let layer = cell.layer.presentation() else { continue }
                maximumHeightError = max(maximumHeightError, abs(layer.bounds.height - fixture.table.rowHeight))
                maximumPositionError = max(maximumPositionError, abs(layer.frame.minY - cell.frame.minY))
            }
        }
        sampler.start()
        fixture.navigation.popViewController(animated: true)
        try await Task.sleep(for: .seconds(1.3))
        sampler.stop()
        XCTAssertGreaterThan(rowCounts.count, 10)
        XCTAssertEqual(Set(rowCounts), [21], "Only the original 20 notes and existing empty note may appear, from the first attached frame through the settling tail")
        XCTAssertLessThanOrEqual(maximumHeightError, 1)
        XCTAssertLessThanOrEqual(maximumPositionError, 1)
        XCTAssertEqual(fixture.store.notes.count, 21)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.existingEmpty.path))
    }

    func testLastDeleteImmediatelyBeforeBackNeverRevealsTheOldTitle() async throws {
        let fixture = try await Fixture()
        defer { fixture.close() }
        let session = EditorDocumentSession(store: fixture.store, snapshot: try await fixture.store.makeUnsavedNote())
        session.changed("Only a moment")
        await session.flush()
        let editor = NoteEditorViewController(store: fixture.store, snapshot: session.snapshot, isNew: true)
        await fixture.push(editor)
        let textView = try XCTUnwrap(editor.view.subviews.compactMap { $0 as? UITextView }.first)
        textView.text = ""
        editor.textViewDidChange(textView)
        var counts: [Int] = []
        let sampler = EmptyReturnFrameSampler {
            guard fixture.navigation.topViewController === fixture.notebook,
                  fixture.notebook.view.window === fixture.window else { return }
            counts.append(fixture.table.numberOfRows(inSection: 0))
        }
        sampler.start()
        // Same run-loop turn as the last deletion: strictly within debounce.
        fixture.navigation.popViewController(animated: true)
        try await Task.sleep(for: .seconds(1.3))
        sampler.stop()
        XCTAssertGreaterThan(counts.count, 10)
        XCTAssertEqual(Set(counts), [21])
        XCTAssertEqual(fixture.store.notes.count, 21)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.existingEmpty.path))
    }

    func testCancelledInteractiveBackRestoresComposerAndKeepsResumedWriting() async throws {
        let fixture = try await Fixture()
        defer { fixture.close() }
        let snapshot = try await fixture.store.createNote()
        let editor = NoteEditorViewController(store: fixture.store, snapshot: snapshot, isNew: true)
        await fixture.push(editor)
        let driver = EmptyReturnInteractionDriver()
        fixture.navigation.delegate = driver
        fixture.navigation.popViewController(animated: true)
        driver.interaction.update(0.35)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(fixture.store.search("").count, 21)
        driver.interaction.cancel()
        try await Task.sleep(for: .milliseconds(650))
        XCTAssertTrue(fixture.navigation.topViewController === editor)
        XCTAssertEqual(fixture.store.search("").count, 22)
        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshot.note.url.path))
        XCTAssertFalse(fixture.store.canUndoTrash)
        let textView = try XCTUnwrap(editor.view.subviews.compactMap { $0 as? UITextView }.first)
        textView.text = "Kept after cancelled Back"
        editor.textViewDidChange(textView)
        fixture.navigation.delegate = fixture.navigation
        fixture.navigation.popViewController(animated: true)
        try await Task.sleep(for: .seconds(1))
        XCTAssertEqual(fixture.store.notes.count, 22)
        let kept = try XCTUnwrap(fixture.store.notes.first(where: { $0.title == "Kept after cancelled Back" }))
        XCTAssertEqual(try String(contentsOf: kept.url, encoding: .utf8), "Kept after cancelled Back")
        XCTAssertFalse(fixture.store.canUndoTrash)
    }

    func testCompletedInteractiveBackNeverRevealsAbandonedComposer() async throws {
        let fixture = try await Fixture()
        defer { fixture.close() }
        let snapshot = try await fixture.store.createNote()
        let editor = NoteEditorViewController(store: fixture.store, snapshot: snapshot, isNew: true)
        await fixture.push(editor)
        let driver = EmptyReturnInteractionDriver()
        fixture.navigation.delegate = driver
        var counts: [Int] = []
        let sampler = EmptyReturnFrameSampler {
            guard fixture.navigation.topViewController === fixture.notebook,
                  fixture.notebook.view.window === fixture.window else { return }
            counts.append(fixture.table.numberOfRows(inSection: 0))
        }
        sampler.start()
        fixture.navigation.popViewController(animated: true)
        driver.interaction.update(0.6)
        try await Task.sleep(for: .milliseconds(80))
        driver.interaction.finish()
        try await Task.sleep(for: .seconds(1))
        sampler.stop()
        XCTAssertTrue(fixture.navigation.topViewController === fixture.notebook)
        XCTAssertGreaterThan(counts.count, 10)
        XCTAssertEqual(Set(counts), [21])
        XCTAssertEqual(fixture.store.notes.count, 21)
        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshot.note.url.path))
    }

    func testExistingEmptyEditorReturnsWithoutDeletionOrOmission() async throws {
        let fixture = try await Fixture()
        defer { fixture.close() }
        let note = try XCTUnwrap(fixture.store.notes.first(where: { $0.url == fixture.existingEmpty }))
        let editor = NoteEditorViewController(store: fixture.store, snapshot: try await fixture.store.open(note))
        await fixture.push(editor)
        fixture.navigation.popViewController(animated: true)
        try await Task.sleep(for: .seconds(1))
        XCTAssertEqual(fixture.store.search("").count, 21)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.existingEmpty.path))
        XCTAssertFalse(fixture.store.canUndoTrash)
    }

    @MainActor
    private final class Fixture {
        let folder: URL
        let existingEmpty: URL
        let store: NoteStore
        let notebook: NotebookViewController
        let navigation: PaperNavigationController
        let window: UIWindow
        let originalRoot: UIViewController?
        let table: UITableView
        private var didShowCount = 0

        init() async throws {
            folder = FileManager.default.temporaryDirectory.appendingPathComponent("empty-return-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for index in 0..<20 {
                let title = String(format: "Original %02d", index)
                try "\(title)\nKeep this thought.".write(to: folder.appendingPathComponent(title + ".md"), atomically: true, encoding: .utf8)
            }
            existingEmpty = folder.appendingPathComponent("Existing blank.md")
            try "".write(to: existingEmpty, atomically: true, encoding: .utf8)
            store = NoteStore(folderURL: folder)
            await store.refresh()
            notebook = NotebookViewController(store: store)
            navigation = PaperNavigationController(rootViewController: notebook)
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first(where: { $0.activationState == .foregroundActive }))
            window = try XCTUnwrap(scene.windows.first(where: \.isKeyWindow))
            originalRoot = window.rootViewController
            window.endEditing(true)
            window.rootViewController = navigation
            window.layoutIfNeeded()
            notebook.view.layoutIfNeeded()
            table = try XCTUnwrap(notebook.view.subviews.compactMap { $0 as? UITableView }.first)
            let previousDidShow = navigation.onDidShow
            navigation.onDidShow = { [weak self] in previousDidShow?(); self?.didShowCount += 1 }
            try await Task.sleep(for: .milliseconds(100))
        }

        func push(_ editor: NoteEditorViewController) async {
            let previous = didShowCount
            navigation.pushViewController(editor, animated: true)
            let deadline = ContinuousClock.now.advanced(by: .seconds(4))
            while didShowCount == previous && ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertGreaterThan(didShowCount, previous)
            XCTAssertTrue(navigation.topViewController === editor)
        }

        func close() {
            window.endEditing(true)
            window.rootViewController = originalRoot
            window.layoutIfNeeded()
            try? FileManager.default.removeItem(at: folder)
        }
    }
}

@MainActor
private final class EmptyReturnFrameSampler: NSObject {
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

/// Exercise UIKit's actual containment/appearance cancellation callbacks. The
/// test controls progress; production continues using UIKit's native edge pop.
@MainActor
private final class EmptyReturnInteractionDriver: NSObject, UINavigationControllerDelegate, UIViewControllerAnimatedTransitioning {
    let interaction = UIPercentDrivenInteractiveTransition()
    func navigationController(_ navigationController: UINavigationController, animationControllerFor operation: UINavigationController.Operation,
                              from fromVC: UIViewController, to toVC: UIViewController) -> UIViewControllerAnimatedTransitioning? { self }
    func navigationController(_ navigationController: UINavigationController, interactionControllerFor animationController: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? { interaction }
    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval { 0.35 }
    func animateTransition(using context: UIViewControllerContextTransitioning) {
        guard let from = context.view(forKey: .from), let to = context.view(forKey: .to),
              let toController = context.viewController(forKey: .to) else { XCTFail("Missing navigation views"); return }
        to.frame = context.finalFrame(for: toController)
        context.containerView.insertSubview(to, belowSubview: from)
        UIView.animate(withDuration: transitionDuration(using: context), animations: {
            from.transform = CGAffineTransform(translationX: from.bounds.width, y: 0)
        }, completion: { _ in
            from.transform = .identity
            context.completeTransition(!context.transitionWasCancelled)
        })
    }
}

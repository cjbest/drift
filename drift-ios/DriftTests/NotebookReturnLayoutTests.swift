import XCTest
import UIKit
@testable import Drift

@MainActor
final class NotebookReturnLayoutTests: XCTestCase {
    func testReturningFromSearchResultRevealsFullSizeRowsThroughoutBack() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("drift-return-layout-\(UUID().uuidString)", isDirectory: true)
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
        window.layoutIfNeeded()
        notebook.view.layoutIfNeeded()
        let table = try XCTUnwrap(notebook.view.subviews.compactMap { $0 as? UITableView }.first)
        let search = try XCTUnwrap(descendants(of: notebook.view).compactMap { $0 as? UITextField }
            .first(where: { $0.accessibilityIdentifier == "note-search" }))
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }

        for _ in 0..<3 {
            XCTAssertTrue(search.becomeFirstResponder())
            search.text = "Thought 00"
            search.sendActions(for: .editingChanged)
            let filtered = await waitUntil {
                table.numberOfRows(inSection: 0) == 1 && !store.isLoading
            }
            XCTAssertTrue(filtered)
            notebook.tableView(table, didSelectRowAt: IndexPath(row: 0, section: 0))
            let opened = await waitUntil {
                navigation.topViewController is NoteEditorViewController && navigation.transitionCoordinator == nil
            }
            XCTAssertTrue(opened)
            XCTAssertEqual(search.text, "", "Opening a result clears Search for the returning notebook")
            XCTAssertEqual(table.numberOfRows(inSection: 0), 1,
                           "Exercise the deferred one-result to full-notebook transition")

            var renderedFrames = 0
            var inspectedRows = 0
            var maximumHeightError: CGFloat = 0
            var maximumPositionError: CGFloat = 0
            var minimumRowCount = Int.max
            let sampler = NotebookFrameSampler {
                // UIKit can change topViewController before attaching the
                // incoming page or calling viewWillAppear. A display-link tick
                // in that interval still shows only the outgoing editor.
                // Inspect every frame from the notebook's first attachment.
                guard navigation.topViewController === notebook,
                      notebook.view.window === window else { return }
                renderedFrames += 1
                minimumRowCount = min(minimumRowCount, table.numberOfRows(inSection: 0))
                for cell in table.visibleCells {
                    guard let presentation = cell.layer.presentation() else { continue }
                    inspectedRows += 1
                    maximumHeightError = max(maximumHeightError, abs(presentation.bounds.height - table.rowHeight))
                    maximumPositionError = max(maximumPositionError, abs(presentation.frame.minY - cell.frame.minY))
                }
            }
            sampler.start()
            navigation.popViewController(animated: true)
            let returned = await waitUntil {
                renderedFrames >= 3 && navigation.topViewController === notebook && navigation.transitionCoordinator == nil
            }
            sampler.stop()
            XCTAssertTrue(returned)
            XCTAssertGreaterThanOrEqual(renderedFrames, 3, "Inspect motion, not just the final frame")
            XCTAssertGreaterThan(inspectedRows, renderedFrames, "Inspect presentation layers across several rows")
            XCTAssertEqual(minimumRowCount, 20, "All rows must exist from the first returning frame")
            XCTAssertLessThanOrEqual(maximumHeightError, 1,
                                     "Rows must not grow from collapsed heights during Back")
            XCTAssertLessThanOrEqual(maximumPositionError, 1,
                                     "Rows must not overlap then spread apart during Back")
        }
        await store.flushCatalogueCache()
    }

    private func descendants(of view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        repeat {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        } while ContinuousClock.now < deadline
        return false
    }
}

@MainActor
private final class NotebookFrameSampler: NSObject {
    private let sample: () -> Void
    private var displayLink: CADisplayLink?

    init(sample: @escaping () -> Void) { self.sample = sample }

    func start() {
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick() { sample() }
}

@MainActor
final class NotebookEmptyLayoutTests: XCTestCase {
    func testEmptyNotebookAndNoSearchResultsKeepReadableTextWidth() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("drift-empty-layout-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
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
        navigation.overrideUserInterfaceStyle = .dark
        defer {
            window.endEditing(true)
            window.rootViewController = originalRoot
            window.layoutIfNeeded()
        }
        window.layoutIfNeeded()
        notebook.view.layoutIfNeeded()
        let table = try XCTUnwrap(notebook.view.subviews.compactMap { $0 as? UITableView }.first)
        let search = try XCTUnwrap(descendants(of: notebook.view).compactMap { $0 as? UITextField }
            .first(where: { $0.accessibilityIdentifier == "note-search" }))

        for cycle in 1...3 {
            for (query, expectedTitle) in [("", "No notes yet"), ("unmatched", "No matching notes")] {
                search.text = query
                search.sendActions(for: .editingChanged)
                await Task.yield()
                window.layoutIfNeeded()
                table.layoutIfNeeded()
                let empty = try XCTUnwrap(table.backgroundView as? NotebookEmptyView)
                empty.layoutIfNeeded()
                attach(empty, name: "\(expectedTitle)-cycle-\(cycle)")
                let labels = try textLabels(in: empty)
                XCTAssertTrue(labels.contains { $0.text == expectedTitle })
                for label in labels {
                    XCTAssertGreaterThan(label.bounds.width, min(280, empty.bounds.width - 64),
                                         "Empty-state text must use a readable line measure, not the symbol's narrow column")
                    XCTAssertLessThan(label.bounds.height, 140,
                                      "Ordinary empty-state copy should not become a tall column of broken words")
                }
            }
        }
        await store.flushCatalogueCache()
    }

    func testEmptyStatesFitNarrowPhoneAndIPadAtAccessibilityTextSize() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive }))
        let window = try XCTUnwrap(scene.windows.first(where: \.isKeyWindow))
        let originalRoot = window.rootViewController
        let host = UIViewController()
        host.view.backgroundColor = Theme.paperUIColor
        window.rootViewController = host
        defer { window.rootViewController = originalRoot; window.layoutIfNeeded() }
        let empty = NotebookEmptyView()
        host.view.addSubview(empty)
        for category in [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge] {
            host.traitOverrides.preferredContentSizeCategory = category
            for width: CGFloat in [320, 430, 768] {
                empty.frame = CGRect(x: 0, y: 0, width: width, height: 650)
                for (title, detail, artwork, action) in [
                    ("No notes yet", "Tap + or double-tap this page to start one.", NotebookEmptyView.Artwork.symbol("square.and.pencil"), nil),
                    ("No matching notes", "Try another word or a shorter phrase.", .symbol("magnifyingglass"), nil),
                    ("Drift", "Choose the same iCloud Drive folder on iPhone and Mac.", .none, "Choose Shared Folder"),
                ] {
                    empty.configure(artwork: artwork, title: title, detail: detail, action: action)
                    await Task.yield()
                    window.layoutIfNeeded()
                    empty.layoutIfNeeded()
                    let labels = try textLabels(in: empty)
                    for label in labels {
                        XCTAssertGreaterThanOrEqual(label.bounds.width, min(256, width - 64),
                                                    "Readable text width at \(width)pt / \(category.rawValue)")
                        XCTAssertLessThanOrEqual(label.bounds.width, width - 64 + 0.5)
                        let needed = label.sizeThatFits(CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude))
                        XCTAssertGreaterThanOrEqual(label.bounds.height + 1, needed.height,
                                                    "Large text must remain complete and scrollable")
                    }
                    let scroll = try XCTUnwrap(empty.subviews.first as? UIScrollView)
                    let stack = try XCTUnwrap(descendants(of: scroll).first { $0 is UIStackView })
                    let contentFrame = stack.convert(stack.bounds, to: scroll)
                    XCTAssertGreaterThanOrEqual(contentFrame.minY, 0)
                    XCTAssertLessThanOrEqual(contentFrame.maxY, scroll.contentSize.height + 0.5)
                    if width == 430 { attach(empty, name: "\(title)-\(category.rawValue)") }
                }
            }
        }
    }

    private func descendants(of view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    private func textLabels(in view: NotebookEmptyView) throws -> [UILabel] {
        let stack = try XCTUnwrap(descendants(of: view).compactMap { $0 as? UIStackView }.first)
        let labels = stack.arrangedSubviews.compactMap { $0 as? UILabel }
        XCTAssertEqual(labels.count, 2)
        return labels
    }

    private func attach(_ view: UIView, name: String) {
        let image = UIGraphicsImageRenderer(bounds: view.bounds).image { context in
            Theme.paperUIColor.resolvedColor(with: view.traitCollection).setFill()
            context.fill(view.bounds)
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

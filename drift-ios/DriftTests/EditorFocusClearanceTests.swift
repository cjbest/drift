import XCTest
import UIKit
@testable import Drift

@MainActor
final class EditorFocusClearanceTests: XCTestCase {
    func testFirstFocusMovesCaretOutOfTopFadeGradually() async throws {
        try await verifyFocusClearance(typingDuringFocus: false)
    }

    func testTypingDuringFirstFocusKeepsClearanceGradual() async throws {
        try await verifyFocusClearance(typingDuringFocus: true)
    }

    private func verifyFocusClearance(typingDuringFocus: Bool) async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("drift-focus-clearance-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let text = "Long walk\n\n" + (1...36).map {
            "Observation \($0): the paper stays steady as a longer thought wraps across several lines."
        }.joined(separator: "\n\n")
        try text.write(to: folder.appendingPathComponent("Long walk.md"), atomically: true, encoding: .utf8)
        let store = NoteStore(folderURL: folder)
        await store.refresh()
        let snapshot = try await store.openForEditing(XCTUnwrap(store.notes.first))
        let controller = NoteEditorViewController(store: store, snapshot: snapshot)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first(where: { $0.activationState == .foregroundActive }))
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
        let hiddenDeadline = ContinuousClock.now.advanced(by: .seconds(3))
        while (controller.view.keyboardLayoutGuide.layoutFrame.height > 1 || abs(editor.bounds.height - controller.view.bounds.height) > 1), ContinuousClock.now < hiddenDeadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertLessThanOrEqual(controller.view.keyboardLayoutGuide.layoutFrame.height, 1)
        editor.layoutManager.ensureLayout(for: editor.textContainer)
        editor.selectedRange = NSRange(location: (text as NSString).length, length: 0)
        let position = try XCTUnwrap(editor.selectedTextRange?.end)
        let caret = editor.caretRect(for: position)
        let readingY = window.safeAreaInsets.top + 3
        editor.setContentOffset(CGPoint(x: 0, y: caret.minY - readingY), animated: false)
        try? await Task.sleep(for: .milliseconds(350))
        let requiredY = window.safeAreaInsets.top + 18
        let initialY = editor.caretRect(for: position).minY - editor.contentOffset.y
        XCTAssertEqual(initialY, readingY, accuracy: 1)
        XCTAssertGreaterThan(editor.contentOffset.y, 1000)
        var samples: [[Double]] = []
        let start = CACurrentMediaTime()
        let sampler = FocusClearanceSampler {
            guard let position = editor.selectedTextRange?.end else { return }
            let visibleOffset = editor.layer.presentation()?.bounds.origin.y ?? editor.contentOffset.y
            let y = editor.caretRect(for: position).minY - visibleOffset
            samples.append([CACurrentMediaTime() - start, y, editor.contentOffset.y,
                            controller.view.keyboardLayoutGuide.layoutFrame.height,
                            editor.layer.presentation()?.bounds.origin.y ?? editor.contentOffset.y])
        }
        sampler.start()
        defer { sampler.stop() }
        XCTAssertTrue(editor.becomeFirstResponder())
        XCTAssertTrue(editor.isFirstResponder, "Focus must remain immediate")
        if typingDuringFocus {
            let typingDeadline = ContinuousClock.now.advanced(by: .seconds(1))
            var caretBeforeTyping = initialY
            repeat {
                let presentedOffset = editor.layer.presentation()?.bounds.origin.y ?? editor.contentOffset.y
                caretBeforeTyping = editor.caretRect(for: try XCTUnwrap(editor.selectedTextRange?.end)).minY - presentedOffset
                if UIAccessibility.isReduceMotionEnabled || caretBeforeTyping > initialY + 0.5 { break }
                try? await Task.sleep(for: .milliseconds(10))
            } while ContinuousClock.now < typingDeadline
            print("FOCUS_EARLY_TYPING elapsed=\(CACurrentMediaTime() - start) caretY=\(caretBeforeTyping) reducedMotion=\(UIAccessibility.isReduceMotionEnabled)")
            if !UIAccessibility.isReduceMotionEnabled {
                XCTAssertGreaterThan(caretBeforeTyping, initialY + 0.5,
                                     "Typing must actually occur after clearance movement begins")
                XCTAssertLessThan(caretBeforeTyping, requiredY - 0.5,
                                  "Typing must actually interrupt the in-flight clearance movement")
            }
            editor.insertText("!")
        }
        try? await Task.sleep(for: .milliseconds(800))
        sampler.stop()
        let attachment = XCTAttachment(string: "seconds,caretY,offsetY,keyboardHeight,presentationOffsetY\n" + samples.map { $0.map(String.init(describing:)).joined(separator: ",") }.joined(separator: "\n"))
        attachment.name = "focus-clearance-frames"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertGreaterThan(controller.view.keyboardLayoutGuide.layoutFrame.height, 100)
        let finalY = editor.caretRect(for: position).minY - editor.contentOffset.y
        XCTAssertEqual(finalY, requiredY, accuracy: 1, "Retain full caret clearance")
        let positions = [Double(initialY)] + samples.map { $0[1] }
        let maxStep = zip(positions, positions.dropFirst()).map { abs($1 - $0) }.max() ?? 0
        let intermediate = samples.filter { $0[1] > initialY + 1 && $0[1] < requiredY - 1 }.count
        print("FOCUS_CLEARANCE reducedMotion=\(UIAccessibility.isReduceMotionEnabled) initial=\(initialY) final=\(finalY) maxStep=\(maxStep) intermediate=\(intermediate) samples=\(samples.count)")
        if UIAccessibility.isReduceMotionEnabled {
            XCTAssertEqual(intermediate, 0, "Reduced Motion keeps immediate caret accommodation")
        } else {
            XCTAssertGreaterThanOrEqual(intermediate, 3, "Required clearance must move through displayed intermediate positions")
            XCTAssertLessThan(maxStep, Double(requiredY - initialY) * 0.5, "Do not apply most of the clearance in one displayed frame")
        }
        if !typingDuringFocus { editor.insertText("!") }
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(editor.text.hasSuffix("lines.!"))
        let typedY = editor.caretRect(for: try XCTUnwrap(editor.selectedTextRange?.end)).minY - editor.contentOffset.y
        XCTAssertEqual(typedY, finalY, accuracy: 1, "First typing stays at the cleared insertion point")
        editor.resignFirstResponder()
        try? await Task.sleep(for: .milliseconds(600))
        await store.flushCatalogueCache()
    }
}

@MainActor
private final class FocusClearanceSampler: NSObject {
    private let sample: () -> Void
    private var link: CADisplayLink?
    init(sample: @escaping () -> Void) { self.sample = sample }
    func start() {
        let displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink.add(to: .main, forMode: .common)
        link = displayLink
    }
    func stop() { link?.invalidate(); link = nil }
    @objc private func tick() { sample() }
}

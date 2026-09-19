import Testing
import UIKit
@testable import Drift

@MainActor
struct QuickNoteActionTests {
    private func shortcut(type: String? = nil) -> UIApplicationShortcutItem {
        UIApplicationShortcutItem(type: type ?? QuickNoteAction.shortcutType, localizedTitle: "New Note")
    }

    @Test
    func appDeclaresOnlyNewNoteShortcut() throws {
        let items = try #require(Bundle.main.object(forInfoDictionaryKey: "UIApplicationShortcutItems")
                                 as? [[String: Any]])
        #expect(items.count == 1)
        let item = try #require(items.first)
        #expect(item["UIApplicationShortcutItemType"] as? String == QuickNoteAction.shortcutType)
        #expect(item["UIApplicationShortcutItemTitle"] as? String == "New Note")
        #expect(item["UIApplicationShortcutItemIconType"] as? String == "UIApplicationShortcutIconTypeCompose")
    }

    @Test
    func unknownShortcutDoesNotQueueRequest() {
        let actions = QuickNoteAction()
        #expect(!actions.handle(shortcut(type: "best.christopher.drift.unknown"), for: "scene-a"))
        #expect(!actions.consumePendingRequest(for: "scene-a"))
    }

    @Test
    func pendingRequestIsConsumedOnceAndCoalescesDuplicates() {
        let actions = QuickNoteAction()
        #expect(actions.handle(shortcut(), for: "scene-a"))
        #expect(actions.handle(shortcut(), for: "scene-a"))
        #expect(actions.consumePendingRequest(for: "scene-a"))
        #expect(!actions.consumePendingRequest(for: "scene-a"))
        #expect(actions.handle(shortcut(), for: "scene-a"))
        #expect(actions.consumePendingRequest(for: "scene-a"))
    }

    @Test
    func requestCanOnlyBeConsumedByItsTargetScene() {
        let actions = QuickNoteAction()
        #expect(actions.handle(shortcut(), for: "scene-a"))
        #expect(!actions.consumePendingRequest(for: "scene-b"))
        #expect(actions.handle(shortcut(), for: "scene-b"))
        #expect(actions.consumePendingRequest(for: "scene-a"))
        #expect(actions.consumePendingRequest(for: "scene-b"))
        #expect(!actions.consumePendingRequest(for: "scene-a"))
        #expect(!actions.consumePendingRequest(for: "scene-b"))
    }
}

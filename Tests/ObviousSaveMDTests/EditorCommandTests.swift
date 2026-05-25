import AppKit
import Testing
@testable import ObviousSaveMD

@Suite("Editor commands")
@MainActor
struct EditorCommandTests {
    @Test func toolbarCommandsExposeUndoCopyAndPaste() {
        #expect(EditorCommand.toolbarCommands == [.undo, .copy, .paste])

        #expect(EditorCommand.undo.title == "Undo")
        #expect(EditorCommand.undo.systemImage == "arrow.uturn.backward")

        #expect(EditorCommand.copy.title == "Copy")
        #expect(EditorCommand.copy.systemImage == "doc.on.doc")

        #expect(EditorCommand.paste.title == "Paste")
        #expect(EditorCommand.paste.systemImage == "doc.on.clipboard")
    }

    @Test func appKitPerformerDispatchesStandardResponderActions() {
        let sender = SpyActionSender()
        let performer = AppKitEditorCommandPerformer(actionSender: sender)

        _ = performer.perform(.undo)
        _ = performer.perform(.copy)
        _ = performer.perform(.paste)

        #expect(sender.sentActions.map(\.selectorName) == [
            "undo:",
            "copy:",
            "paste:",
        ])
        #expect(sender.sentActions.allSatisfy { $0.target == nil })
        #expect(sender.sentActions.allSatisfy { $0.sender == nil })
    }
}

private final class SpyActionSender: AppKitActionSending {
    private(set) var sentActions: [SentAction] = []

    func sendAction(_ action: Selector, to target: Any?, from sender: Any?) -> Bool {
        sentActions.append(SentAction(action: action, target: target, sender: sender))
        return true
    }
}

private struct SentAction {
    let action: Selector
    let target: Any?
    let sender: Any?

    var selectorName: String {
        NSStringFromSelector(action)
    }
}

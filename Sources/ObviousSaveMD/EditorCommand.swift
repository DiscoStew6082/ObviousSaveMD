import AppKit

@MainActor
protocol AppKitActionSending {
    @discardableResult
    func sendAction(_ action: Selector, to target: Any?, from sender: Any?) -> Bool
}

extension NSApplication: AppKitActionSending {}

enum EditorCommand: Hashable {
    case undo
    case copy
    case paste

    static let toolbarCommands: [EditorCommand] = [.undo, .copy, .paste]

    var title: String {
        switch self {
        case .undo:
            return "Undo"
        case .copy:
            return "Copy"
        case .paste:
            return "Paste"
        }
    }

    var systemImage: String {
        switch self {
        case .undo:
            return "arrow.uturn.backward"
        case .copy:
            return "doc.on.doc"
        case .paste:
            return "doc.on.clipboard"
        }
    }

    var appKitSelector: Selector {
        switch self {
        case .undo:
            return Selector(("undo:"))
        case .copy:
            return #selector(NSText.copy(_:))
        case .paste:
            return #selector(NSText.paste(_:))
        }
    }
}

@MainActor
protocol EditorCommandPerforming {
    @discardableResult
    func perform(_ command: EditorCommand) -> Bool
}

struct AppKitEditorCommandPerformer: EditorCommandPerforming {
    private let actionSender: AppKitActionSending

    init(actionSender: AppKitActionSending = NSApp) {
        self.actionSender = actionSender
    }

    @discardableResult
    func perform(_ command: EditorCommand) -> Bool {
        actionSender.sendAction(command.appKitSelector, to: nil, from: nil)
    }
}

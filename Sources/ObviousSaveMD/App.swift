import SwiftUI
import ObviousSaveMDCore

@main
struct ObviousSaveMDApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            EditorCommands()
        }
    }
}

private struct EditorCommands: Commands {
    @FocusedObject private var controller: DocumentController?

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open...") {
                controller?.open()
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(controller == nil)
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                controller?.save()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(controller?.canSave != true)

            Button("Save As...") {
                controller?.saveAs()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(controller == nil)
        }
    }
}

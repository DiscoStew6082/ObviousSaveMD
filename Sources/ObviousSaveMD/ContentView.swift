import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ObviousSaveMDCore

struct ContentView: View {
    @StateObject private var controller: DocumentController
    @StateObject private var closeHandler = WindowCloseHandler()

    init(controller: DocumentController = DocumentController(
        fileIO: UTF8TextFileIO(),
        dialogs: AppKitFileDialogs(),
        prompt: AppKitUnsavedChangesPrompt()
    )) {
        _controller = StateObject(wrappedValue: controller)
    }

    var body: some View {
        VStack(spacing: 0) {
            MarkdownTextView(text: Binding(
                get: { controller.content },
                set: { controller.replaceContentFromEditor($0) }
            ))
            .frame(minWidth: 700, minHeight: 460)

            Divider()

            statusBar
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task {
                        await controller.open()
                    }
                } label: {
                    Label("Open", systemImage: "folder")
                        .labelStyle(.titleAndIcon)
                }
                .keyboardShortcut("o", modifiers: .command)
                .help("Open")

                Button {
                    controller.save()
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                        .labelStyle(.titleAndIcon)
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!controller.canSave)
                .help("Save")

                Button {
                    controller.saveAs()
                } label: {
                    Label("Save As", systemImage: "square.and.arrow.down.on.square")
                        .labelStyle(.titleAndIcon)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .help("Save As")
            }
        }
        .background(windowAccessor)
        .focusedSceneObject(controller)
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            Text(controller.displayFileName)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)

            Text(controller.filePathDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 12)

            if let error = controller.lastErrorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Label {
                Text(controller.saveStatus)
                    .font(.caption.weight(.semibold))
            } icon: {
                Image(systemName: controller.isDirty ? "circle.fill" : "checkmark.circle.fill")
                    .imageScale(.small)
            }
            .labelStyle(.titleAndIcon)
            .foregroundStyle(controller.isDirty ? .orange : .green)
            .accessibilityLabel(controller.saveStatus)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
    }

    private var windowAccessor: some View {
        WindowAccessor(
            title: controller.windowTitle,
            isDocumentEdited: controller.isDirty,
            closeHandler: closeHandler,
            shouldClose: { [weak controller] in
                controller?.requestClose() ?? true
            }
        )
        .frame(width: 0, height: 0)
    }
}

enum EditableDocumentContentTypes {
    private static let allowedExtensions = Set(["md", "markdown", "txt", "text"])

    static let allowedContentTypes: [UTType] = [
        UTType(filenameExtension: "md", conformingTo: .plainText),
        UTType(filenameExtension: "markdown", conformingTo: .plainText),
        UTType(filenameExtension: "txt", conformingTo: .plainText),
        .plainText,
    ].compactMap { $0 }

    static func allowsFileName(_ fileName: String) -> Bool {
        allowedExtensions.contains(URL(fileURLWithPath: fileName).pathExtension.lowercased())
    }
}

private final class AppKitFileDialogs: FileDialoging {
    func chooseOpenURL() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Open Markdown or Text"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = EditableDocumentContentTypes.allowedContentTypes
        return panel.runModal() == .OK ? panel.url : nil
    }

    func chooseSaveURL(suggestedFileName: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = "Save Markdown"
        panel.nameFieldStringValue = suggestedFileName
        return panel.runModal() == .OK ? panel.url : nil
    }
}

private struct AppKitUnsavedChangesPrompt: UnsavedChangesPrompting {
    func promptForUnsavedChanges(fileName: String) -> UnsavedChangesDecision {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Save changes to \(fileName)?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .save
        case .alertSecondButtonReturn:
            return .discard
        default:
            return .cancel
        }
    }
}

private final class WindowCloseHandler: NSObject, ObservableObject, NSWindowDelegate {
    var shouldClose: (() -> Bool)?

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        shouldClose?() ?? true
    }
}

private struct WindowAccessor: NSViewRepresentable {
    let title: String
    let isDocumentEdited: Bool
    let closeHandler: WindowCloseHandler
    let shouldClose: () -> Bool

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ view: NSView, context: Context) {
        closeHandler.shouldClose = shouldClose

        DispatchQueue.main.async {
            guard let window = view.window else {
                return
            }

            if window.delegate !== closeHandler {
                window.delegate = closeHandler
            }

            window.title = title
            window.isDocumentEdited = isDocumentEdited
        }
    }
}

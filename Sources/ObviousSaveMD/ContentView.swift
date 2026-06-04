import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ObviousSaveMDCore

struct ContentView: View {
    @StateObject private var controller: DocumentController
    @StateObject private var closeHandler = WindowCloseHandler()
    private let editorCommandPerformer: EditorCommandPerforming

    init(controller: DocumentController = DocumentController(
        fileIO: UTF8TextFileIO(),
        dialogs: AppKitFileDialogs(),
        prompt: AppKitUnsavedChangesPrompt()
    ), editorCommandPerformer: EditorCommandPerforming = AppKitEditorCommandPerformer()) {
        _controller = StateObject(wrappedValue: controller)
        self.editorCommandPerformer = editorCommandPerformer
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
                ForEach(EditorCommand.toolbarCommands, id: \.self) { command in
                    editorCommandButton(command)
                }
            }

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

    private func editorCommandButton(_ command: EditorCommand) -> some View {
        Button {
            editorCommandPerformer.perform(command)
        } label: {
            Label(command.title, systemImage: command.systemImage)
                .labelStyle(.titleAndIcon)
        }
        .help(command.title)
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

enum OpenPanelDirectoryPath {
    static func resolve(_ rawPath: String, fileManager: FileManager = .default) -> URL? {
        let trimmedPath = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            return nil
        }

        let unquotedPath = trimmedPath.removingMatchingSurroundingQuotes()
        let directoryURL: URL
        if unquotedPath.lowercased().hasPrefix("file://"),
           let fileURL = URL(string: unquotedPath),
           fileURL.isFileURL {
            directoryURL = fileURL
        } else {
            let expandedPath = (unquotedPath as NSString).expandingTildeInPath
            guard expandedPath.hasPrefix("/") else {
                return nil
            }

            directoryURL = URL(fileURLWithPath: expandedPath, isDirectory: true)
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }

        return directoryURL.standardizedFileURL
    }
}

enum OpenPanelConfiguration {
    @MainActor
    static func configure(_ panel: NSOpenPanel) {
        panel.title = "Open Markdown or Text"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = EditableDocumentContentTypes.allowedContentTypes
        panel.accessoryView = OpenPanelPathAccessoryView(panel: panel)
        panel.isAccessoryViewDisclosed = true
    }
}

private final class AppKitFileDialogs: FileDialoging {
    func chooseOpenURL() -> URL? {
        let panel = NSOpenPanel()
        OpenPanelConfiguration.configure(panel)
        return panel.runModal() == .OK ? panel.url : nil
    }

    func chooseSaveURL(suggestedFileName: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = "Save Markdown"
        panel.nameFieldStringValue = suggestedFileName
        return panel.runModal() == .OK ? panel.url : nil
    }
}

private final class OpenPanelPathAccessoryView: NSView {
    private weak var panel: NSOpenPanel?
    private let pathField = NSTextField()
    private let statusLabel = NSTextField(labelWithString: "")

    init(panel: NSOpenPanel) {
        self.panel = panel
        super.init(frame: NSRect(x: 0, y: 0, width: 420, height: 56))
        configureView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func configureView() {
        pathField.placeholderString = "Folder path"
        pathField.target = self
        pathField.action = #selector(goToDirectory)
        pathField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let goButton = NSButton(title: "Go", target: self, action: #selector(goToDirectory))
        goButton.bezelStyle = .rounded
        goButton.setContentHuggingPriority(.required, for: .horizontal)

        let row = NSStackView(views: [pathField, goButton])
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY

        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingMiddle

        let stack = NSStackView(views: [row, statusLabel])
        stack.orientation = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            pathField.widthAnchor.constraint(greaterThanOrEqualToConstant: 300),
        ])
    }

    @objc private func goToDirectory() {
        guard let directoryURL = OpenPanelDirectoryPath.resolve(pathField.stringValue) else {
            statusLabel.stringValue = "Folder not found"
            NSSound.beep()
            return
        }

        panel?.directoryURL = directoryURL
        statusLabel.stringValue = directoryURL.path
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

private extension String {
    func removingMatchingSurroundingQuotes() -> String {
        guard count >= 2 else {
            return self
        }

        let quotePairs: [(Character, Character)] = [("\"", "\""), ("'", "'")]
        guard quotePairs.contains(where: { hasPrefix(String($0.0)) && hasSuffix(String($0.1)) }) else {
            return self
        }

        return String(dropFirst().dropLast())
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

import AppKit
import Testing
@testable import ObviousSaveMD

@Suite("MarkdownTextView")
@MainActor
struct MarkdownTextViewTests {
    @Test func editorWrapsLinesAndScrollsVertically() throws {
        let scrollView = MarkdownTextView.makeConfiguredScrollView(text: "A very long markdown line")

        #expect(scrollView.hasVerticalScroller)
        #expect(!scrollView.hasHorizontalScroller)
        #expect(!scrollView.autohidesScrollers)
        #expect(scrollView.scrollerStyle == .legacy)

        let textView = try #require(scrollView.documentView as? NSTextView)
        #expect(!textView.isHorizontallyResizable)
        #expect(textView.textContainer?.widthTracksTextView == true)
        #expect(textView.textContainer?.heightTracksTextView == false)
    }

    @Test func openDialogDocumentTypesAllowMarkdownAndPlainTextOnly() {
        #expect(EditableDocumentContentTypes.allowsFileName("notes.md"))
        #expect(EditableDocumentContentTypes.allowsFileName("notes.markdown"))
        #expect(EditableDocumentContentTypes.allowsFileName("notes.txt"))
        #expect(!EditableDocumentContentTypes.allowsFileName("photo.png"))
        #expect(!EditableDocumentContentTypes.allowsFileName("archive.zip"))
    }

    @Test func openDialogPathEntryResolvesExplicitExistingDirectories() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let resolvedPath = OpenPanelDirectoryPath.resolve(directory.path)
        let resolvedFileURL = OpenPanelDirectoryPath.resolve(directory.absoluteString)

        #expect(resolvedPath?.path == directory.standardizedFileURL.path)
        #expect(resolvedFileURL?.path == directory.standardizedFileURL.path)
    }

    @Test func openDialogPathEntryRejectsMissingPathsAndFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let fileURL = directory.appendingPathComponent("notes.md")
        try "# Notes".write(to: fileURL, atomically: true, encoding: .utf8)

        #expect(OpenPanelDirectoryPath.resolve("") == nil)
        #expect(OpenPanelDirectoryPath.resolve("/definitely/not/a/real/folder") == nil)
        #expect(OpenPanelDirectoryPath.resolve(fileURL.path) == nil)
    }

    @Test func openDialogConfigurationShowsPathEntryAccessory() {
        let panel = NSOpenPanel()

        OpenPanelConfiguration.configure(panel)

        #expect(panel.accessoryView != nil)
        #expect(panel.isAccessoryViewDisclosed)
        #expect(!panel.canChooseDirectories)
        #expect(panel.canChooseFiles)
    }

    @Test func openDialogPathEntryAccessoryKeepsControlsInsetAndSeparated() throws {
        let panel = NSOpenPanel()
        OpenPanelConfiguration.configure(panel)
        let accessory = try #require(panel.accessoryView)
        accessory.frame = NSRect(x: 0, y: 0, width: 520, height: 72)

        accessory.layoutSubtreeIfNeeded()

        let pathField = try #require(accessory.descendantTextField(placeholder: "Folder path"))
        let goButton = try #require(accessory.descendantButton(title: "Go"))
        let pathFrame = pathField.convert(pathField.bounds, to: accessory)
        let buttonFrame = goButton.convert(goButton.bounds, to: accessory)

        #expect(pathFrame.minX >= 12)
        #expect(accessory.bounds.maxX - buttonFrame.maxX >= 12)
        #expect(buttonFrame.minX - pathFrame.maxX >= 10)
        #expect(pathFrame.minY >= 8)
    }
}

private extension NSView {
    func descendantTextField(placeholder: String) -> NSTextField? {
        if let textField = self as? NSTextField,
           textField.placeholderString == placeholder {
            return textField
        }

        for subview in subviews {
            if let textField = subview.descendantTextField(placeholder: placeholder) {
                return textField
            }
        }

        return nil
    }

    func descendantButton(title: String) -> NSButton? {
        if let button = self as? NSButton,
           button.title == title {
            return button
        }

        for subview in subviews {
            if let button = subview.descendantButton(title: title) {
                return button
            }
        }

        return nil
    }
}

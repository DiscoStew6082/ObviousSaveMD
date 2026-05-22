import Foundation
import Testing
@testable import ObviousSaveMDCore

@Suite("DocumentController")
@MainActor
struct DocumentControllerTests {
    @Test func editingUntitledDocumentMarksItDirty() {
        let controller = DocumentController()

        controller.replaceContentFromEditor("# Hello")

        #expect(controller.content == "# Hello")
        #expect(controller.fileURL == nil)
        #expect(controller.isDirty)
    }

    @Test func saveUntitledDocumentRoutesThroughSaveAs() {
        let saveURL = URL(fileURLWithPath: "/tmp/notes.md")
        let fileIO = FakeTextFileIO()
        let dialogs = FakeFileDialogs(saveURL: saveURL)
        let controller = DocumentController(fileIO: fileIO, dialogs: dialogs, prompt: FakeUnsavedChangesPrompt())
        controller.replaceContentFromEditor("# Hello")

        let didSave = controller.save()

        #expect(didSave)
        #expect(dialogs.saveURLRequestCount == 1)
        #expect(fileIO.writes == [TextWrite(text: "# Hello", url: saveURL)])
        #expect(controller.fileURL == saveURL)
        #expect(!controller.isDirty)
    }

    @Test func saveExistingDocumentWritesToExistingURLWithoutPromptingForLocation() {
        let existingURL = URL(fileURLWithPath: "/tmp/existing.md")
        let fileIO = FakeTextFileIO()
        let dialogs = FakeFileDialogs(saveURL: URL(fileURLWithPath: "/tmp/other.md"))
        let controller = DocumentController(
            content: "Updated",
            fileURL: existingURL,
            isDirty: true,
            fileIO: fileIO,
            dialogs: dialogs,
            prompt: FakeUnsavedChangesPrompt()
        )

        let didSave = controller.save()

        #expect(didSave)
        #expect(dialogs.saveURLRequestCount == 0)
        #expect(fileIO.writes == [TextWrite(text: "Updated", url: existingURL)])
        #expect(controller.fileURL == existingURL)
        #expect(!controller.isDirty)
    }

    @Test func cancelledSaveAsLeavesUntitledDocumentDirty() {
        let fileIO = FakeTextFileIO()
        let dialogs = FakeFileDialogs(saveURL: nil)
        let controller = DocumentController(fileIO: fileIO, dialogs: dialogs, prompt: FakeUnsavedChangesPrompt())
        controller.replaceContentFromEditor("Draft")

        let didSave = controller.save()

        #expect(!didSave)
        #expect(dialogs.saveURLRequestCount == 1)
        #expect(fileIO.writes.isEmpty)
        #expect(controller.fileURL == nil)
        #expect(controller.isDirty)
    }

    @Test func openingCleanDocumentLoadsUtf8ContentAndClearsDirtyState() {
        let openURL = URL(fileURLWithPath: "/tmp/open.md")
        let fileIO = FakeTextFileIO(reads: [openURL: "# Opened"])
        let dialogs = FakeFileDialogs(openURL: openURL)
        let controller = DocumentController(fileIO: fileIO, dialogs: dialogs, prompt: FakeUnsavedChangesPrompt())

        let didOpen = controller.open()

        #expect(didOpen)
        #expect(dialogs.openURLRequestCount == 1)
        #expect(controller.content == "# Opened")
        #expect(controller.fileURL == openURL)
        #expect(!controller.isDirty)
    }

    @Test func openingDirtyDocumentCancelPreservesCurrentDocument() {
        let openURL = URL(fileURLWithPath: "/tmp/replacement.md")
        let fileIO = FakeTextFileIO(reads: [openURL: "Replacement"])
        let dialogs = FakeFileDialogs(openURL: openURL)
        let prompt = FakeUnsavedChangesPrompt(decision: .cancel)
        let controller = DocumentController(
            content: "Draft",
            fileURL: nil,
            isDirty: true,
            fileIO: fileIO,
            dialogs: dialogs,
            prompt: prompt
        )

        let didOpen = controller.open()

        #expect(!didOpen)
        #expect(prompt.requestCount == 1)
        #expect(dialogs.openURLRequestCount == 0)
        #expect(controller.content == "Draft")
        #expect(controller.fileURL == nil)
        #expect(controller.isDirty)
    }

    @Test func openingDirtyDocumentDontSaveDiscardsAndLoadsSelectedFile() {
        let openURL = URL(fileURLWithPath: "/tmp/replacement.md")
        let fileIO = FakeTextFileIO(reads: [openURL: "Replacement"])
        let dialogs = FakeFileDialogs(openURL: openURL)
        let prompt = FakeUnsavedChangesPrompt(decision: .discard)
        let controller = DocumentController(
            content: "Draft",
            fileURL: nil,
            isDirty: true,
            fileIO: fileIO,
            dialogs: dialogs,
            prompt: prompt
        )

        let didOpen = controller.open()

        #expect(didOpen)
        #expect(prompt.requestCount == 1)
        #expect(dialogs.openURLRequestCount == 1)
        #expect(controller.content == "Replacement")
        #expect(controller.fileURL == openURL)
        #expect(!controller.isDirty)
    }

    @Test func openingDirtyDocumentSaveWritesCurrentFileThenLoadsSelectedFile() {
        let currentURL = URL(fileURLWithPath: "/tmp/current.md")
        let openURL = URL(fileURLWithPath: "/tmp/replacement.md")
        let fileIO = FakeTextFileIO(reads: [openURL: "Replacement"])
        let dialogs = FakeFileDialogs(openURL: openURL)
        let prompt = FakeUnsavedChangesPrompt(decision: .save)
        let controller = DocumentController(
            content: "Draft",
            fileURL: currentURL,
            isDirty: true,
            fileIO: fileIO,
            dialogs: dialogs,
            prompt: prompt
        )

        let didOpen = controller.open()

        #expect(didOpen)
        #expect(prompt.requestCount == 1)
        #expect(fileIO.writes == [TextWrite(text: "Draft", url: currentURL)])
        #expect(controller.content == "Replacement")
        #expect(controller.fileURL == openURL)
        #expect(!controller.isDirty)
    }

    @Test func closingDirtyDocumentCancelKeepsWindowOpenAndPreservesDocument() {
        let prompt = FakeUnsavedChangesPrompt(decision: .cancel)
        let controller = DocumentController(
            content: "Draft",
            fileURL: nil,
            isDirty: true,
            fileIO: FakeTextFileIO(),
            dialogs: FakeFileDialogs(),
            prompt: prompt
        )

        let shouldClose = controller.requestClose()

        #expect(!shouldClose)
        #expect(prompt.requestCount == 1)
        #expect(controller.content == "Draft")
        #expect(controller.fileURL == nil)
        #expect(controller.isDirty)
    }

    @Test func closingDirtyDocumentDontSaveAllowsCloseWithoutWriting() {
        let fileIO = FakeTextFileIO()
        let prompt = FakeUnsavedChangesPrompt(decision: .discard)
        let controller = DocumentController(
            content: "Draft",
            fileURL: URL(fileURLWithPath: "/tmp/close.md"),
            isDirty: true,
            fileIO: fileIO,
            dialogs: FakeFileDialogs(),
            prompt: prompt
        )

        let shouldClose = controller.requestClose()

        #expect(shouldClose)
        #expect(prompt.requestCount == 1)
        #expect(fileIO.writes.isEmpty)
    }

    @Test func closingDirtyDocumentSaveWritesThenAllowsClose() {
        let existingURL = URL(fileURLWithPath: "/tmp/close.md")
        let fileIO = FakeTextFileIO()
        let prompt = FakeUnsavedChangesPrompt(decision: .save)
        let controller = DocumentController(
            content: "Draft",
            fileURL: existingURL,
            isDirty: true,
            fileIO: fileIO,
            dialogs: FakeFileDialogs(),
            prompt: prompt
        )

        let shouldClose = controller.requestClose()

        #expect(shouldClose)
        #expect(prompt.requestCount == 1)
        #expect(fileIO.writes == [TextWrite(text: "Draft", url: existingURL)])
        #expect(!controller.isDirty)
    }

    @Test func closingDirtyUntitledDocumentSaveAsCancelKeepsWindowOpen() {
        let fileIO = FakeTextFileIO()
        let prompt = FakeUnsavedChangesPrompt(decision: .save)
        let controller = DocumentController(
            content: "Draft",
            fileURL: nil,
            isDirty: true,
            fileIO: fileIO,
            dialogs: FakeFileDialogs(saveURL: nil),
            prompt: prompt
        )

        let shouldClose = controller.requestClose()

        #expect(!shouldClose)
        #expect(prompt.requestCount == 1)
        #expect(fileIO.writes.isEmpty)
        #expect(controller.fileURL == nil)
        #expect(controller.isDirty)
    }

    @Test func closingDirtyUntitledDocumentSaveAsWritesThenAllowsClose() {
        let saveURL = URL(fileURLWithPath: "/tmp/saved.md")
        let fileIO = FakeTextFileIO()
        let prompt = FakeUnsavedChangesPrompt(decision: .save)
        let controller = DocumentController(
            content: "Draft",
            fileURL: nil,
            isDirty: true,
            fileIO: fileIO,
            dialogs: FakeFileDialogs(saveURL: saveURL),
            prompt: prompt
        )

        let shouldClose = controller.requestClose()

        #expect(shouldClose)
        #expect(prompt.requestCount == 1)
        #expect(fileIO.writes == [TextWrite(text: "Draft", url: saveURL)])
        #expect(controller.fileURL == saveURL)
        #expect(!controller.isDirty)
    }

    @Test func saveIsDisabledOnlyWhenThereIsNoOpenFileAndNoContent() {
        let freshUntitled = DocumentController()
        let untitledWithContent = DocumentController(content: "Draft")
        let openedEmptyFile = DocumentController(fileURL: URL(fileURLWithPath: "/tmp/empty.md"))

        #expect(!freshUntitled.canSave)
        #expect(untitledWithContent.canSave)
        #expect(openedEmptyFile.canSave)
    }

    @Test func utf8FileIOPreservesNonAsciiMarkdown() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let url = directory.appendingPathComponent("notes.md")
        let text = "# Café\nnaïve façade\nこんにちは"
        let fileIO = UTF8TextFileIO()

        try fileIO.writeText(text, to: url)
        let loadedText = try fileIO.readText(from: url)

        #expect(loadedText == text)
    }
}

private struct TextWrite: Equatable {
    let text: String
    let url: URL
}

private final class FakeTextFileIO: TextFileIO {
    private let reads: [URL: String]
    var writes: [TextWrite] = []

    init(reads: [URL: String] = [:]) {
        self.reads = reads
    }

    func readText(from url: URL) throws -> String {
        reads[url] ?? ""
    }

    func writeText(_ text: String, to url: URL) throws {
        writes.append(TextWrite(text: text, url: url))
    }
}

private final class FakeFileDialogs: FileDialoging {
    private let openURL: URL?
    private let saveURL: URL?
    var openURLRequestCount = 0
    var saveURLRequestCount = 0

    init(openURL: URL? = nil, saveURL: URL? = nil) {
        self.openURL = openURL
        self.saveURL = saveURL
    }

    func chooseOpenURL() -> URL? {
        openURLRequestCount += 1
        return openURL
    }

    func chooseSaveURL(suggestedFileName: String) -> URL? {
        saveURLRequestCount += 1
        return saveURL
    }
}

private final class FakeUnsavedChangesPrompt: UnsavedChangesPrompting {
    private let decision: UnsavedChangesDecision
    var requestCount = 0

    init(decision: UnsavedChangesDecision = .cancel) {
        self.decision = decision
    }

    func promptForUnsavedChanges(fileName: String) -> UnsavedChangesDecision {
        requestCount += 1
        return decision
    }
}

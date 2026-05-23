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

    @Test func openingCleanDocumentLoadsUtf8ContentAndClearsDirtyState() async {
        let openURL = URL(fileURLWithPath: "/tmp/open.md")
        let fileIO = FakeTextFileIO(reads: [openURL: "# Opened"])
        let dialogs = FakeFileDialogs(openURL: openURL)
        let controller = DocumentController(fileIO: fileIO, dialogs: dialogs, prompt: FakeUnsavedChangesPrompt())

        let didOpen = await controller.open()

        #expect(didOpen)
        #expect(dialogs.openURLRequestCount == 1)
        #expect(controller.content == "# Opened")
        #expect(controller.fileURL == openURL)
        #expect(!controller.isDirty)
    }

    @Test func openingDirtyDocumentCancelPreservesCurrentDocument() async {
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

        let didOpen = await controller.open()

        #expect(!didOpen)
        #expect(prompt.requestCount == 1)
        #expect(dialogs.openURLRequestCount == 0)
        #expect(controller.content == "Draft")
        #expect(controller.fileURL == nil)
        #expect(controller.isDirty)
    }

    @Test func openingDirtyDocumentDontSaveDiscardsAndLoadsSelectedFile() async {
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

        let didOpen = await controller.open()

        #expect(didOpen)
        #expect(prompt.requestCount == 1)
        #expect(dialogs.openURLRequestCount == 1)
        #expect(controller.content == "Replacement")
        #expect(controller.fileURL == openURL)
        #expect(!controller.isDirty)
    }

    @Test func openingDirtyDocumentSaveWritesCurrentFileThenLoadsSelectedFile() async {
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

        let didOpen = await controller.open()

        #expect(didOpen)
        #expect(prompt.requestCount == 1)
        #expect(fileIO.writes == [TextWrite(text: "Draft", url: currentURL)])
        #expect(controller.content == "Replacement")
        #expect(controller.fileURL == openURL)
        #expect(!controller.isDirty)
    }

    @Test func failedOpenPreservesCurrentDocumentAndReportsError() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let currentURL = directory.appendingPathComponent("current.md")
        let oversizedURL = directory.appendingPathComponent("oversized.md")
        try "12345".write(to: oversizedURL, atomically: true, encoding: .utf8)
        let dialogs = FakeFileDialogs(openURL: oversizedURL)
        let controller = DocumentController(
            content: "Current",
            fileURL: currentURL,
            isDirty: false,
            fileIO: UTF8TextFileIO(maximumReadableBytes: 4),
            dialogs: dialogs,
            prompt: FakeUnsavedChangesPrompt()
        )

        let didOpen = await controller.open()

        #expect(!didOpen)
        #expect(controller.content == "Current")
        #expect(controller.fileURL == currentURL)
        #expect(!controller.isDirty)
        #expect(controller.lastErrorMessage != nil)
    }

    @Test func delayedOpenDoesNotReplaceDocumentChangedDuringRead() async {
        let currentURL = URL(fileURLWithPath: "/tmp/current.md")
        let replacementURL = URL(fileURLWithPath: "/tmp/replacement.md")
        let fileIO = SuspendingTextFileIO()
        let dialogs = FakeFileDialogs(openURL: replacementURL)
        let controller = DocumentController(
            content: "Current",
            fileURL: currentURL,
            isDirty: false,
            fileIO: fileIO,
            dialogs: dialogs,
            prompt: FakeUnsavedChangesPrompt()
        )

        let openTask = Task {
            await controller.open()
        }
        await fileIO.waitUntilReadStarted()

        controller.replaceContentFromEditor("User edit")
        await fileIO.finishRead(with: "Replacement")
        let didOpen = await openTask.value

        #expect(!didOpen)
        #expect(controller.content == "User edit")
        #expect(controller.fileURL == currentURL)
        #expect(controller.isDirty)
        #expect(controller.lastErrorMessage != nil)
    }

    @Test func olderDelayedOpenDoesNotReplaceAfterNewerCancelledOpen() async {
        let currentURL = URL(fileURLWithPath: "/tmp/current.md")
        let firstURL = URL(fileURLWithPath: "/tmp/first.md")
        let firstRead = SuspendingTextFileIO()
        let dialogs = FakeFileDialogs(openURLs: [firstURL, nil])
        let controller = DocumentController(
            content: "Current",
            fileURL: currentURL,
            isDirty: false,
            fileIO: firstRead,
            dialogs: dialogs,
            prompt: FakeUnsavedChangesPrompt()
        )

        let firstOpenTask = Task {
            await controller.open()
        }
        await firstRead.waitUntilReadStarted()

        let didSecondOpen = await controller.open()
        await firstRead.finishRead(with: "First")
        let didFirstOpen = await firstOpenTask.value

        #expect(!didSecondOpen)
        #expect(!didFirstOpen)
        #expect(controller.content == "Current")
        #expect(controller.fileURL == currentURL)
        #expect(!controller.isDirty)
    }

    @Test func staleFailedOpenDoesNotReplaceCurrentErrorMessage() async {
        let firstURL = URL(fileURLWithPath: "/tmp/first.md")
        let secondURL = URL(fileURLWithPath: "/tmp/second.md")
        let fileIO = FirstReadSuspendsThenTextFileIO(secondText: "Second")
        let dialogs = FakeFileDialogs(openURLs: [firstURL, secondURL])
        let controller = DocumentController(
            fileIO: fileIO,
            dialogs: dialogs,
            prompt: FakeUnsavedChangesPrompt()
        )

        let firstOpenTask = Task {
            await controller.open()
        }
        await fileIO.waitUntilFirstReadStarted()
        let didSecondOpen = await controller.open()

        await fileIO.failFirstRead(with: UTF8TextFileIOError.invalidUTF8)
        let didFirstOpen = await firstOpenTask.value

        #expect(didSecondOpen)
        #expect(!didFirstOpen)
        #expect(controller.content == "Second")
        #expect(controller.fileURL == secondURL)
        #expect(!controller.isDirty)
        #expect(controller.lastErrorMessage == nil)
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

    @Test func modifiedDocumentDisplaysExplicitModifiedIndicator() {
        let clean = DocumentController(fileURL: URL(fileURLWithPath: "/tmp/notes.md"))
        let dirty = DocumentController(
            content: "Draft",
            fileURL: URL(fileURLWithPath: "/tmp/notes.md"),
            isDirty: true
        )

        #expect(clean.displayFileName == "notes.md")
        #expect(clean.saveStatus == "Saved")
        #expect(clean.windowTitle == "notes.md - Saved")

        #expect(dirty.displayFileName == "* notes.md")
        #expect(dirty.saveStatus == "Modified")
        #expect(dirty.windowTitle == "* notes.md - Modified")
    }

    @Test func utf8FileIOPreservesNonAsciiMarkdown() async throws {
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
        let loadedText = try await fileIO.readText(from: url)

        #expect(loadedText == text)
    }

    @Test func utf8FileIORejectsNonRegularFilesBeforeReading() async throws {
        let fileIO = UTF8TextFileIO()

        let error = await captureUTF8TextFileIOError {
            _ = try await fileIO.readText(from: URL(fileURLWithPath: "/dev/null"))
        }

        #expect(error == .unsupportedFileType)
    }

    @Test func utf8FileIORejectsNamedPipesWithoutBlocking() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let fifoURL = directory.appendingPathComponent("pipe.md")
        fifoURL.withUnsafeFileSystemRepresentation { fileSystemPath in
            #expect(fileSystemPath != nil)
            guard let fileSystemPath else {
                return
            }

            #expect(mkfifo(fileSystemPath, S_IRUSR | S_IWUSR) == 0)
        }
        let fileIO = UTF8TextFileIO()

        let error = await captureUTF8TextFileIOError {
            _ = try await fileIO.readText(from: fifoURL)
        }

        #expect(error == .unsupportedFileType)
    }

    @Test func utf8FileIORejectsFilesOverConfiguredSizeLimit() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let url = directory.appendingPathComponent("oversized.md")
        try "12345".write(to: url, atomically: true, encoding: .utf8)
        let fileIO = UTF8TextFileIO(maximumReadableBytes: 4)

        let error = await captureUTF8TextFileIOError {
            _ = try await fileIO.readText(from: url)
        }

        #expect(error == .fileTooLarge(actualBytes: 5, maximumBytes: 4))
    }

    @Test func utf8FileIORejectsNulBytesBeforeLoadingIntoEditor() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let url = directory.appendingPathComponent("binary.md")
        try Data([0x23, 0x20, 0x54, 0x69, 0x74, 0x6c, 0x65, 0x00]).write(to: url)
        let fileIO = UTF8TextFileIO()

        let error = await captureUTF8TextFileIOError {
            _ = try await fileIO.readText(from: url)
        }

        #expect(error == .binaryContent)
    }

    @Test func utf8FileIORejectsInvalidUTF8BeforeLoadingIntoEditor() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let url = directory.appendingPathComponent("invalid.md")
        try Data([0xff]).write(to: url)
        let fileIO = UTF8TextFileIO()

        let error = await captureUTF8TextFileIOError {
            _ = try await fileIO.readText(from: url)
        }

        #expect(error == .invalidUTF8)
    }

    @Test func utf8FileIORejectsSymbolicLinksForReading() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let targetURL = directory.appendingPathComponent("target.md")
        let linkURL = directory.appendingPathComponent("link.md")
        try "# Target".write(to: targetURL, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: targetURL)
        let fileIO = UTF8TextFileIO()

        let error = await captureUTF8TextFileIOError {
            _ = try await fileIO.readText(from: linkURL)
        }

        #expect(error == .unsupportedFileType)
    }

    @Test func utf8FileIORejectsSymbolicLinksForWriting() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let targetURL = directory.appendingPathComponent("target.md")
        let linkURL = directory.appendingPathComponent("link.md")
        try "Original".write(to: targetURL, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: targetURL)
        let fileIO = UTF8TextFileIO()

        let error = await captureUTF8TextFileIOError {
            try fileIO.writeText("Replacement", to: linkURL)
        }

        #expect(error == .unsupportedFileType)
        #expect(try String(contentsOf: targetURL, encoding: .utf8) == "Original")
    }
}

@MainActor
private func captureUTF8TextFileIOError(_ operation: () async throws -> Void) async -> UTF8TextFileIOError? {
    do {
        try await operation()
        return nil
    } catch let error as UTF8TextFileIOError {
        return error
    } catch {
        return nil
    }
}

private struct TextWrite: Equatable {
    let text: String
    let url: URL
}

private final class FakeTextFileIO: TextFileIO, @unchecked Sendable {
    private let reads: [URL: String]
    var writes: [TextWrite] = []

    init(reads: [URL: String] = [:]) {
        self.reads = reads
    }

    func readText(from url: URL) async throws -> String {
        reads[url] ?? ""
    }

    func writeText(_ text: String, to url: URL) throws {
        writes.append(TextWrite(text: text, url: url))
    }
}

private final class SuspendingTextFileIO: TextFileIO, @unchecked Sendable {
    private let readGate = ReadGate()

    func readText(from url: URL) async throws -> String {
        try await readGate.read()
    }

    func writeText(_ text: String, to url: URL) throws {}

    func waitUntilReadStarted() async {
        await readGate.waitUntilReadStarted()
    }

    func finishRead(with text: String) async {
        await readGate.finishRead(with: text)
    }

    func failRead(with error: Error) async {
        await readGate.failRead(with: error)
    }
}

private final class FirstReadSuspendsThenTextFileIO: TextFileIO, @unchecked Sendable {
    private let readGate: SequencedReadGate

    init(secondText: String) {
        readGate = SequencedReadGate(secondText: secondText)
    }

    func readText(from url: URL) async throws -> String {
        try await readGate.read()
    }

    func writeText(_ text: String, to url: URL) throws {}

    func waitUntilFirstReadStarted() async {
        await readGate.waitUntilFirstReadStarted()
    }

    func failFirstRead(with error: Error) async {
        await readGate.failFirstRead(with: error)
    }
}

private actor ReadGate {
    private var readContinuation: CheckedContinuation<String, Error>?
    private var startedContinuation: CheckedContinuation<Void, Never>?

    func read() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            readContinuation = continuation
            startedContinuation?.resume()
            startedContinuation = nil
        }
    }

    func waitUntilReadStarted() async {
        guard readContinuation == nil else {
            return
        }

        await withCheckedContinuation { continuation in
            startedContinuation = continuation
        }
    }

    func finishRead(with text: String) {
        readContinuation?.resume(returning: text)
        readContinuation = nil
    }

    func failRead(with error: Error) {
        readContinuation?.resume(throwing: error)
        readContinuation = nil
    }
}

private actor SequencedReadGate {
    private let secondText: String
    private var readCount = 0
    private var firstReadContinuation: CheckedContinuation<String, Error>?
    private var firstReadStartedContinuation: CheckedContinuation<Void, Never>?

    init(secondText: String) {
        self.secondText = secondText
    }

    func read() async throws -> String {
        readCount += 1

        guard readCount == 1 else {
            return secondText
        }

        return try await withCheckedThrowingContinuation { continuation in
            firstReadContinuation = continuation
            firstReadStartedContinuation?.resume()
            firstReadStartedContinuation = nil
        }
    }

    func waitUntilFirstReadStarted() async {
        guard firstReadContinuation == nil else {
            return
        }

        await withCheckedContinuation { continuation in
            firstReadStartedContinuation = continuation
        }
    }

    func failFirstRead(with error: Error) {
        firstReadContinuation?.resume(throwing: error)
        firstReadContinuation = nil
    }
}

private final class FakeFileDialogs: FileDialoging {
    private var openURLs: [URL?]
    private let saveURL: URL?
    var openURLRequestCount = 0
    var saveURLRequestCount = 0

    init(openURL: URL? = nil, saveURL: URL? = nil) {
        self.openURLs = [openURL]
        self.saveURL = saveURL
    }

    init(openURLs: [URL?], saveURL: URL? = nil) {
        self.openURLs = openURLs
        self.saveURL = saveURL
    }

    func chooseOpenURL() -> URL? {
        openURLRequestCount += 1
        return openURLs.isEmpty ? nil : openURLs.removeFirst()
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

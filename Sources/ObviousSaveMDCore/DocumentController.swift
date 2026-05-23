import Foundation
import Combine

public enum UnsavedChangesDecision {
    case save
    case discard
    case cancel
}

public protocol TextFileIO: Sendable {
    func readText(from url: URL) async throws -> String
    func writeText(_ text: String, to url: URL) throws
}

@MainActor
public protocol FileDialoging {
    func chooseOpenURL() -> URL?
    func chooseSaveURL(suggestedFileName: String) -> URL?
}

@MainActor
public protocol UnsavedChangesPrompting {
    func promptForUnsavedChanges(fileName: String) -> UnsavedChangesDecision
}

@MainActor
public final class DocumentController: ObservableObject {
    @Published public private(set) var content: String
    @Published public private(set) var fileURL: URL?
    @Published public private(set) var isDirty: Bool
    @Published public private(set) var lastErrorMessage: String?

    private let fileIO: TextFileIO
    private let dialogs: FileDialoging
    private let prompt: UnsavedChangesPrompting
    private var openRequestGeneration = 0

    public init(
        content: String = "",
        fileURL: URL? = nil,
        isDirty: Bool = false,
        fileIO: TextFileIO = UnavailableTextFileIO(),
        dialogs: FileDialoging = EmptyFileDialogs(),
        prompt: UnsavedChangesPrompting = CancelingUnsavedChangesPrompt()
    ) {
        self.content = content
        self.fileURL = fileURL
        self.isDirty = isDirty
        self.fileIO = fileIO
        self.dialogs = dialogs
        self.prompt = prompt
    }

    public var canSave: Bool {
        fileURL != nil || !content.isEmpty
    }

    public var fileName: String {
        fileURL?.lastPathComponent ?? "Untitled"
    }

    public var displayFileName: String {
        isDirty ? "* \(fileName)" : fileName
    }

    public var filePathDescription: String {
        fileURL?.path ?? "No file selected"
    }

    public var saveStatus: String {
        isDirty ? "Modified" : "Saved"
    }

    public var windowTitle: String {
        "\(displayFileName) - \(saveStatus)"
    }

    public func replaceContentFromEditor(_ newContent: String) {
        guard newContent != content else {
            return
        }

        content = newContent
        isDirty = true
    }

    @discardableResult
    public func open() async -> Bool {
        openRequestGeneration += 1
        let currentOpenRequestGeneration = openRequestGeneration

        guard resolveUnsavedChangesBeforeReplacingDocument() else {
            return false
        }

        guard let selectedURL = dialogs.chooseOpenURL() else {
            return false
        }

        let documentSnapshot = DocumentSnapshot(
            content: content,
            fileURL: fileURL,
            isDirty: isDirty
        )

        do {
            let loadedContent = try await fileIO.readText(from: selectedURL)

            guard currentOpenRequestGeneration == openRequestGeneration else {
                return false
            }

            guard documentSnapshot.matches(content: content, fileURL: fileURL, isDirty: isDirty) else {
                lastErrorMessage = "The selected file was not opened because the current document changed."
                return false
            }

            content = loadedContent
            fileURL = selectedURL
            isDirty = false
            lastErrorMessage = nil
            return true
        } catch {
            guard currentOpenRequestGeneration == openRequestGeneration else {
                return false
            }

            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    public func save() -> Bool {
        guard let fileURL else {
            return saveAs()
        }

        return writeCurrentContent(to: fileURL, shouldUpdateFileURL: false)
    }

    @discardableResult
    public func saveAs() -> Bool {
        guard let selectedURL = dialogs.chooseSaveURL(suggestedFileName: suggestedFileName) else {
            return false
        }

        return writeCurrentContent(to: selectedURL, shouldUpdateFileURL: true)
    }

    @discardableResult
    public func requestClose() -> Bool {
        resolveUnsavedChangesBeforeReplacingDocument()
    }

    private var suggestedFileName: String {
        fileURL?.lastPathComponent ?? "Untitled.md"
    }

    private func resolveUnsavedChangesBeforeReplacingDocument() -> Bool {
        guard isDirty else {
            return true
        }

        switch prompt.promptForUnsavedChanges(fileName: fileName) {
        case .save:
            return save()
        case .discard:
            return true
        case .cancel:
            return false
        }
    }

    private func writeCurrentContent(to url: URL, shouldUpdateFileURL: Bool) -> Bool {
        do {
            try fileIO.writeText(content, to: url)
            if shouldUpdateFileURL {
                fileURL = url
            }
            isDirty = false
            lastErrorMessage = nil
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
    }
}

private struct DocumentSnapshot {
    let content: String
    let fileURL: URL?
    let isDirty: Bool

    func matches(content: String, fileURL: URL?, isDirty: Bool) -> Bool {
        self.content == content && self.fileURL == fileURL && self.isDirty == isDirty
    }
}

public struct UnavailableTextFileIO: TextFileIO {
    public init() {}

    public func readText(from url: URL) async throws -> String {
        throw CocoaError(.fileReadUnknown)
    }

    public func writeText(_ text: String, to url: URL) throws {
        throw CocoaError(.fileWriteUnknown)
    }
}

public struct EmptyFileDialogs: FileDialoging {
    public init() {}

    public func chooseOpenURL() -> URL? {
        nil
    }

    public func chooseSaveURL(suggestedFileName: String) -> URL? {
        nil
    }
}

public struct CancelingUnsavedChangesPrompt: UnsavedChangesPrompting {
    public init() {}

    public func promptForUnsavedChanges(fileName: String) -> UnsavedChangesDecision {
        .cancel
    }
}

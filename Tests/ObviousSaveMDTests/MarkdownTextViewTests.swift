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
}

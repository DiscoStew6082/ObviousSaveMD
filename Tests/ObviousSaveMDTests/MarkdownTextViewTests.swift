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

    @Test func pastingMultipleClipboardTextItemsInsertsEverySection() throws {
        let scrollView = MarkdownTextView.makeConfiguredScrollView(text: "")
        let textView = try #require(scrollView.documentView as? MarkdownEditorTextView)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()

        let overview = NSPasteboardItem()
        overview.setString("# Overview\nFirst section", forType: .string)
        let details = NSPasteboardItem()
        details.setString("## Details\nSecond section", forType: .string)

        #expect(pasteboard.writeObjects([overview, details]))
        #expect(textView.paste(nil, from: pasteboard))
        #expect(textView.string == "# Overview\nFirst section\n## Details\nSecond section")
    }

    @Test func pasteCommandInsertsEveryClipboardTextItemAtCursor() throws {
        let scrollView = MarkdownTextView.makeConfiguredScrollView(text: "Before\nAfter")
        let textView = try #require(scrollView.documentView as? MarkdownEditorTextView)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))

        pasteboard.clearContents()
        let overview = NSPasteboardItem()
        overview.setString("# Overview\nFirst section", forType: .string)
        let details = NSPasteboardItem()
        details.setString("## Details\nSecond section", forType: .string)

        textView.setSelectedRange(NSRange(location: 7, length: 0))

        #expect(pasteboard.writeObjects([overview, details]))
        #expect(textView.paste(nil, from: pasteboard))

        let insertedText = "# Overview\nFirst section\n## Details\nSecond section"
        #expect(textView.string == "Before\n\(insertedText)After")
        #expect(textView.selectedRange().location == 7 + (insertedText as NSString).length)
        #expect(textView.selectedRange().length == 0)
    }

    @Test func preferredPasteLeavesSingleRichClipboardForAppKit() throws {
        let scrollView = MarkdownTextView.makeConfiguredScrollView(text: "")
        let textView = try #require(scrollView.documentView as? MarkdownEditorTextView)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()

        let item = NSPasteboardItem()
        item.setString("Plain fallback", forType: .string)
        item.setString("<html><body><p>Rich visible text</p></body></html>", forType: .html)

        #expect(pasteboard.writeObjects([item]))
        #expect(!textView.insertPreferredPasteboardText(from: pasteboard))
        #expect(textView.string.isEmpty)
    }

    @Test func preferredPasteUsesSingleItemHTMLWhenPlainTextIsOnlyLinkTarget() throws {
        let scrollView = MarkdownTextView.makeConfiguredScrollView(text: "")
        let textView = try #require(scrollView.documentView as? MarkdownEditorTextView)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        let fullSelection = """
        Saved the public review at /tmp/obvioussavemd-fixtures/portfolio-repository-review.md. Verified links and kept unrelated clipboard metadata untouched.
        """
        let htmlSelection = """
        <html><body><p>Saved the public review at <a href="file:///tmp/obvioussavemd-fixtures/portfolio-repository-review.md">/tmp/obvioussavemd-fixtures/portfolio-repository-review.md</a>. Verified links and kept unrelated clipboard metadata untouched.</p></body></html>
        """

        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(
            "/tmp/obvioussavemd-fixtures/portfolio-repository-review.md",
            forType: .string
        )
        item.setString(htmlSelection, forType: .html)

        #expect(pasteboard.writeObjects([item]))
        #expect(textView.paste(nil, from: pasteboard))

        #expect(textView.string == fullSelection)
    }

    @Test func preferredPasteUsesSingleItemHTMLLinkLabelOverPlainTarget() throws {
        let scrollView = MarkdownTextView.makeConfiguredScrollView(text: "")
        let textView = try #require(scrollView.documentView as? MarkdownEditorTextView)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()

        let item = NSPasteboardItem()
        item.setString("https://example.com/project-plan", forType: .string)
        item.setString(
            "<html><body><a href=\"https://example.com/project-plan\">Project plan</a></body></html>",
            forType: .html
        )

        #expect(pasteboard.writeObjects([item]))
        #expect(textView.paste(nil, from: pasteboard))

        #expect(textView.string == "Project plan")
    }

    @Test func preferredPasteUsesSingleItemHTMLLinkLabelOverMailtoTarget() throws {
        let scrollView = MarkdownTextView.makeConfiguredScrollView(text: "")
        let textView = try #require(scrollView.documentView as? MarkdownEditorTextView)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()

        let item = NSPasteboardItem()
        item.setString("mailto:person@example.com", forType: .string)
        item.setString(
            "<html><body><a href=\"mailto:person@example.com\">Email person</a></body></html>",
            forType: .html
        )

        #expect(pasteboard.writeObjects([item]))
        #expect(textView.paste(nil, from: pasteboard))

        #expect(textView.string == "Email person")
    }

    @Test func preferredPasteUsesSingleItemRTFWhenPlainTextIsOnlyLinkTarget() throws {
        let scrollView = MarkdownTextView.makeConfiguredScrollView(text: "")
        let textView = try #require(scrollView.documentView as? MarkdownEditorTextView)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()

        let selectedText = "Review file"
        let rtfData = try #require(NSAttributedString(string: selectedText).rtf(
            from: NSRange(location: 0, length: (selectedText as NSString).length),
            documentAttributes: [:]
        ))
        let item = NSPasteboardItem()
        item.setString("/tmp/obvioussavemd-fixtures/report.md", forType: .string)
        item.setData(rtfData, forType: .rtf)

        #expect(pasteboard.writeObjects([item]))
        #expect(textView.paste(nil, from: pasteboard))

        #expect(textView.string == selectedText)
    }

    @Test func preferredPasteLeavesEquivalentPathTextWithTrailingWhitespaceForAppKit() throws {
        let scrollView = MarkdownTextView.makeConfiguredScrollView(text: "")
        let textView = try #require(scrollView.documentView as? MarkdownEditorTextView)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()

        let item = NSPasteboardItem()
        item.setString("/tmp/obvioussavemd-fixtures/report.md\n", forType: .string)
        item.setString("<html><body><p>/tmp/obvioussavemd-fixtures/report.md</p></body></html>", forType: .html)

        #expect(pasteboard.writeObjects([item]))
        #expect(!textView.insertPreferredPasteboardText(from: pasteboard))
        #expect(textView.string.isEmpty)
    }

    @Test func preferredPasteDoesNotTreatRelativePlainTextAsLinkMetadata() throws {
        let scrollView = MarkdownTextView.makeConfiguredScrollView(text: "")
        let textView = try #require(scrollView.documentView as? MarkdownEditorTextView)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()

        let item = NSPasteboardItem()
        item.setString("docs/release-notes", forType: .string)
        item.setString("<html><body><a href=\"https://example.com/docs\">Release notes</a></body></html>", forType: .html)

        #expect(pasteboard.writeObjects([item]))
        #expect(!textView.paste(nil, from: pasteboard))
        #expect(textView.string.isEmpty)
    }

    @Test func pastePreservesSeparatePlainItemEvenWhenItMatchesRichFilenameSuffix() throws {
        let scrollView = MarkdownTextView.makeConfiguredScrollView(text: "")
        let textView = try #require(scrollView.documentView as? MarkdownEditorTextView)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))

        let fullSelection = """
        Saved the public review at /tmp/obvioussavemd-fixtures/portfolio-repository-review.md. Verified links and kept unrelated clipboard metadata untouched.
        """
        let htmlSelection = """
        <html><body><p>Saved the public review at <a href="file:///tmp/obvioussavemd-fixtures/portfolio-repository-review.md">/tmp/obvioussavemd-fixtures/portfolio-repository-review.md</a>. Verified links and kept unrelated clipboard metadata untouched.</p></body></html>
        """

        pasteboard.clearContents()
        let linkTarget = NSPasteboardItem()
        linkTarget.setString(
            "/tmp/obvioussavemd-fixtures/portfolio-repository-review.md",
            forType: .string
        )
        linkTarget.setString(htmlSelection, forType: .html)
        let linkTitle = NSPasteboardItem()
        linkTitle.setString("repository-review.md", forType: .string)

        #expect(pasteboard.writeObjects([linkTarget, linkTitle]))
        #expect(textView.paste(nil, from: pasteboard))

        #expect(textView.string == fullSelection + "\nrepository-review.md")
    }

    @Test func pastePreservesSeparatePlainItemEvenWhenItMatchesRichFilename() throws {
        let scrollView = MarkdownTextView.makeConfiguredScrollView(text: "")
        let textView = try #require(scrollView.documentView as? MarkdownEditorTextView)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        let fullSelection = "Saved the review at /tmp/obvioussavemd-fixtures/report.md."
        let htmlSelection = """
        <html><body><p>Saved the review at /tmp/obvioussavemd-fixtures/report.md.</p></body></html>
        """

        pasteboard.clearContents()
        let pathItem = NSPasteboardItem()
        pathItem.setString("/tmp/obvioussavemd-fixtures/report.md", forType: .string)
        pathItem.setString(htmlSelection, forType: .html)
        let filenameItem = NSPasteboardItem()
        filenameItem.setString("report.md", forType: .string)

        #expect(pasteboard.writeObjects([pathItem, filenameItem]))
        #expect(textView.paste(nil, from: pasteboard))

        #expect(textView.string == fullSelection + "\nreport.md")
    }

    @Test func namedPasteboardCommandFallbackDoesNotReadGeneralClipboard() throws {
        let scrollView = MarkdownTextView.makeConfiguredScrollView(text: "")
        let textView = try #require(scrollView.documentView as? MarkdownEditorTextView)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()

        let item = NSPasteboardItem()
        item.setString("Single named item", forType: .string)

        #expect(pasteboard.writeObjects([item]))
        #expect(!textView.paste(nil, from: pasteboard))
        #expect(textView.string.isEmpty)
    }

    @Test func pastingRichSelectionKeepsUnrelatedPlainClipboardItems() throws {
        let scrollView = MarkdownTextView.makeConfiguredScrollView(text: "")
        let textView = try #require(scrollView.documentView as? MarkdownEditorTextView)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()

        let first = NSPasteboardItem()
        first.setString("<html><body><p>First section</p></body></html>", forType: .html)
        let second = NSPasteboardItem()
        second.setString("Second section", forType: .string)

        #expect(pasteboard.writeObjects([first, second]))
        #expect(textView.paste(nil, from: pasteboard))

        #expect(textView.string == "First section\nSecond section")
    }

    @Test func pastingRichSelectionKeepsRepeatedPlainClipboardItems() throws {
        let scrollView = MarkdownTextView.makeConfiguredScrollView(text: "")
        let textView = try #require(scrollView.documentView as? MarkdownEditorTextView)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()

        let first = NSPasteboardItem()
        first.setString("<html><body><p>Second section</p></body></html>", forType: .html)
        let second = NSPasteboardItem()
        second.setString("Second section", forType: .string)

        #expect(pasteboard.writeObjects([first, second]))
        #expect(textView.paste(nil, from: pasteboard))

        #expect(textView.string == "Second section\nSecond section")
    }

    @Test func pastingRTFKeepsSelectedTrailingNewline() throws {
        let scrollView = MarkdownTextView.makeConfiguredScrollView(text: "")
        let textView = try #require(scrollView.documentView as? MarkdownEditorTextView)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()

        let selectedText = "Line one\n"
        let rtfData = try #require(NSAttributedString(string: selectedText).rtf(
            from: NSRange(location: 0, length: (selectedText as NSString).length),
            documentAttributes: [:]
        ))
        let item = NSPasteboardItem()
        item.setData(rtfData, forType: .rtf)

        #expect(pasteboard.writeObjects([item]))
        #expect(textView.paste(nil, from: pasteboard))

        #expect(textView.string == selectedText)
    }

    @Test func emptyNamedPasteboardDoesNotChangeSelectionOrText() throws {
        let scrollView = MarkdownTextView.makeConfiguredScrollView(text: "Keep this")
        let textView = try #require(scrollView.documentView as? MarkdownEditorTextView)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
        textView.setSelectedRange(NSRange(location: 0, length: 4))
        #expect(!textView.paste(nil, from: pasteboard))
        #expect(textView.string == "Keep this")
        #expect(textView.selectedRange() == NSRange(location: 0, length: 4))
    }

    @Test func malformedRichRepresentationFallsBackToSameItemsPlainText() throws {
        let scrollView = MarkdownTextView.makeConfiguredScrollView(text: "")
        let textView = try #require(scrollView.documentView as? MarkdownEditorTextView)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
        let first = NSPasteboardItem()
        first.setData(Data([0, 1, 2, 3]), forType: .rtf)
        first.setString("First", forType: .string)
        let second = NSPasteboardItem()
        second.setString("Second", forType: .string)
        #expect(pasteboard.writeObjects([first, second]))
        #expect(textView.paste(nil, from: pasteboard))
        #expect(textView.string == "First\nSecond")
    }

    @Test func openDialogDocumentTypesAllowMarkdownAndPlainTextOnly() {
        #expect(EditableDocumentContentTypes.allowsFileName("notes.md"))
        #expect(EditableDocumentContentTypes.allowsFileName("notes.markdown"))
        #expect(EditableDocumentContentTypes.allowsFileName("notes.txt"))
        #expect(!EditableDocumentContentTypes.allowsFileName("photo.png"))
        #expect(!EditableDocumentContentTypes.allowsFileName("archive.zip"))
    }

    @Test func openDialogConfigurationDoesNotInstallPathEntryAccessory() {
        let panel = NSOpenPanel()

        OpenPanelConfiguration.configure(panel)

        #expect(panel.accessoryView == nil)
        #expect(!panel.isAccessoryViewDisclosed)
        #expect(!panel.canChooseDirectories)
        #expect(panel.canChooseFiles)
    }
}

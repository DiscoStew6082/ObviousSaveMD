import AppKit
import SwiftUI

struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        Self.makeConfiguredScrollView(text: text, delegate: context.coordinator)
    }

    static func makeConfiguredScrollView(text: String, delegate: NSTextViewDelegate? = nil) -> NSScrollView {
        let scrollView = MarkdownEditorTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.scrollerStyle = .legacy
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.delegate = delegate
        textView.string = text
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.insertionPointColor = .controlAccentColor
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]

        if let textContainer = textView.textContainer {
            textContainer.widthTracksTextView = true
            textContainer.heightTracksTextView = false
            textContainer.containerSize = NSSize(
                width: scrollView.contentSize.width,
                height: CGFloat.greatestFiniteMagnitude
            )
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text

        guard let textView = scrollView.documentView as? NSTextView, textView.string != text else {
            return
        }

        let selectedRanges = clampedSelectedRanges(textView.selectedRanges, maxLength: (text as NSString).length)
        context.coordinator.isProgrammaticUpdate = true
        textView.string = text
        textView.selectedRanges = selectedRanges
        context.coordinator.isProgrammaticUpdate = false
    }

    private func clampedSelectedRanges(_ ranges: [NSValue], maxLength: Int) -> [NSValue] {
        let clampedRanges = ranges.map { value -> NSValue in
            var range = value.rangeValue

            if range.location > maxLength {
                range.location = maxLength
                range.length = 0
            } else if range.location + range.length > maxLength {
                range.length = maxLength - range.location
            }

            return NSValue(range: range)
        }

        return clampedRanges.isEmpty ? [NSValue(range: NSRange(location: maxLength, length: 0))] : clampedRanges
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var isProgrammaticUpdate = false

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard !isProgrammaticUpdate, let textView = notification.object as? NSTextView else {
                return
            }

            text.wrappedValue = textView.string
        }
    }
}

final class MarkdownEditorTextView: NSTextView {
    override func paste(_ sender: Any?) {
        paste(sender, from: .general)
    }

    @discardableResult
    func paste(_ sender: Any?, from pasteboard: NSPasteboard) -> Bool {
        guard insertPreferredPasteboardText(from: pasteboard) else {
            guard pasteboard.name == .general else {
                return false
            }

            super.paste(sender)
            return false
        }

        return true
    }

    @discardableResult
    func insertPreferredPasteboardText(from pasteboard: NSPasteboard) -> Bool {
        guard let text = PasteboardPlainText.preferredTextForEditorPaste(from: pasteboard) else {
            return false
        }

        insertText(text, replacementRange: selectedRange())
        return true
    }

    @discardableResult
    func insertPlainTextFragments(from pasteboard: NSPasteboard) -> Bool {
        guard let text = PasteboardPlainText.text(from: pasteboard) else {
            return false
        }

        insertText(text, replacementRange: selectedRange())
        return true
    }
}

private enum PasteboardPlainText {
    static func preferredTextForEditorPaste(from pasteboard: NSPasteboard) -> String? {
        let itemCount = pasteboard.pasteboardItems?.count ?? 0
        guard itemCount > 1 else {
            return richTextWhenItAddsVisibleText(from: pasteboard)
        }

        if let richText = richText(from: pasteboard) {
            return richText
        }

        let fragments = plainTextFragments(from: pasteboard)
        return fragments.count > 1 ? fragments.joined(separator: "\n") : nil
    }

    private static func richTextWhenItAddsVisibleText(from pasteboard: NSPasteboard) -> String? {
        guard let richText = richText(from: pasteboard) else {
            return nil
        }

        let plainText = plainTextFragments(from: pasteboard).joined(separator: "\n")
        let visibleRichText = richText.trimmingCharacters(in: .whitespacesAndNewlines)
        let visiblePlainText = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !visibleRichText.isEmpty,
              visibleRichText != visiblePlainText else {
            return nil
        }

        if isPlainTextOnlyLinkTarget(plainText) {
            return richText
        }

        return nil
    }

    static func text(from pasteboard: NSPasteboard) -> String? {
        if let richText = richText(from: pasteboard) {
            return richText
        }

        let fragments = plainTextFragments(from: pasteboard)
        guard !fragments.isEmpty else {
            return normalizedPlainText(pasteboard.string(forType: .string))
        }

        return fragments.joined(separator: "\n")
    }

    private static func plainTextFragments(from pasteboard: NSPasteboard) -> [String] {
        guard let items = pasteboard.pasteboardItems, !items.isEmpty else {
            return normalizedPlainText(pasteboard.string(forType: .string)).map { [$0] } ?? []
        }

        return items.compactMap { item in
            normalizedPlainText(item.string(forType: .string))
        }
    }

    private static func richText(from pasteboard: NSPasteboard) -> String? {
        guard let items = pasteboard.pasteboardItems else {
            return nil
        }

        let richFragments = items.map { item in
            (
                item: item,
                text: attributedPlainText(from: item, type: .html, documentType: .html)
                    ?? attributedPlainText(from: item, type: .rtf, documentType: .rtf)
            )
        }
        let richText = richFragments.compactMap(\.text).joined(separator: "\n")
        guard !richText.isEmpty else {
            return nil
        }

        let fragments = richFragments.compactMap { fragment -> String? in
            if let text = fragment.text {
                return text
            }

            guard let plainText = normalizedPlainText(fragment.item.string(forType: .string)),
                  !isRedundantPlainMetadata(plainText, in: richText) else {
                return nil
            }

            return plainText
        }

        return fragments.joined(separator: "\n")
    }

    private static func attributedPlainText(
        from item: NSPasteboardItem,
        type: NSPasteboard.PasteboardType,
        documentType: NSAttributedString.DocumentType
    ) -> String? {
        guard let data = item.data(forType: type) else {
            return nil
        }

        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: documentType,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ]
        guard let attributedString = try? NSAttributedString(
            data: data,
            options: options,
            documentAttributes: nil
        ) else {
            return nil
        }

        return normalizedRichText(attributedString.string, documentType: documentType)
    }

    private static func normalizedPlainText(_ text: String?) -> String? {
        guard let text, !text.isEmpty else {
            return nil
        }

        return text
    }

    private static func normalizedRichText(
        _ text: String,
        documentType: NSAttributedString.DocumentType
    ) -> String? {
        var normalizedText = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        if documentType == .html, normalizedText.hasSuffix("\n") {
            normalizedText.removeLast()
        }

        return normalizedText.isEmpty ? nil : normalizedText
    }

    private static func isRedundantPlainMetadata(_ plainText: String, in richText: String) -> Bool {
        return pathLikeTokens(in: richText).contains { token in
            let lastPathComponent = URL(fileURLWithPath: token).lastPathComponent
            return lastPathComponent == plainText || lastPathComponent.hasSuffix(plainText)
        }
    }

    private static func isPlainTextOnlyLinkTarget(_ plainText: String) -> Bool {
        let normalizedPlainText = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedPlainText.hasPrefix("/")
            || normalizedPlainText.hasPrefix("~/")
            || normalizedPlainText.range(
                of: #"^[A-Za-z][A-Za-z0-9+.-]*:\S+$"#,
                options: .regularExpression
            ) != nil
    }

    private static func pathLikeTokens(in text: String) -> [String] {
        text.split { character in
            character.isWhitespace || "\"'`()[]{}<>".contains(character)
        }
        .map { token in
            token.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?"))
        }
        .filter { token in
            token.contains("/")
        }
    }
}

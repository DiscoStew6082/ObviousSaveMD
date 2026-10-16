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
        switch PasteboardPlainText.decision(from: pasteboard) {
        case .insert(let text):
            insertText(text, replacementRange: selectedRange())
            return true
        case .deferToAppKit:
            // AppKit's paste reads the general clipboard, never a named fixture.
            if pasteboard.name == .general {
                super.paste(sender)
            }
            return false
        case .empty:
            return false
        }
    }

    @discardableResult
    func insertPreferredPasteboardText(from pasteboard: NSPasteboard) -> Bool {
        guard case .insert(let text) = PasteboardPlainText.decision(from: pasteboard) else {
            return false
        }
        insertText(text, replacementRange: selectedRange())
        return true
    }
}

enum PasteDecision: Equatable {
    case insert(String)
    case deferToAppKit
    case empty
}

@MainActor
private enum PasteboardPlainText {
    private struct Item {
        let plainText: String?
        let richText: String?
    }

    /// Decode each item's representations once. A separate plain item is content;
    /// a filename-like suffix in another item's rich text is not provenance.
    static func decision(from pasteboard: NSPasteboard) -> PasteDecision {
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            Item(
                plainText: normalizedPlainText(item.string(forType: .string)),
                richText: attributedPlainText(from: item, type: .html, documentType: .html)
                    ?? attributedPlainText(from: item, type: .rtf, documentType: .rtf)
            )
        }
        guard !items.isEmpty else {
            return normalizedPlainText(pasteboard.string(forType: .string)) == nil
                ? .empty : .deferToAppKit
        }

        if items.count == 1, let item = items.first {
            if let rich = item.richText {
                guard let plain = item.plainText else { return .insert(rich) }
                // AppKit may supply an equivalent plain representation for RTF.
                // There is no competing interpretation when both are identical;
                // preserve the decoded content, including its trailing newline.
                if plain == rich { return .insert(rich) }
                if isPlainTextOnlyLinkTarget(plain),
                   rich.trimmingCharacters(in: .whitespacesAndNewlines)
                    != plain.trimmingCharacters(in: .whitespacesAndNewlines) {
                    return .insert(rich)
                }
                return .deferToAppKit
            }
            return item.plainText == nil ? .empty : .deferToAppKit
        }

        let fragments = items.compactMap { $0.richText ?? $0.plainText }
        guard !fragments.isEmpty else { return .empty }
        if items.contains(where: { $0.richText != nil }) || fragments.count > 1 {
            return .insert(fragments.joined(separator: "\n"))
        }
        return .deferToAppKit
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

    private static func isPlainTextOnlyLinkTarget(_ plainText: String) -> Bool {
        let normalizedPlainText = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedPlainText.hasPrefix("/")
            || normalizedPlainText.hasPrefix("~/")
            || normalizedPlainText.range(
                of: #"^[A-Za-z][A-Za-z0-9+.-]*:\S+$"#,
                options: .regularExpression
            ) != nil
    }

}

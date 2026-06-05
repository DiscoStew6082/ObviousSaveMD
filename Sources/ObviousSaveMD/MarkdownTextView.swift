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
        let fragments = PlainTextPasteboardFragments.read(from: .general)
        guard fragments.count > 1 else {
            super.paste(sender)
            return
        }

        insertText(fragments.joined(separator: "\n"), replacementRange: selectedRange())
    }

    @discardableResult
    func insertPlainTextFragments(from pasteboard: NSPasteboard) -> Bool {
        let fragments = PlainTextPasteboardFragments.read(from: pasteboard)
        guard !fragments.isEmpty else {
            return false
        }

        insertText(fragments.joined(separator: "\n"), replacementRange: selectedRange())
        return true
    }
}

private enum PlainTextPasteboardFragments {
    static func read(from pasteboard: NSPasteboard) -> [String] {
        guard let items = pasteboard.pasteboardItems, !items.isEmpty else {
            return pasteboard.string(forType: .string).map { [$0] } ?? []
        }

        return items.compactMap { item in
            let text = item.string(forType: .string) ?? ""
            return text.isEmpty ? nil : text
        }
    }
}

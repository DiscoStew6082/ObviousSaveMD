import AppKit
import SwiftUI

struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.delegate = context.coordinator
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

        if let textContainer = textView.textContainer {
            textContainer.widthTracksTextView = false
            textContainer.containerSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude,
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

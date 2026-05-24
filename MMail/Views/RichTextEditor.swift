import SwiftUI
import AppKit

enum RichFormat { case bold, italic, underline, bullet }

/// An NSTextView-backed editor so we can place the caret at the top on open and
/// apply real bold / italic / underline formatting (exported to HTML on send).
struct RichTextEditor: NSViewRepresentable {
    @Binding var attributed: NSAttributedString
    @Binding var command: RichFormat?
    var focusOnAppear = false
    var baseFontSize: CGFloat = 14

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        guard let tv = scroll.documentView as? NSTextView else { return scroll }
        tv.isRichText = true
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 8, height: 10)
        tv.font = .systemFont(ofSize: baseFontSize)
        tv.textColor = .labelColor
        tv.typingAttributes = [.font: NSFont.systemFont(ofSize: baseFontSize), .foregroundColor: NSColor.labelColor]
        tv.delegate = context.coordinator
        tv.textStorage?.setAttributedString(attributed)
        context.coordinator.textView = tv
        if focusOnAppear {
            DispatchQueue.main.async {
                tv.window?.makeFirstResponder(tv)
                tv.setSelectedRange(NSRange(location: 0, length: 0))
                tv.scrollRangeToVisible(NSRange(location: 0, length: 0))
            }
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        if let cmd = command {
            context.coordinator.apply(cmd)
            DispatchQueue.main.async { self.command = nil }
        }
        // Sync external changes (e.g. a template inserted) without clobbering typing.
        if tv.attributedString().string != attributed.string {
            let sel = tv.selectedRange()
            tv.textStorage?.setAttributedString(attributed)
            let loc = min(sel.location, attributed.length)
            tv.setSelectedRange(NSRange(location: loc, length: 0))
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: RichTextEditor
        weak var textView: NSTextView?
        init(_ parent: RichTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            parent.attributed = NSAttributedString(attributedString: tv.attributedString())
        }

        func apply(_ cmd: RichFormat) {
            guard let tv = textView, let storage = tv.textStorage else { return }
            let sel = tv.selectedRange()
            switch cmd {
            case .bold: toggleTrait(.boldFontMask, tv: tv, storage: storage, sel: sel)
            case .italic: toggleTrait(.italicFontMask, tv: tv, storage: storage, sel: sel)
            case .underline: toggleUnderline(tv: tv, storage: storage, sel: sel)
            case .bullet: tv.insertText("• ", replacementRange: sel)
            }
            parent.attributed = NSAttributedString(attributedString: tv.attributedString())
        }

        private func toggleTrait(_ trait: NSFontTraitMask, tv: NSTextView, storage: NSTextStorage, sel: NSRange) {
            let fm = NSFontManager.shared
            if sel.length == 0 {
                let cur = (tv.typingAttributes[.font] as? NSFont) ?? .systemFont(ofSize: parent.baseFontSize)
                let has = fm.traits(of: cur).contains(trait)
                tv.typingAttributes[.font] = has ? fm.convert(cur, toNotHaveTrait: trait) : fm.convert(cur, toHaveTrait: trait)
                return
            }
            storage.beginEditing()
            storage.enumerateAttribute(.font, in: sel, options: []) { value, sub, _ in
                let font = (value as? NSFont) ?? .systemFont(ofSize: parent.baseFontSize)
                let has = fm.traits(of: font).contains(trait)
                let newFont = has ? fm.convert(font, toNotHaveTrait: trait) : fm.convert(font, toHaveTrait: trait)
                storage.addAttribute(.font, value: newFont, range: sub)
            }
            storage.endEditing()
        }

        private func toggleUnderline(tv: NSTextView, storage: NSTextStorage, sel: NSRange) {
            if sel.length == 0 {
                let on = (tv.typingAttributes[.underlineStyle] as? Int) ?? 0
                tv.typingAttributes[.underlineStyle] = on == 0 ? NSUnderlineStyle.single.rawValue : 0
                return
            }
            var allUnderlined = true
            storage.enumerateAttribute(.underlineStyle, in: sel, options: []) { value, _, stop in
                if (value as? Int) ?? 0 == 0 { allUnderlined = false; stop.pointee = true }
            }
            storage.beginEditing()
            if allUnderlined { storage.removeAttribute(.underlineStyle, range: sel) }
            else { storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: sel) }
            storage.endEditing()
        }
    }
}

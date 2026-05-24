import SwiftUI
import AppKit

enum RichFormat { case bold, italic, underline, bullet, numbered }

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
            case .bullet: applyList(ordered: false, tv: tv, storage: storage)
            case .numbered: applyList(ordered: true, tv: tv, storage: storage)
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

        private static let bulletRe = try? NSRegularExpression(pattern: "^•\\s")
        private static let numberRe = try? NSRegularExpression(pattern: "^\\d+\\.\\s")

        /// Toggle a bullet / numbered list across the selected lines, preserving
        /// each line's inline formatting (only the leading marker is rewritten).
        private func applyList(ordered: Bool, tv: NSTextView, storage: NSTextStorage) {
            let ns = storage.string as NSString
            let block = ns.lineRange(for: tv.selectedRange())
            var starts: [Int] = []
            var i = block.location
            while i < NSMaxRange(block) {
                starts.append(i)
                i = NSMaxRange(ns.lineRange(for: NSRange(location: i, length: 0)))
            }
            if starts.isEmpty { starts = [block.location] }

            func line(_ start: Int) -> NSString {
                ns.substring(with: ns.lineRange(for: NSRange(location: start, length: 0))) as NSString
            }
            func prefixLen(_ re: NSRegularExpression?, _ s: NSString) -> Int {
                re?.firstMatch(in: s as String, range: NSRange(location: 0, length: s.length))?.range.length ?? 0
            }
            let nonEmpty = starts.filter { !(line($0) as String).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let allBulleted = !nonEmpty.isEmpty && nonEmpty.allSatisfy { prefixLen(Self.bulletRe, line($0)) > 0 }
            let allNumbered = !nonEmpty.isEmpty && nonEmpty.allSatisfy { prefixLen(Self.numberRe, line($0)) > 0 }
            let removing = (ordered && allNumbered) || (!ordered && allBulleted)

            struct Edit { let start: Int; let removeLen: Int; let insert: String }
            var edits: [Edit] = []
            var counter = 1
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: parent.baseFontSize),
                                                        .foregroundColor: NSColor.labelColor]
            for start in starts {
                let c = line(start)
                if (c as String).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                let existing = max(prefixLen(Self.bulletRe, c), prefixLen(Self.numberRe, c))
                let insert: String
                if removing { insert = "" }
                else if ordered { insert = "\(counter). "; counter += 1 }
                else { insert = "• " }
                edits.append(Edit(start: start, removeLen: existing, insert: insert))
            }
            storage.beginEditing()
            for e in edits.sorted(by: { $0.start > $1.start }) {
                storage.replaceCharacters(in: NSRange(location: e.start, length: e.removeLen),
                                          with: NSAttributedString(string: e.insert, attributes: attrs))
            }
            storage.endEditing()
            let newLen = (storage.string as NSString).length
            tv.setSelectedRange(NSRange(location: min(NSMaxRange(block), newLen), length: 0))
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

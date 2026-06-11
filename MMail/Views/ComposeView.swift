import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ComposeView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p
    let draft: ComposeDraft

    @State private var to: String
    @State private var cc: String
    @State private var bcc: String
    @State private var showCcBcc: Bool
    @State private var subject: String
    @StateObject private var editor: RichTextController
    @State private var fromId: String
    @State private var attachments: [ComposeAttachment] = []
    @FocusState private var focus: Field?

    // Popovers
    @State private var templatesOpen = false
    @State private var scheduleOpen = false
    // Template editor sheet
    @State private var editorOpen = false
    @State private var editorName = ""
    @State private var editorBody = ""
    // Custom-time schedule sheet
    @State private var customOpen = false
    @State private var customWhen = Date()
    // Local key monitor (Escape routing for popovers/sheets)
    @State private var escMonitor: Any?
    @State private var fromPickerOpen = false
    @State private var dropTargeted = false

    enum Field { case to, subject, body }

    init(draft: ComposeDraft) {
        self.draft = draft
        _to = State(initialValue: draft.to)
        _cc = State(initialValue: draft.cc)
        _bcc = State(initialValue: draft.bcc)
        _showCcBcc = State(initialValue: !draft.cc.isEmpty || !draft.bcc.isEmpty)
        _subject = State(initialValue: draft.subject)
        let initialBody = NSAttributedString(
            string: draft.body,
            attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.labelColor])
        _editor = StateObject(wrappedValue: RichTextController(initial: initialBody, focusOnAppear: !draft.to.isEmpty))
        _fromId = State(initialValue: draft.fromId)
        _attachments = State(initialValue: draft.attachments)
    }

    private var fromAcct: Account? {
        model.accounts.first { $0.id == fromId } ?? model.accounts.first
    }

    private func currentDraft() -> ComposeDraft {
        var d = draft
        d.to = to; d.cc = cc; d.bcc = bcc; d.subject = subject; d.body = editor.currentString(); d.fromId = fromId
        d.attachments = attachments
        d.bodyHTML = htmlBody()
        return d
    }

    /// Export the body to HTML only when it actually uses formatting — plain
    /// messages stay plain text.
    private func htmlBody() -> String? {
        let body = editor.currentAttributed()
        let full = NSRange(location: 0, length: body.length)
        guard full.length > 0 else { return nil }
        var formatted = false
        body.enumerateAttributes(in: full, options: []) { attrs, _, stop in
            if let f = attrs[.font] as? NSFont {
                let t = NSFontManager.shared.traits(of: f)
                if t.contains(.boldFontMask) || t.contains(.italicFontMask) { formatted = true; stop.pointee = true }
            }
            if let u = attrs[.underlineStyle] as? Int, u != 0 { formatted = true; stop.pointee = true }
        }
        guard formatted else { return nil }
        guard let data = try? body.data(
            from: full,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.html,
                                 .characterEncoding: String.Encoding.utf8.rawValue]) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func pickAttachments() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK {
            for url in panel.urls {
                guard let data = try? Data(contentsOf: url) else { continue }
                let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                attachments.append(ComposeAttachment(filename: url.lastPathComponent, mimeType: mime, data: data))
            }
        }
    }

    private func send() { model.sendDraft(currentDraft()) }

    /// Attach a clipboard image on ⌘V. Returns true if it consumed the paste;
    /// when the clipboard holds text (no image), returns false so normal paste runs.
    @discardableResult
    private func pasteImageFromClipboard() -> Bool {
        let pb = NSPasteboard.general
        if pb.string(forType: .string) != nil { return false }   // let text paste through
        let png: Data?
        if let data = pb.data(forType: .png) {
            png = data
        } else if let img = NSImage(pasteboard: pb), let tiff = img.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff) {
            png = rep.representation(using: .png, properties: [:])
        } else {
            png = nil
        }
        guard let png else { return false }
        let name = "pasted-\(Int(Date().timeIntervalSince1970)).png"
        attachments.append(ComposeAttachment(filename: name, mimeType: "image/png", data: png))
        return true
    }

    /// Accept files dropped onto the compose window as attachments.
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            handled = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var url: URL?
                if let u = item as? URL { url = u }
                else if let d = item as? Data { url = URL(dataRepresentation: d, relativeTo: nil) }
                else if let s = item as? String { url = URL(string: s) }
                guard let url, url.isFileURL, let data = try? Data(contentsOf: url) else { return }
                let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                DispatchQueue.main.async {
                    attachments.append(ComposeAttachment(filename: url.lastPathComponent, mimeType: mime, data: data))
                }
            }
        }
        return handled
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            fromField
            Divider().overlay(p.border)
            RecipientRow(label: "To", text: $to, contacts: model.contacts(), autofocus: to.isEmpty) {
                if !showCcBcc {
                    Button("Cc/Bcc") { showCcBcc = true }
                        .buttonStyle(.plain).font(.system(size: 11.5)).foregroundStyle(p.fg3)
                }
            }
            Divider().overlay(p.border)
            if showCcBcc {
                RecipientRow(label: "Cc", text: $cc, contacts: model.contacts()) { EmptyView() }
                Divider().overlay(p.border)
                RecipientRow(label: "Bcc", text: $bcc, contacts: model.contacts()) { EmptyView() }
                Divider().overlay(p.border)
            }
            field(label: "Subject") {
                TextField("", text: $subject)
                    .textFieldStyle(.plain).font(.system(size: 13.5))
                    .focused($focus, equals: .subject)
            }
            Divider().overlay(p.border)
            formatBar
            Divider().overlay(p.border)
            RichTextEditor(controller: editor)
                .padding(4)
                .frame(maxHeight: .infinity)
                .overlay(alignment: .topLeading) {
                    if editor.isEmpty {
                        Text("Write your message…")
                            .font(.system(size: 14)).foregroundStyle(p.fg4)
                            .padding(.horizontal, 17).padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }
            if !attachments.isEmpty { attachmentBar }
            footer
        }
        .frame(width: 540, height: 460)
        .background(p.bg1)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(dropTargeted ? p.brandBlue : p.borderStrong, lineWidth: dropTargeted ? 2 : 1))
        .overlay {
            if dropTargeted {
                ZStack {
                    p.brandBlue100.opacity(0.6)
                    VStack(spacing: 8) {
                        Icon(name: "attach", size: 28).foregroundStyle(p.brandBlue)
                        Text("Drop to attach").font(.system(size: 15, weight: .semibold)).foregroundStyle(p.brandBlue)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { handleDrop($0) }
        .shadow(color: .black.opacity(0.3), radius: 40, y: 16)
        .background(hiddenShortcuts)
        .onAppear { installEscMonitor() }
        .onDisappear { removeEscMonitor() }
        .foregroundStyle(p.fg1)
        .sheet(isPresented: $editorOpen) { templateEditorSheet }
        .sheet(isPresented: $customOpen) { customScheduleSheet }
    }

    // Hidden keyboard shortcuts: ⌘/ toggles templates; digits apply when open.
    private var hiddenShortcuts: some View {
        Group {
            Button("") { if !editorOpen && !customOpen { templatesOpen.toggle() } }
                .keyboardShortcut(KeyEquivalent("/"), modifiers: .command)
            if templatesOpen && !editorOpen && !customOpen {
                ForEach(model.templates.filter { !$0.shortcut.isEmpty }) { tpl in
                    Button("") { applyTemplate(tpl) }
                        .keyboardShortcut(KeyEquivalent(Character(tpl.shortcut)), modifiers: [])
                }
            }
        }
        .opacity(0).frame(width: 0, height: 0)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(draft.titleLabel).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(p.fg2)
            Spacer()
            Button { model.saveDraftAndClose(currentDraft()) } label: { Icon(name: "x", size: 14).foregroundStyle(p.fg2) }
                .buttonStyle(.plain).help("Save draft & close")
        }
        .padding(.horizontal, 14).frame(height: 42)
        .background(p.bg2)
        .overlay(Rectangle().fill(p.border).frame(height: 1), alignment: .bottom)
    }

    private var fromField: some View {
        HStack(spacing: 0) {
            Text("From").font(.system(size: 12)).foregroundStyle(p.fg3).frame(width: 56, alignment: .leading)
            Button { fromPickerOpen.toggle() } label: {
                HStack(spacing: 8) {
                    if let acct = fromAcct {
                        GradientTile(colors: acct.gradientColors, text: acct.initials, size: 18, cornerRadius: 5, fontSize: 10, image: acct.avatarImage)
                        Text(acct.email).font(.system(size: 12.5, weight: .medium)).foregroundStyle(p.fg1).lineLimit(1)
                    } else {
                        Text("No account").font(.system(size: 12.5)).foregroundStyle(p.fg3)
                    }
                    Icon(name: "chevronDown", size: 12).foregroundStyle(p.fg3)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(p.bg3)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(model.accounts.count <= 1)
            .popover(isPresented: $fromPickerOpen, arrowEdge: .bottom) {
                VStack(spacing: 2) {
                    ForEach(model.accounts) { a in
                        Button { fromId = a.id; fromPickerOpen = false } label: {
                            HStack(spacing: 10) {
                                GradientTile(colors: a.gradientColors, text: a.initials, size: 22, cornerRadius: 6, fontSize: 11, image: a.avatarImage)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(a.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(p.fg1)
                                    Text(a.email).font(.system(size: 11)).foregroundStyle(p.fg3)
                                }
                                Spacer(minLength: 12)
                                if a.id == fromId { Icon(name: "check", size: 13).foregroundStyle(p.brandBlue) }
                            }
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(HoverRowButtonStyle())
                    }
                }
                .padding(6).frame(width: 280)
            }
            Spacer()
        }
        .padding(.horizontal, 14).frame(height: 40)
    }

    private func field<C: View>(label: String, @ViewBuilder content: () -> C) -> some View {
        HStack(spacing: 0) {
            Text(label).font(.system(size: 12)).foregroundStyle(p.fg3).frame(width: 56, alignment: .leading)
            content()
        }
        .padding(.horizontal, 14).frame(height: 40)
    }

    // MARK: Formatting bar

    private var formatBar: some View {
        HStack(spacing: 4) {
            formatButton(help: "Bold") { editor.apply(.bold) } label: {
                Text("B").font(.system(size: 13, weight: .bold))
            }
            formatButton(help: "Italic") { editor.apply(.italic) } label: {
                Text("I").font(.system(size: 13, weight: .semibold)).italic()
            }
            formatButton(help: "Underline") { editor.apply(.underline) } label: {
                Text("U").font(.system(size: 13, weight: .semibold)).underline()
            }
            formatButton(help: "Bulleted list") { editor.apply(.bullet) } label: {
                Image(systemName: "list.bullet").font(.system(size: 12))
            }
            formatButton(help: "Numbered list") { editor.apply(.numbered) } label: {
                Image(systemName: "list.number").font(.system(size: 12))
            }
            Spacer()
        }
        .foregroundStyle(p.fg2)
        .padding(.horizontal, 12).padding(.vertical, 5)
    }

    private func formatButton<L: View>(help: String, action: @escaping () -> Void, @ViewBuilder label: () -> L) -> some View {
        Button(action: action) {
            label().frame(width: 28, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(help)
    }

    // MARK: Footer

    private var attachmentBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(attachments) { att in
                    HStack(spacing: 6) {
                        Icon(name: "attach", size: 11).foregroundStyle(p.fg3)
                        Text(att.filename).font(.system(size: 11.5)).foregroundStyle(p.fg1).lineLimit(1)
                        Button { attachments.removeAll { $0.id == att.id } } label: {
                            Icon(name: "x", size: 10).foregroundStyle(p.fg3)
                        }.buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(p.bg3)
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 6)
        }
        .overlay(Rectangle().fill(p.border).frame(height: 1), alignment: .top)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button(action: send) {
                HStack(spacing: 8) {
                    Icon(name: "send", size: 14)
                    Text("Send").font(.system(size: 13, weight: .semibold))
                    Kbd("⌘↵", onAccent: true)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14).frame(height: 32)
                .background(p.brandBlue)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: .command)

            footerIcon("attach", help: "Attach file", active: !attachments.isEmpty) { pickAttachments() }

            scheduleButton
            templatesButton

            Spacer()
            Button { model.compose = nil } label: {
                Icon(name: "trash", size: 14).foregroundStyle(p.fg3).frame(width: 30, height: 30)
            }.buttonStyle(.plain).help("Discard")
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .overlay(Rectangle().fill(p.border).frame(height: 1), alignment: .top)
    }

    private func footerIcon(_ icon: String, help: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Icon(name: icon, size: 14)
                .foregroundStyle(active ? p.brandBlue : p.fg3)
                .frame(width: 30, height: 30)
                .background(active ? p.brandBlue100 : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain).help(help)
    }

    // MARK: Schedule send

    private var scheduleButton: some View {
        footerIcon("clock", help: "Schedule send", active: scheduleOpen) { scheduleOpen.toggle() }
            .popover(isPresented: $scheduleOpen, arrowEdge: .top) { scheduleMenu }
    }

    private struct ScheduleOption: Identifiable { let id: String; let label: String; let sub: String; let when: Date }

    private var scheduleOptions: [ScheduleOption] {
        let now = Date()
        let cal = Calendar.current
        var opts: [ScheduleOption] = []
        let inHour = now.addingTimeInterval(3600)
        opts.append(.init(id: "hour", label: "In 1 hour", sub: timeStr(inHour), when: inHour))
        if let tonight = cal.date(bySettingHour: 18, minute: 0, second: 0, of: now), tonight > now {
            opts.append(.init(id: "tonight", label: "This evening", sub: "Today, \(timeStr(tonight))", when: tonight))
        }
        if let base = cal.date(byAdding: .day, value: 1, to: now),
           let tmrw = cal.date(bySettingHour: 8, minute: 0, second: 0, of: base) {
            opts.append(.init(id: "tomorrow", label: "Tomorrow morning", sub: "\(dayStr(tmrw)), \(timeStr(tmrw))", when: tmrw))
        }
        if let mon = nextMonday(from: now, cal: cal) {
            opts.append(.init(id: "monday", label: "Next Monday", sub: "\(dayStr(mon)), \(timeStr(mon))", when: mon))
        }
        return opts
    }

    private var scheduleMenu: some View {
        VStack(spacing: 0) {
            menuHead("Schedule send")
            VStack(spacing: 0) {
                ForEach(scheduleOptions) { opt in
                    Button { scheduleSend(opt) } label: {
                        HStack {
                            Text(opt.label).font(.system(size: 13, weight: .semibold)).foregroundStyle(p.fg1)
                            Spacer(minLength: 12)
                            Text(opt.sub).font(.system(size: 11.5)).monospacedDigit().foregroundStyle(p.fg3)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(HoverRowButtonStyle())
                }
            }
            .padding(4)
            dashedFootButton(icon: "clock", title: "Pick date & time…") { openCustom() }
        }
        .frame(width: 280)
        .background(p.bg1)
    }

    private func scheduleSend(_ opt: ScheduleOption) {
        scheduleOpen = false
        model.scheduleSend(currentDraft(), at: opt.when, label: opt.label)
    }

    private func openCustom() {
        let cal = Calendar.current
        if let base = cal.date(byAdding: .day, value: 1, to: Date()),
           let def = cal.date(bySettingHour: 9, minute: 0, second: 0, of: base) {
            customWhen = def
        }
        scheduleOpen = false
        customOpen = true
    }

    private func saveCustom() {
        let f = DateFormatter(); f.dateFormat = "MMM d, h:mm a"
        let label = f.string(from: customWhen)
        customOpen = false
        model.scheduleSend(currentDraft(), at: customWhen, label: label)
    }

    // MARK: Templates

    private var templatesButton: some View {
        footerIcon("file", help: "Reply templates (⌘/)", active: templatesOpen) { templatesOpen.toggle() }
            .popover(isPresented: $templatesOpen, arrowEdge: .top) { templatesMenu }
    }

    private var templatesMenu: some View {
        VStack(spacing: 0) {
            HStack {
                Text("REPLY TEMPLATES").font(.system(size: 10.5, weight: .bold)).tracking(0.6).foregroundStyle(p.fg3)
                Spacer()
                HStack(spacing: 2) { Kbd("⌘"); Kbd("/") }
            }
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 8)
            .overlay(Rectangle().fill(p.border).frame(height: 1), alignment: .bottom)

            ScrollView {
                VStack(spacing: 0) {
                    if model.templates.isEmpty {
                        Text("No templates yet.").font(.system(size: 12.5)).foregroundStyle(p.fg3).padding(.vertical, 24)
                    } else {
                        ForEach(model.templates) { tpl in templateRow(tpl) }
                    }
                }
                .padding(4)
            }
            .frame(maxHeight: 320)

            dashedFootButton(icon: "plus", title: "New template") { openEditor() }
        }
        .frame(width: 320)
        .background(p.bg1)
    }

    private func templateRow(_ tpl: ReplyTemplate) -> some View {
        TemplateRow(tpl: tpl,
                    onApply: { applyTemplate(tpl) },
                    onRemove: tpl.custom ? { model.removeTemplate(tpl.id) } : nil)
    }

    private func applyTemplate(_ tpl: ReplyTemplate) {
        if editor.currentString().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            editor.replaceAll(tpl.body)
        } else {
            editor.appendPlain("\n\n" + tpl.body)
        }
        templatesOpen = false
    }

    private func openEditor() {
        editorName = ""; editorBody = ""
        templatesOpen = false
        editorOpen = true
    }

    private func saveTemplate() {
        if model.addTemplate(name: editorName, body: editorBody) { editorOpen = false }
    }

    // MARK: Sheets

    private var templateEditorSheet: some View {
        VStack(spacing: 0) {
            sheetHead(icon: "file", title: "New reply template") { editorOpen = false }
            VStack(alignment: .leading, spacing: 14) {
                tplField(label: "Name") {
                    TextField("e.g. Thanks, will get back to you", text: $editorName)
                        .textFieldStyle(.plain)
                        .onSubmit { saveTemplate() }
                }
                tplField(label: "Body") {
                    TextEditor(text: $editorBody)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 140)
                }
                HStack(spacing: 6) {
                    Icon(name: "command", size: 11).foregroundStyle(p.fg4)
                    Text("A 1–9 shortcut will be auto-assigned if available.")
                        .font(.system(size: 11.5)).foregroundStyle(p.fg3)
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 16)
            sheetFoot {
                ghostButton("Cancel") { editorOpen = false }
                primaryButton("Save template",
                               disabled: editorName.trimmingCharacters(in: .whitespaces).isEmpty
                                   || editorBody.trimmingCharacters(in: .whitespaces).isEmpty,
                               action: saveTemplate)
            }
        }
        .frame(width: 520)
        .background(p.bg1)
    }

    private var customScheduleSheet: some View {
        VStack(spacing: 0) {
            sheetHead(icon: "clock", title: "Schedule send") { customOpen = false }
            VStack(alignment: .leading, spacing: 14) {
                tplField(label: "Send at") {
                    DatePicker("", selection: $customWhen, displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.field)
                        .labelsHidden()
                }
                HStack(spacing: 6) {
                    Icon(name: "bell", size: 11).foregroundStyle(p.fg4)
                    Text("You'll get a heads-up before it sends. Cancel anytime from the Drafts folder.")
                        .font(.system(size: 11.5)).foregroundStyle(p.fg3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 16)
            sheetFoot {
                ghostButton("Cancel") { customOpen = false }
                primaryButton("Schedule send", disabled: false, action: saveCustom)
            }
        }
        .frame(width: 440)
        .background(p.bg1)
    }

    // MARK: Small builders

    private func menuHead(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10.5, weight: .bold)).tracking(0.6).foregroundStyle(p.fg3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 8)
            .overlay(Rectangle().fill(p.border).frame(height: 1), alignment: .bottom)
    }

    private func dashedFootButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 6) {
                    Icon(name: icon, size: 12)
                    Text(title).font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(p.fg2)
                .frame(maxWidth: .infinity).padding(.vertical, 7)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(p.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            }
            .buttonStyle(.plain)
            .padding(6)
        }
        .background(p.bg2)
        .overlay(Rectangle().fill(p.border).frame(height: 1), alignment: .top)
    }

    private func sheetHead(icon: String, title: String, close: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Icon(name: icon, size: 14).foregroundStyle(p.brandBlue)
            Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(p.fg1)
            Spacer()
            Button(action: close) { Icon(name: "x", size: 14).foregroundStyle(p.fg3).frame(width: 30, height: 30) }
                .buttonStyle(.plain).keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .overlay(Rectangle().fill(p.border).frame(height: 1), alignment: .bottom)
    }

    private func sheetFoot<C: View>(@ViewBuilder content: () -> C) -> some View {
        HStack(spacing: 8) { Spacer(); content() }
            .padding(.horizontal, 18).padding(.vertical, 12)
            .background(p.bg2)
            .overlay(Rectangle().fill(p.border).frame(height: 1), alignment: .top)
    }

    private func tplField<C: View>(label: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(.system(size: 11, weight: .bold)).tracking(0.6).foregroundStyle(p.fg3)
            content()
                .font(.system(size: 13.5))
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(p.bg2)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(p.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func ghostButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(p.fg2)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(p.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func primaryButton(_ title: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(disabled ? p.bg4 : p.brandBlue)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain).disabled(disabled)
    }

    // MARK: Helpers

    private func timeStr(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }
    private func dayStr(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEE"; return f.string(from: d)
    }
    private func nextMonday(from now: Date, cal: Calendar) -> Date? {
        let jsDay = cal.component(.weekday, from: now) - 1 // Sun=0..Sat=6
        var days = ((1 - jsDay) + 7) % 7
        if days == 0 { days = 7 }
        guard let base = cal.date(byAdding: .day, value: days, to: now) else { return nil }
        return cal.date(bySettingHour: 9, minute: 0, second: 0, of: base)
    }

    // MARK: Escape routing (close topmost sub-overlay before the app monitor closes compose)

    private func installEscMonitor() {
        guard escMonitor == nil else { return }
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // ⌘V: attach a clipboard image (only when it's image-only, so text paste still works).
            if event.modifierFlags.contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "v",
               !editorOpen, !customOpen {
                if pasteImageFromClipboard() { return nil }
                return event
            }
            guard event.keyCode == 53 else { return event } // Escape only
            if editorOpen { editorOpen = false; return nil }
            if customOpen { customOpen = false; return nil }
            if templatesOpen { templatesOpen = false; return nil }
            if scheduleOpen { scheduleOpen = false; return nil }
            if fromPickerOpen { fromPickerOpen = false; return nil }
            return event
        }
    }
    private func removeEscMonitor() {
        if let m = escMonitor { NSEvent.removeMonitor(m); escMonitor = nil }
    }
}

// MARK: - Template row (hover reveals remove)

private struct TemplateRow: View {
    @Environment(\.palette) private var p
    let tpl: ReplyTemplate
    let onApply: () -> Void
    let onRemove: (() -> Void)?
    @State private var hover = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onApply) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tpl.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(p.fg1).lineLimit(1)
                        Text(previewLine).font(.system(size: 11.5)).foregroundStyle(p.fg3).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    if !tpl.shortcut.isEmpty { Kbd(tpl.shortcut) }
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let onRemove, hover {
                Button(action: onRemove) {
                    Icon(name: "x", size: 11).foregroundStyle(p.fg3).frame(width: 24, height: 24)
                }
                .buttonStyle(.plain).help("Remove template")
            }
        }
        .background(hover ? p.bg3 : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hover = $0 }
    }

    private var previewLine: String {
        let first = tpl.body.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? tpl.body
        return first.count > 60 ? String(first.prefix(60)) + "…" : first
    }
}

// MARK: - Recipient field with contact autocomplete

private struct RecipientRow<Trailing: View>: View {
    @Environment(\.palette) private var p
    let label: String
    @Binding var text: String
    let contacts: [Sender]
    var autofocus = false
    @ViewBuilder var trailing: () -> Trailing
    @FocusState private var focused: Bool

    private var lastToken: String {
        (text.components(separatedBy: ",").last ?? "").trimmingCharacters(in: .whitespaces)
    }
    private var matches: [Sender] {
        let q = lastToken.lowercased()
        guard focused, q.count >= 1 else { return [] }
        let used = Set(text.lowercased().split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init).filter { $0.contains("@") })
        return Array(contacts.filter {
            !$0.email.isEmpty && !used.contains($0.email.lowercased())
                && ($0.name.lowercased().contains(q) || $0.email.lowercased().contains(q))
        }.prefix(6))
    }
    private func complete(_ s: Sender) {
        var parts = text.components(separatedBy: ",")
        if parts.isEmpty { parts = [""] }
        parts[parts.count - 1] = " \(s.email)"
        text = parts.joined(separator: ",") + ", "
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(label).font(.system(size: 12)).foregroundStyle(p.fg3).frame(width: 56, alignment: .leading)
                TextField("", text: $text)
                    .textFieldStyle(.plain).font(.system(size: 13.5))
                    .focused($focused)
                    .autocorrectionDisabled()
                trailing()
            }
            .padding(.horizontal, 14).frame(height: 40)

            if !matches.isEmpty {
                VStack(spacing: 0) {
                    ForEach(matches) { s in
                        Button { complete(s) } label: {
                            HStack(spacing: 8) {
                                Avatar(sender: s, size: 22)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(s.name).font(.system(size: 12.5, weight: .medium)).foregroundStyle(p.fg1).lineLimit(1)
                                    Text(s.email).font(.system(size: 11)).foregroundStyle(p.fg3).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }
                        .buttonStyle(HoverRowButtonStyle())
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(p.bg2)
                .overlay(Rectangle().fill(p.border).frame(height: 1), alignment: .top)
            }
        }
        .onAppear { if autofocus { DispatchQueue.main.async { focused = true } } }
    }
}

// MARK: - Hover row button style (schedule options)

private struct HoverRowButtonStyle: ButtonStyle {
    @Environment(\.palette) private var p
    @State private var hover = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(hover ? p.bg3 : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onHover { hover = $0 }
    }
}

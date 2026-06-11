import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p
    @State private var newLabelDraft = ""
    @State private var ruleField: MailRule.Field = .from
    @State private var ruleValue = ""
    @State private var ruleAction: MailRule.Action = .trash
    @State private var ruleLabelId = ""
    @State private var proxySecretDraft = ""

    var body: some View {
        ZStack(alignment: .top) {
            OverlayBackdrop { model.settings = false }
            sheet.padding(.top, 88)
        }
    }

    private var sheet: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Icon(name: "settings", size: 20).foregroundStyle(p.fg1)
                Text("Settings").font(.system(size: 18, weight: .bold)).foregroundStyle(p.fg1)
                Spacer()
                Button { model.settings = false } label: { Icon(name: "x", size: 16).foregroundStyle(p.fg2) }.buttonStyle(.plain)
            }
            .padding(.horizontal, 28).padding(.vertical, 20)
            .overlay(Rectangle().fill(p.border).frame(height: 1), alignment: .bottom)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("Appearance") {
                        toggleRow("Dark mode", "Use a dark interface, day or night.",
                                  on: Binding(get: { model.dark }, set: { model.setDark($0) }))
                        toggleRow("Show sidebar", "Folders and labels rail on the left.",
                                  on: Binding(get: { model.sidebarVisible }, set: { model.setSidebar($0) }))
                        toggleRow("Reading pane", "Read messages alongside the list (off goes full-width).",
                                  on: Binding(get: { model.readingPane }, set: { model.setReadingPane($0) }), last: true)
                    }
                    section("Image privacy proxy") {
                        toggleRow("Route remote images through privacy proxy",
                                  "Load images for trusted senders via a caching proxy so the sender sees the proxy's IP, not yours. Off falls back to direct loading.",
                                  on: Binding(get: { model.proxyEnabled }, set: { model.setProxyEnabled($0) }))
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Proxy base URL").font(.system(size: 12, weight: .medium)).foregroundStyle(p.fg2)
                            TextField("https://your-worker.workers.dev", text: Binding(
                                get: { model.proxyBaseURL },
                                set: { model.setProxyBaseURL($0) }))
                                .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(p.fg1)
                                .padding(.horizontal, 8).padding(.vertical, 7)
                                .background(p.bg2)
                                .overlay(RoundedRectangle(cornerRadius: 7).stroke(p.border, lineWidth: 1))
                        }
                        .padding(.vertical, 10)
                        Rectangle().fill(p.border).frame(height: 1)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Signing secret").font(.system(size: 12, weight: .medium)).foregroundStyle(p.fg2)
                            Text("The same secret you set with `wrangler secret put PROXY_SECRET`. Stored in the macOS Keychain and a local file (`~/Library/Application Support/MMail/`) so it survives rebuilds.")
                                .font(.system(size: 11.5)).foregroundStyle(p.fg3)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 8) {
                                SecureField(model.hasProxySecret ? "•••••••• (set)" : "Paste the signing secret",
                                            text: $proxySecretDraft)
                                    .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(p.fg1)
                                    .padding(.horizontal, 8).padding(.vertical, 7)
                                    .background(p.bg2)
                                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(p.border, lineWidth: 1))
                                Button {
                                    model.setProxySecret(proxySecretDraft)
                                    proxySecretDraft = ""
                                } label: {
                                    Text("Save").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(p.brandBlue)
                                }
                                .buttonStyle(.plain)
                                .disabled(proxySecretDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                            if let saveError = model.proxySecretSaveError {
                                Text(saveError)
                                    .font(.system(size: 11.5)).foregroundStyle(p.danger)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            proxyMisconfigWarning
                        }
                        .padding(.vertical, 10)
                    }
                    section("Accounts") {
                        AllInboxEditRow()
                        Rectangle().fill(p.border).frame(height: 1)
                        if model.realConfigs.isEmpty {
                            Text("No account connected.").font(.system(size: 13)).foregroundStyle(p.fg3).padding(.vertical, 12)
                        } else {
                            ForEach(Array(model.realConfigs.enumerated()), id: \.element.id) { idx, cfg in
                                AccountEditRow(cfg: cfg)
                                if idx < model.realConfigs.count - 1 { Rectangle().fill(p.border).frame(height: 1) }
                            }
                        }
                        Rectangle().fill(p.border).frame(height: 1)
                        Button { model.settings = false; model.addingAccount = true } label: {
                            HStack(spacing: 6) { Icon(name: "plus", size: 13); Text("Add account").font(.system(size: 12.5, weight: .semibold)) }
                                .foregroundStyle(p.brandBlue)
                        }.buttonStyle(.plain).padding(.vertical, 12)
                    }
                    if !model.realConfigs.isEmpty {
                        section("Signatures") {
                            ForEach(Array(model.realConfigs.enumerated()), id: \.element.id) { idx, cfg in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(cfg.email).font(.system(size: 12, weight: .medium)).foregroundStyle(p.fg2)
                                    TextEditor(text: Binding(
                                        get: { model.signature(for: cfg.id) },
                                        set: { model.setSignature(cfg.id, $0) }))
                                        .font(.system(size: 13)).scrollContentBackground(.hidden)
                                        .frame(height: 70)
                                        .padding(8).background(p.bg2)
                                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(p.border, lineWidth: 1))
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                                .padding(.vertical, 10)
                                if idx < model.realConfigs.count - 1 { Rectangle().fill(p.border).frame(height: 1) }
                            }
                        }
                    }
                    section("Labels") {
                        if model.labels.isEmpty {
                            Text("No labels yet. Create one below.").font(.system(size: 13)).foregroundStyle(p.fg3).padding(.vertical, 12)
                        } else {
                            ForEach(model.labels) { l in
                                LabelEditRow(label: l)
                                if l.id != model.labels.last?.id { Rectangle().fill(p.border).frame(height: 1) }
                            }
                        }
                        Rectangle().fill(p.border).frame(height: 1)
                        HStack(spacing: 8) {
                            Icon(name: "tag", size: 13).foregroundStyle(p.fg3)
                            TextField("New label name", text: $newLabelDraft)
                                .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(p.fg1)
                                .onSubmit { addNewLabel() }
                            Button { addNewLabel() } label: {
                                Text("Add").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(p.brandBlue)
                            }
                            .buttonStyle(.plain)
                            .disabled(newLabelDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        .padding(.vertical, 12)
                    }
                    section("Rules") {
                        if model.rules.isEmpty {
                            Text("No rules yet. New inbox mail can be auto-labeled, archived, or trashed by sender or subject.")
                                .font(.system(size: 13)).foregroundStyle(p.fg3)
                                .fixedSize(horizontal: false, vertical: true).padding(.vertical, 12)
                        } else {
                            ForEach(model.rules) { r in
                                HStack(spacing: 8) {
                                    Icon(name: "sliders", size: 13).foregroundStyle(p.fg3)
                                    Text(ruleSummary(r)).font(.system(size: 13)).foregroundStyle(p.fg1).lineLimit(1)
                                    Spacer()
                                    Button { model.removeRule(r.id) } label: {
                                        Icon(name: "trash", size: 13).foregroundStyle(p.danger)
                                    }.buttonStyle(.plain)
                                }
                                .padding(.vertical, 9)
                                Rectangle().fill(p.border).frame(height: 1)
                            }
                        }
                        VStack(spacing: 8) {
                            HStack(spacing: 8) {
                                Picker("", selection: $ruleField) {
                                    ForEach(MailRule.Field.allCases, id: \.self) { Text($0.label).tag($0) }
                                }.labelsHidden().fixedSize()
                                Text("contains").font(.system(size: 12)).foregroundStyle(p.fg3)
                                TextField("text…", text: $ruleValue)
                                    .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(p.fg1)
                                    .padding(.horizontal, 8).padding(.vertical, 6)
                                    .background(p.bg2)
                                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(p.border, lineWidth: 1))
                            }
                            HStack(spacing: 8) {
                                Picker("", selection: $ruleAction) {
                                    ForEach(MailRule.Action.allCases, id: \.self) { Text($0.label).tag($0) }
                                }.labelsHidden().fixedSize()
                                if ruleAction == .label {
                                    Picker("", selection: $ruleLabelId) {
                                        Text("Choose…").tag("")
                                        ForEach(model.labels) { Text($0.name).tag($0.id) }
                                    }.labelsHidden().fixedSize()
                                }
                                Spacer()
                                Button { addRule() } label: {
                                    Text("Add rule").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(p.brandBlue)
                                }
                                .buttonStyle(.plain)
                                .disabled(ruleValue.trimmingCharacters(in: .whitespaces).isEmpty
                                          || (ruleAction == .label && ruleLabelId.isEmpty && model.labels.isEmpty))
                            }
                        }
                        .padding(.top, 8)
                    }
                    section("VIP senders") {
                        if model.vipSenders.isEmpty {
                            Text("No VIPs yet. Mark a sender as VIP from a message's ⋯ menu — their mail is highlighted and never auto-filtered.")
                                .font(.system(size: 13)).foregroundStyle(p.fg3)
                                .fixedSize(horizontal: false, vertical: true).padding(.vertical, 12)
                        } else {
                            let vips = model.vipSenders.sorted()
                            ForEach(Array(vips.enumerated()), id: \.element) { idx, addr in
                                HStack {
                                    Icon(name: "crown", size: 13).foregroundStyle(Color(hex: "F4A52A"))
                                    Text(addr).font(.system(size: 13)).foregroundStyle(p.fg1).lineLimit(1)
                                    Spacer()
                                    Button { model.removeVIP(addr) } label: {
                                        Text("Remove").font(.system(size: 12.5, weight: .medium)).foregroundStyle(p.brandBlue)
                                    }.buttonStyle(.plain)
                                }
                                .padding(.vertical, 10)
                                if idx < vips.count - 1 { Rectangle().fill(p.border).frame(height: 1) }
                            }
                        }
                    }
                    section("Remote images") {
                        if model.trustedImageSenders.isEmpty {
                            Text("No trusted senders. Trust a sender from a blocked-image message's \"Always\" button to auto-load their remote images.")
                                .font(.system(size: 13)).foregroundStyle(p.fg3)
                                .fixedSize(horizontal: false, vertical: true).padding(.vertical, 12)
                        } else {
                            let trusted = TrustedSenders.list(model.trustedImageSenders)
                            ForEach(Array(trusted.enumerated()), id: \.element) { idx, addr in
                                HStack {
                                    Icon(name: "photo", size: 13).foregroundStyle(p.fg3)
                                    Text(addr).font(.system(size: 13)).foregroundStyle(p.fg1).lineLimit(1)
                                    Spacer()
                                    Button { model.untrustImages(addr) } label: {
                                        Text("Stop").font(.system(size: 12.5, weight: .medium)).foregroundStyle(p.brandBlue)
                                    }.buttonStyle(.plain)
                                }
                                .padding(.vertical, 10)
                                if idx < trusted.count - 1 { Rectangle().fill(p.border).frame(height: 1) }
                            }
                        }
                    }
                    section("Blocked contacts") {
                        if model.blockedSenders.isEmpty {
                            Text("No blocked contacts. Block a sender from a message's ⋯ menu — their mail goes straight to Trash.")
                                .font(.system(size: 13)).foregroundStyle(p.fg3)
                                .fixedSize(horizontal: false, vertical: true).padding(.vertical, 12)
                        } else {
                            let blocked = model.blockedSenders.sorted()
                            ForEach(Array(blocked.enumerated()), id: \.element) { idx, addr in
                                HStack {
                                    Icon(name: "spam", size: 13).foregroundStyle(p.danger)
                                    Text(addr).font(.system(size: 13)).foregroundStyle(p.fg1).lineLimit(1)
                                    Spacer()
                                    Button { model.unblockSender(addr) } label: {
                                        Text("Unblock").font(.system(size: 12.5, weight: .medium)).foregroundStyle(p.brandBlue)
                                    }.buttonStyle(.plain)
                                }
                                .padding(.vertical, 10)
                                if idx < blocked.count - 1 { Rectangle().fill(p.border).frame(height: 1) }
                            }
                        }
                    }
                    section("Keyboard & alerts") {
                        toggleRow("Keyboard (vim) navigation", "J / K to move, G-prefix to go to folders, single-key triage.",
                                  on: Binding(get: { model.vimNav }, set: { model.setVimNav($0) }))
                        toggleRow("New-mail notifications", "Show a notification when new mail arrives.",
                                  on: Binding(get: { model.notificationsEnabled }, set: { model.setNotifications($0) }))
                        toggleRow("Confirm before discarding", "Ask before throwing away a draft.",
                                  on: Binding(get: { model.confirmDiscard }, set: { model.setConfirmDiscard($0) }), last: true)
                    }
                }
                .padding(.horizontal, 28).padding(.vertical, 24)
            }
        }
        .frame(width: 720)
        .frame(maxHeight: 620)
        .background(p.bg1)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(p.borderStrong, lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 48, y: 24)
    }

    private func addRule() {
        let labelId = ruleLabelId.isEmpty ? model.labels.first?.id : ruleLabelId
        if model.addRule(field: ruleField, value: ruleValue, action: ruleAction, labelId: labelId) {
            ruleValue = ""
        }
    }

    private func ruleSummary(_ r: MailRule) -> String {
        let act: String
        switch r.action {
        case .trash: act = "→ Trash"
        case .archive: act = "→ Archive"
        case .label: act = "→ \(r.labelId.flatMap { model.label(for: $0)?.name } ?? "Label")"
        }
        return "\(r.field.label) contains \"\(r.value)\"  \(act)"
    }

    private func addNewLabel() {
        let name = newLabelDraft.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        model.addLabel(name)
        newLabelDraft = ""
    }

    /// Display-only advisory: when the proxy toggle is ON but `imageProxyConfig` is
    /// inert, name which sub-condition is failing. Derived from the SAME pure
    /// `ProxyConfigState.classify(...)` result that `imageProxyConfig` consumes
    /// (single source of truth) — `model.hasProxySecret` (= `loadProxySecret() != nil`)
    /// is the same resolved secret state, so this never disagrees with the load path.
    /// Re-derives on `model` changes as the user edits fields. Renders NOTHING in
    /// `.disabled` / `.ok`; calls no setter and triggers no fetch.
    @ViewBuilder
    private var proxyMisconfigWarning: some View {
        let proxyState = ProxyConfigState.classify(
            proxyEnabled: model.proxyEnabled,
            proxyBaseURL: model.proxyBaseURL,
            secretPresent: model.hasProxySecret)
        if proxyState.isWarning {
            HStack(alignment: .top, spacing: 6) {
                Icon(name: "alert", size: 12).foregroundStyle(p.danger).padding(.top, 1)
                Text(proxyWarningMessage(for: proxyState))
                    .font(.system(size: 11.5)).foregroundStyle(p.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func proxyWarningMessage(for state: ProxyConfigState) -> String {
        switch state {
        case .missingURL, .invalidURL, .urlMissingHost:
            return "Proxy is on but the base URL is missing or invalid — remote images will load directly (leaking your IP) until you set a valid https://… URL."
        case .missingSecret:
            return "Proxy is on but the signing secret is missing — remote images will load directly (leaking your IP) until you paste the secret and Save."
        case .disabled, .ok:
            return ""
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 13, weight: .bold)).foregroundStyle(p.fg1).padding(.bottom, 12)
            content()
        }
    }

    private func toggleRow(_ label: String, _ desc: String, on: Binding<Bool>, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.system(size: 13.5, weight: .medium)).foregroundStyle(p.fg1)
                    Text(desc).font(.system(size: 12)).foregroundStyle(p.fg3)
                }
                Spacer()
                MMToggle(on: on)
            }
            .padding(.vertical, 12)
            if !last { Rectangle().fill(p.border).frame(height: 1) }
        }
    }
}

struct LabelEditRow: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p
    let label: MailLabel
    @State private var name = ""
    @State private var colorOpen = false

    private let swatchCols = Array(repeating: GridItem(.fixed(24), spacing: 8), count: 5)

    var body: some View {
        HStack(spacing: 10) {
            Button { colorOpen.toggle() } label: {
                Circle().fill(label.color).frame(width: 16, height: 16)
                    .overlay(Circle().stroke(p.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $colorOpen, arrowEdge: .bottom) { swatches }

            TextField("Label name", text: $name)
                .textFieldStyle(.plain).font(.system(size: 13.5)).foregroundStyle(p.fg1)
                .onSubmit { model.renameLabel(label.id, to: name) }

            Spacer(minLength: 8)
            Button { model.deleteLabel(label.id) } label: {
                Icon(name: "trash", size: 13).foregroundStyle(p.danger)
            }
            .buttonStyle(.plain).help("Delete label")
        }
        .padding(.vertical, 10)
        .onAppear { name = label.name }
        .onChange(of: label.name) { _, v in name = v }
    }

    private var swatches: some View {
        LazyVGrid(columns: swatchCols, spacing: 8) {
            ForEach(AppModel.labelPalette, id: \.self) { hex in
                Button { model.setLabelColor(label.id, hex: hex); colorOpen = false } label: {
                    Circle().fill(Color(hex: hex)).frame(width: 22, height: 22)
                        .overlay(Circle().stroke(label.colorHex == hex ? p.fg1 : Color.clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
    }
}

struct AccountEditRow: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p
    let cfg: MailAccountConfig
    @State private var name = ""
    @State private var colorOpen = false

    private let swatchCols = Array(repeating: GridItem(.fixed(24), spacing: 8), count: 5)

    var body: some View {
        let acct = model.accountsById[cfg.id] ?? AppModel.uiAccount(for: cfg)
        HStack(spacing: 10) {
            GradientTile(colors: acct.gradientColors, text: acct.initials, size: 32, image: acct.avatarImage)

            VStack(alignment: .leading, spacing: 2) {
                TextField("Account name", text: $name)
                    .textFieldStyle(.plain).font(.system(size: 13.5, weight: .medium)).foregroundStyle(p.fg1)
                    .onSubmit { model.renameAccount(cfg.id, to: name) }
                Text("\(cfg.email) · \(cfg.imapHost)").font(.system(size: 12)).foregroundStyle(p.fg3).lineLimit(1)
            }

            Spacer(minLength: 8)

            if cfg.hasCustomAvatar != true {
                Button { colorOpen.toggle() } label: {
                    Circle().fill(acct.color).frame(width: 16, height: 16)
                        .overlay(Circle().stroke(p.border, lineWidth: 1))
                }
                .buttonStyle(.plain).help("Pick avatar color")
                .popover(isPresented: $colorOpen, arrowEdge: .bottom) { swatches }
            }

            Button { chooseImage() } label: {
                Text("Choose image…").font(.system(size: 12.5, weight: .medium)).foregroundStyle(p.fg2)
                    .padding(.horizontal, 10).frame(height: 30)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(p.border, lineWidth: 1))
            }.buttonStyle(.plain)

            if cfg.hasCustomAvatar == true {
                Button { model.removeAccountImage(cfg.id) } label: {
                    Text("Use letters").font(.system(size: 12.5, weight: .medium)).foregroundStyle(p.fg2)
                        .padding(.horizontal, 10).frame(height: 30)
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(p.border, lineWidth: 1))
                }.buttonStyle(.plain)
            }

            Button { model.loadFolder(cfg.id, "inbox", force: true) } label: {
                HStack(spacing: 6) { Icon(name: "refresh", size: 14); Text("Resync").font(.system(size: 12.5, weight: .medium)) }
                    .foregroundStyle(p.fg2).padding(.horizontal, 10).frame(height: 30)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(p.border, lineWidth: 1))
            }.buttonStyle(.plain)

            Button { model.removeRealAccount(cfg.id) } label: {
                Text("Remove").font(.system(size: 12.5, weight: .medium)).foregroundStyle(p.danger)
                    .padding(.horizontal, 10).frame(height: 30)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(p.danger.opacity(0.4), lineWidth: 1))
            }.buttonStyle(.plain)
        }
        .padding(.vertical, 12)
        .onAppear { name = cfg.displayName }
        .onChange(of: cfg.displayName) { _, v in name = v }
    }

    private var swatches: some View {
        LazyVGrid(columns: swatchCols, spacing: 8) {
            ForEach(AppModel.labelPalette, id: \.self) { hex in
                Button { model.setAccountColor(cfg.id, hex: hex); colorOpen = false } label: {
                    Circle().fill(Color(hex: hex)).frame(width: 22, height: 22)
                        .overlay(Circle().stroke(cfg.avatarColorHex == hex ? p.fg1 : Color.clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK,
              let url = panel.url,
              let img = NSImage(contentsOf: url) else { return }
        model.setAccountImage(cfg.id, img)
    }
}

/// Editing row for the unified "All" inbox — mirrors `AccountEditRow` but has no
/// `cfg`, Resync, or Remove (the unified inbox is not a removable server account).
struct AllInboxEditRow: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p
    @State private var name = ""
    @State private var colorOpen = false

    private let swatchCols = Array(repeating: GridItem(.fixed(24), spacing: 8), count: 5)

    var body: some View {
        HStack(spacing: 10) {
            GradientTile(colors: model.allInboxColorHex.map { [Color(hex: $0)] } ?? [p.magenta],
                         text: model.allInboxSpec.tileText, size: 32, image: model.allInboxImage)

            VStack(alignment: .leading, spacing: 2) {
                TextField("All inboxes", text: $name)
                    .textFieldStyle(.plain).font(.system(size: 13.5, weight: .medium)).foregroundStyle(p.fg1)
                    .onSubmit { model.setAllInboxName(name) }
                Text("Unified inbox").font(.system(size: 12)).foregroundStyle(p.fg3).lineLimit(1)
            }

            Spacer(minLength: 8)

            if !model.allInboxHasImage {
                Button { colorOpen.toggle() } label: {
                    Circle().fill(model.allInboxColorHex.map { Color(hex: $0) } ?? p.magenta).frame(width: 16, height: 16)
                        .overlay(Circle().stroke(p.border, lineWidth: 1))
                }
                .buttonStyle(.plain).help("Pick avatar color")
                .popover(isPresented: $colorOpen, arrowEdge: .bottom) { swatches }
            }

            Button { chooseImage() } label: {
                Text("Choose image…").font(.system(size: 12.5, weight: .medium)).foregroundStyle(p.fg2)
                    .padding(.horizontal, 10).frame(height: 30)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(p.border, lineWidth: 1))
            }.buttonStyle(.plain)

            if model.allInboxHasImage {
                Button { model.removeAllInboxImage() } label: {
                    Text("Use letters").font(.system(size: 12.5, weight: .medium)).foregroundStyle(p.fg2)
                        .padding(.horizontal, 10).frame(height: 30)
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(p.border, lineWidth: 1))
                }.buttonStyle(.plain)
            }
        }
        .padding(.vertical, 12)
        .onAppear { name = model.allInboxName }
    }

    private var swatches: some View {
        LazyVGrid(columns: swatchCols, spacing: 8) {
            ForEach(AppModel.labelPalette, id: \.self) { hex in
                Button { model.setAllInboxColor(hex); colorOpen = false } label: {
                    Circle().fill(Color(hex: hex)).frame(width: 22, height: 22)
                        .overlay(Circle().stroke(model.allInboxColorHex == hex ? p.fg1 : Color.clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK,
              let url = panel.url,
              let img = NSImage(contentsOf: url) else { return }
        model.setAllInboxImage(img)
    }
}

struct MMToggle: View {
    @Environment(\.palette) private var p
    @Binding var on: Bool
    var body: some View {
        Button { on.toggle() } label: {
            ZStack(alignment: on ? .trailing : .leading) {
                Capsule().fill(on ? p.success : p.bg4).frame(width: 36, height: 20)
                Circle().fill(.white).frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                    .padding(2)
            }
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: on)
    }
}

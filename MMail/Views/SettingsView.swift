import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p
    @State private var newLabelDraft = ""

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
                    section("Accounts") {
                        if model.realConfigs.isEmpty {
                            Text("No account connected.").font(.system(size: 13)).foregroundStyle(p.fg3).padding(.vertical, 12)
                        } else {
                            ForEach(Array(model.realConfigs.enumerated()), id: \.element.id) { idx, cfg in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(cfg.email).font(.system(size: 13.5, weight: .medium)).foregroundStyle(p.fg1)
                                        Text("\(cfg.imapHost) · IMAP/SMTP").font(.system(size: 12)).foregroundStyle(p.fg3)
                                    }
                                    Spacer()
                                    Button { model.loadFolder(cfg.id, "inbox") } label: {
                                        HStack(spacing: 6) { Icon(name: "refresh", size: 14); Text("Resync").font(.system(size: 12.5, weight: .medium)) }
                                            .foregroundStyle(p.fg2).padding(.horizontal, 10).frame(height: 30)
                                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(p.border, lineWidth: 1))
                                    }.buttonStyle(.plain)
                                    Button { model.removeRealAccount(cfg.id) } label: {
                                        Text("Remove").font(.system(size: 12.5, weight: .medium)).foregroundStyle(p.danger)
                                            .padding(.horizontal, 10).frame(height: 30)
                                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(p.danger.opacity(0.4), lineWidth: 1))
                                    }.buttonStyle(.plain)
                                }.padding(.vertical, 12)
                                if idx < model.realConfigs.count - 1 { Rectangle().fill(p.border).frame(height: 1) }
                            }
                        }
                        Rectangle().fill(p.border).frame(height: 1)
                        Button { model.settings = false; model.addingAccount = true } label: {
                            HStack(spacing: 6) { Icon(name: "plus", size: 13); Text("Add account").font(.system(size: 12.5, weight: .semibold)) }
                                .foregroundStyle(p.brandBlue)
                        }.buttonStyle(.plain).padding(.vertical, 12)
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

    private func addNewLabel() {
        let name = newLabelDraft.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        model.addLabel(name)
        newLabelDraft = ""
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

import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p
    @State private var hoveredFolder: String?

    private let folderIcons: [String: String] = [
        "home": "home", "inbox": "inbox", "starred": "star", "snoozed": "clock",
        "done": "done", "archive": "archive", "sent": "send", "outbox": "outbox", "drafts": "draft", "spam": "spam", "trash": "trash"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            composeButton
                .padding(.horizontal, 4)
                .padding(.top, 8)
                .padding(.bottom, 16)

            VStack(spacing: 1) {
                // Home is the cross-account dashboard (weather, contacts,
                // journal, todos), so it only makes sense in the unified
                // "All inboxes" scope. Hide it when a specific account is
                // selected.
                ForEach(SampleData.folders.filter { f in
                    f.id != "home" || model.currentAccount == "all"
                }) { f in
                    folderRow(f)
                }
            }

            if model.folder != "home" {
                Text("LABELS")
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(p.fg4)
                    .padding(.horizontal, 12)
                    .padding(.top, 18)
                    .padding(.bottom, 6)

                ForEach(model.labels) { l in
                    labelRow(l)
                }
            }

            Spacer(minLength: 8)

            footer
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .frame(width: 232)
        .frame(maxHeight: .infinity)
        .background(p.bg1)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(p.border, lineWidth: 1))
        .shadow(color: .black.opacity(p.isDark ? 0.4 : 0.06), radius: 4, y: 1)
        .padding(EdgeInsets(top: 10, leading: 6, bottom: 10, trailing: 10))
    }

    private var composeButton: some View {
        Button { model.startCompose() } label: {
            HStack {
                Icon(name: "pencil", size: 16)
                Text("Compose").font(.system(size: 13.5, weight: .semibold))
                Spacer()
                Kbd("C", onAccent: true)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .frame(maxWidth: .infinity)
            .background(p.brandBlue)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Compose (C)")
    }

    private func folderRow(_ f: Folder) -> some View {
        let active = model.folder == f.id
        let hovered = hoveredFolder == f.id
        let count = f.id == "outbox" ? (model.scheduled.count + model.sending.count) : (model.unreadCounts[f.id] ?? 0)
        return Button { model.setFolder(f.id) } label: {
            HStack(spacing: 10) {
                Icon(name: folderIcons[f.id] ?? "mail", size: 16)
                Text(f.name).font(.system(size: 13, weight: .medium))
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(active ? p.brandBlue.opacity(0.7) : p.fg3)
                } else if let sc = f.shortcut, hovered {
                    Text(sc)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(p.fg4)
                }
            }
            .foregroundStyle(active ? p.activeFolderText : (hovered ? p.fg1 : p.fg2))
            .padding(.horizontal, 10)
            .frame(height: 30)
            .frame(maxWidth: .infinity)
            .background(active ? p.brandBlue100 : (hovered ? p.bg3 : Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hoveredFolder = $0 ? f.id : (hoveredFolder == f.id ? nil : hoveredFolder) }
    }

    private func labelRow(_ l: MailLabel) -> some View {
        let active = model.labelFilter == l.id
        let hovered = hoveredFolder == "label:\(l.id)"
        return Button { model.selectLabel(l.id) } label: {
            HStack(spacing: 10) {
                Circle().fill(l.color).frame(width: 8, height: 8)
                Text(l.name).font(.system(size: 12.5)).foregroundStyle(active ? p.activeFolderText : p.fg2).lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 26)
            .frame(maxWidth: .infinity)
            .background(active ? p.brandBlue100 : (hovered ? p.bg3 : Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hoveredFolder = $0 ? "label:\(l.id)" : (hoveredFolder == "label:\(l.id)" ? nil : hoveredFolder) }
    }

    private var footer: some View {
        let isAll = model.currentAccount == "all"
        let acct = model.accountsById[model.currentAccount]
        return HStack(spacing: 8) {
            HStack(spacing: 10) {
                GradientTile(colors: isAll ? [Color(hex: "2D3DEC"), Color(hex: "7A5AE0")] : (acct?.gradientColors ?? []),
                             text: isAll ? "M" : (acct?.initials ?? "M"),
                             size: 28, cornerRadius: 14, fontSize: 11)
                VStack(alignment: .leading, spacing: 0) {
                    Text(isAll ? "All inboxes" : (acct?.name ?? "")).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(p.fg1)
                    Text(isAll ? "Unified view" : (acct?.email ?? "")).font(.system(size: 11)).foregroundStyle(p.fg3)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            Button { model.help = true } label: { Icon(name: "command", size: 14).foregroundStyle(p.fg2) }
                .buttonStyle(.plain).help("Shortcuts (?)")
            Button { model.settings = true } label: { Icon(name: "settings", size: 14).foregroundStyle(p.fg2) }
                .buttonStyle(.plain).help("Settings")
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }
}

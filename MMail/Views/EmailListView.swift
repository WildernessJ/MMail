import SwiftUI

struct EmailListView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p

    private var isSearch: Bool {
        model.searchActive && !model.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
    }
    private var folderName: String {
        SampleData.folders.first { $0.id == model.folder }?.name ?? model.folder
    }
    private var scopeLoading: Bool {
        model.currentAccount == "all" ? !model.loadingAccounts.isEmpty : model.loadingAccounts.contains(model.currentAccount)
    }
    private var scopeIsRealMail: Bool {
        model.isRealAccount(model.currentAccount) || (model.currentAccount == "all" && !model.realConfigs.isEmpty)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(p.border)
            if model.selectionActive {
                selectionBar
                Divider().overlay(p.border)
            }
            list
        }
        .frame(width: model.readingPane ? 380 : nil)
        .frame(maxWidth: model.readingPane ? 380 : .infinity, maxHeight: .infinity)
        .background(p.bg1)
        .overlay(Rectangle().fill(p.border).frame(width: 1), alignment: .trailing)
    }

    // MARK: Header

    private var header: some View {
        let visible = model.filteredEmails
        let unread = visible.filter { $0.unread }.count
        let acctName = model.currentAccount == "all" ? "All inboxes" : (model.accountsById[model.currentAccount]?.name ?? folderName)
        let labelName = model.labelFilter.flatMap { model.label(for: $0)?.name }
        let title = isSearch ? "Search" : (labelName ?? (model.folder == "inbox" ? acctName : folderName))
        let sub: String = {
            if isSearch {
                let n = visible.count
                return "\(n) result\(n == 1 ? "" : "s") for \"\(model.searchQuery)\""
            }
            if labelName != nil {
                let n = visible.count
                return "\(n) \(n == 1 ? "message" : "messages") · label"
            }
            if model.folder == "inbox" {
                return unread > 0 ? "\(unread) unread · \(greeting())" : "Inbox zero · \(greeting())"
            }
            let n = visible.count
            return "\(n) \(n == 1 ? "message" : "messages")"
        }()

        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 22, weight: .bold))
                    .foregroundStyle(p.fg1)
                Spacer()
                if scopeIsRealMail {
                    Button { model.refreshCurrentRealFolder() } label: {
                        if scopeLoading {
                            ProgressView().controlSize(.small)
                        } else {
                            Icon(name: "refresh", size: 14).foregroundStyle(p.fg3)
                        }
                    }
                    .buttonStyle(.plain).help("Refresh")
                }
            }
            HStack(spacing: 6) {
                Text(sub).font(.system(size: 12.5)).foregroundStyle(p.fg3)
                if model.searching {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                    Text("searching all mail…").font(.system(size: 11.5)).foregroundStyle(p.fg4)
                }
            }
            if model.folder == "inbox" && !isSearch && model.labelFilter == nil {
                HStack(spacing: 4) {
                    ForEach(InboxFilter.allCases, id: \.self) { f in
                        filterChip(f)
                    }
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var selectionBar: some View {
        HStack(spacing: 6) {
            Text("\(model.selectedIds.count) selected")
                .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(p.fg1)
            Button { model.selectAllVisible() } label: {
                Text("Select all").font(.system(size: 11.5)).foregroundStyle(p.brandBlue)
            }.buttonStyle(.plain)
            Spacer()
            bulkButton("check", "Done") { model.bulkDone() }
            bulkButton("archive", "Archive") { model.bulkArchive() }
            let moveAcct = model.currentAccount == "all"
                ? (model.emails.first { model.selectedIds.contains($0.id) }?.account ?? "")
                : model.currentAccount
            let folders = model.folderNames(for: moveAcct)
            if !folders.isEmpty {
                Menu {
                    ForEach(folders, id: \.self) { name in
                        Button(name) { model.bulkMoveToMailbox(name) }
                    }
                } label: {
                    Icon(name: "outbox", size: 14).foregroundStyle(p.fg2).frame(width: 28, height: 26)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Move to…")
            }
            bulkButton("mail", "Read") { model.bulkMarkRead(true) }
            bulkButton("trash", "Delete") { model.bulkDelete() }
            Button { model.clearSelection() } label: {
                Icon(name: "x", size: 13).foregroundStyle(p.fg3).frame(width: 26, height: 26)
            }.buttonStyle(.plain).help("Clear selection (esc)")
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
        .background(p.bg2)
    }

    private func bulkButton(_ icon: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Icon(name: icon, size: 14).foregroundStyle(p.fg2).frame(width: 28, height: 26)
        }
        .buttonStyle(.plain).help(help)
    }

    private func filterChip(_ f: InboxFilter) -> some View {
        let active = model.filter == f
        return Button { model.filter = f } label: {
            Text(f.title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(active ? p.fg1 : p.fg3)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(active ? p.bg3 : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: List

    private var list: some View {
        let visible = model.filteredEmails
        return Group {
            if visible.isEmpty && scopeLoading {
                loadingState
            } else if visible.isEmpty, let err = model.accountErrors[model.currentAccount] {
                errorState(err)
            } else if visible.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0, pinnedViews: []) {
                            ForEach(groupByDay(visible), id: \.0) { day, items in
                                Text(day.uppercased())
                                    .font(.system(size: 10.5, weight: .bold))
                                    .tracking(0.6)
                                    .foregroundStyle(p.fg4)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 20)
                                    .padding(.top, 14)
                                    .padding(.bottom, 6)
                                ForEach(items) { e in
                                    EmailRowView(email: e,
                                                 selected: e.id == model.selectedEmail?.id,
                                                 showAccountDot: model.currentAccount == "all",
                                                 accountColor: model.accountsById[e.account]?.color)
                                        .id(e.id)
                                }
                            }
                            if model.canLoadMore || model.downloadingAllOlder {
                                loadOlderFooter
                            }
                        }
                    }
                    .onChange(of: model.selectedId) { _, id in
                        if let id { withAnimation { proxy.scrollTo(id, anchor: .center) } }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.large)
            Text("Connecting…").font(.system(size: 13.5)).foregroundStyle(p.fg3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 10) {
            Icon(name: "alert", size: 32, weight: .light).foregroundStyle(p.danger)
            Text("Couldn't connect").font(.system(size: 18, weight: .bold)).foregroundStyle(p.fg2)
            Text(message).font(.system(size: 12.5)).foregroundStyle(p.fg3)
                .multilineTextAlignment(.center).frame(maxWidth: 320)
            Button { model.refreshCurrentRealFolder() } label: {
                Text("Retry").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(p.brandBlue).clipShape(Capsule())
            }.buttonStyle(.plain).padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(40)
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Icon(name: "done", size: 36, weight: .light)
                .foregroundStyle(p.fg2)
            Text(model.folder == "inbox" ? "You're all caught up" : "Nothing here")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(p.fg2)
                .padding(.top, 16).padding(.bottom, 8)
            Text(model.folder == "inbox"
                 ? "No new mail in your inbox. Take a break, or press C to write something."
                 : "No messages in \(folderName.lowercased()).")
                .font(.system(size: 13.5))
                .foregroundStyle(p.fg3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            if model.canLoadMore || model.downloadingAllOlder {
                loadOlderFooter
                    .padding(.top, 22)
                    .frame(maxWidth: 360)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    /// Shared footer shown both below the inbox list and inside the empty
    /// state: "Load older messages" for one page + "Download all older
    /// messages" for an automated recursive backfill. Swaps to a progress
    /// line with a Cancel button while a recursive download is running.
    private var loadOlderFooter: some View {
        VStack(spacing: 6) {
            if model.downloadingAllOlder {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Downloading messages older than a month… \(model.olderDownloadedCount) downloaded")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(p.fg2)
                        .multilineTextAlignment(.center)
                }
                Button("Cancel") { model.cancelLoadAllOlder() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(p.brandBlue)
            } else {
                Button { model.loadOlder() } label: {
                    HStack(spacing: 6) {
                        if model.loadingOlder { ProgressView().controlSize(.small) }
                        Text(model.loadingOlder ? "Loading older than a month…" : "Load mail older than a month")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(p.brandBlue)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .disabled(model.loadingOlder)

                Button { model.loadAllOlder() } label: {
                    Text("Download all mail older than a month")
                        .font(.system(size: 11.5))
                        .foregroundStyle(p.fg3)
                        .underline()
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .disabled(model.loadingOlder)
            }
        }
        .padding(.vertical, 10)
    }

    // MARK: Grouping

    private func groupByDay(_ emails: [Email]) -> [(String, [Email])] {
        let order = ["today", "yesterday", "earlier", "snoozed"]
        let labels = ["today": "Today", "yesterday": "Yesterday", "earlier": "Earlier", "snoozed": "Snoozed"]
        var buckets: [String: [Email]] = [:]
        for e in emails { buckets[e.day, default: []].append(e) }
        return order.compactMap { key in
            guard let items = buckets[key], !items.isEmpty else { return nil }
            return (labels[key] ?? key, items)
        }
    }
}

func greeting() -> String {
    let h = Calendar.current.component(.hour, from: Date())
    if h < 5 { return "burning the midnight oil" }
    if h < 12 { return "good morning" }
    if h < 18 { return "good afternoon" }
    return "good evening"
}

// MARK: - Email row

struct EmailRowView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p
    let email: Email
    let selected: Bool
    let showAccountDot: Bool
    let accountColor: Color?
    @State private var hovered = false

    private var sender: Sender? { email.resolvedSender }

    private var bulkSelected: Bool { model.selectedIds.contains(email.id) }

    /// Outgoing folders show the recipient; everything else shows the sender.
    private var displayName: String {
        if ["sent", "drafts", "outbox"].contains(email.folder) {
            guard let to = email.to?.first, !to.isEmpty else { return "(no recipient)" }
            if let lt = to.firstIndex(of: "<") {
                let name = String(to[..<lt]).trimmingCharacters(in: .whitespaces)
                return name.isEmpty ? to.trimmingCharacters(in: CharacterSet(charactersIn: "<> ")) : name
            }
            return to
        }
        return sender?.name ?? (email.to?.first ?? "You")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if hovered || model.selectionActive {
                Button { model.toggleSelect(email.id) } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(bulkSelected ? p.brandBlue : Color.clear)
                            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(bulkSelected ? p.brandBlue : p.borderStrong, lineWidth: 1.5))
                            .frame(width: 18, height: 18)
                        if bulkSelected { Icon(name: "check", size: 11, weight: .bold).foregroundStyle(.white) }
                    }
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 7)
            }
            HStack(alignment: .top, spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    HStack(spacing: 6) {
                        if showAccountDot, let c = accountColor {
                            Circle().fill(c).frame(width: 6, height: 6)
                        }
                        if model.isVIP(email.fromEmail) {
                            Icon(name: "crown", size: 10).foregroundStyle(Color(hex: "F4A52A"))
                        }
                        Text(displayName)
                            .font(.system(size: 13.5, weight: email.unread ? .bold : .semibold))
                            .foregroundStyle(email.unread ? p.fg1 : p.fg2)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if email.starred {
                        Icon(name: "star.fill", size: 10).foregroundStyle(Color(hex: "F4A52A"))
                    }
                    Text(email.time)
                        .font(.system(size: 11.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(email.unread ? p.brandBlue : p.fg3)
                }
                Text(email.subject)
                    .font(.system(size: 13, weight: email.unread ? .bold : .regular))
                    .foregroundStyle(email.unread ? p.fg1 : p.fg2)
                    .lineLimit(1)
                Text(email.preview)
                    .font(.system(size: 12.5))
                    .foregroundStyle(p.fg3)
                    .lineLimit(2)
                    .lineSpacing(1)
                if !email.labels.isEmpty || email.hasAttachment {
                    HStack(spacing: 6) {
                        if email.hasAttachment {
                            Icon(name: "attach", size: 12).foregroundStyle(p.fg3)
                        }
                        ForEach(email.labels, id: \.self) { l in
                            if let def = model.label(for: l) {
                                Pill(label: def.name, kind: l, colorHex: def.colorHex)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                if model.selectionActive { model.toggleSelect(email.id) } else { model.activate(email.id) }
            }
            if hovered || selected {
                VStack {
                    HStack(spacing: 2) {
                        rowAction(email.starred ? "star.fill" : "star", help: "Star (S)") { model.toggleStar(email.id) }
                        rowAction("check", help: "Mark as done (H)") { model.markDone(email.id) }
                        rowAction("archive", help: "Archive (E)") { model.archive(email.id) }
                    }
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(rowBackground)
        .overlay(alignment: .leading) {
            if selected {
                Rectangle().fill(p.brandBlue).frame(width: 3)
                    .padding(.vertical, 8)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            }
        }
        .overlay(Rectangle().fill(p.border).frame(height: 1), alignment: .bottom)
        .onHover { hovered = $0 }
    }

    private var avatar: some View {
        Avatar(sender: sender, size: 36)
    }

    private var rowBackground: Color {
        if bulkSelected { return p.brandBlue100 }
        if selected { return p.brandBlue100 }
        if hovered { return p.bg2 }
        return p.bg1
    }

    private func rowAction(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Icon(name: icon, size: 14)
                .foregroundStyle(p.fg3)
                .frame(width: 26, height: 26)
                .background(p.bg3.opacity(0.0001))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

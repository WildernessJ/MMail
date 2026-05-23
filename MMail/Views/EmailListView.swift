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
                            if model.canLoadMore {
                                Button { model.loadMore() } label: {
                                    Text("Load more")
                                        .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(p.brandBlue)
                                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                                }
                                .buttonStyle(.plain)
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
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

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    HStack(spacing: 6) {
                        if showAccountDot, let c = accountColor {
                            Circle().fill(c).frame(width: 6, height: 6)
                        }
                        Text(sender?.name ?? (email.to?.first ?? "You"))
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
        .contentShape(Rectangle())
        .onTapGesture { model.select(email.id) }
        .onHover { hovered = $0 }
    }

    private var avatar: some View {
        Avatar(sender: sender, size: 36)
    }

    private var rowBackground: Color {
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

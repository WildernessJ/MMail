import SwiftUI

struct ReaderView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p

    var body: some View {
        Group {
            if let email = model.selectedEmail {
                reader(email)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(p.bg1)
    }

    private func reader(_ email: Email) -> some View {
        let account = model.accountsById[email.account]
        let sender = SampleData.senders[email.from]
        return VStack(spacing: 0) {
            toolbar
            Divider().overlay(p.border)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(email.subject)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(p.fg1)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 20)

                    metaRow(email: email, sender: sender, account: account)
                        .padding(.bottom, 24)
                    Divider().overlay(p.border)

                    Text(email.body)
                        .font(.system(size: 15))
                        .foregroundStyle(p.fg1)
                        .lineSpacing(5)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 28)

                    if let thread = email.thread, !thread.isEmpty {
                        threadSection(thread)
                    }

                    replyStrip(sender: sender)
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, 56)
                .padding(.top, 32)
                .padding(.bottom, 80)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 4) {
            rtb("archive", "Archive", kbd: "E") { model.archive() }
            rtb("check", "Done", kbd: "H") { model.markDone() }
            rtb("clock", "Snooze", kbd: nil) { model.snooze() }
            rtb("trash", "Delete", kbd: "#") { model.delete() }
            Rectangle().fill(p.border).frame(width: 1, height: 18).padding(.horizontal, 6)
            rtb("reply", "Reply", kbd: "R") { model.reply() }
            rtb("replyAll", "Reply all", kbd: nil) { model.replyAll() }
            rtb("forward", "Forward", kbd: "F") { model.forward() }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    private func rtb(_ icon: String, _ label: String, kbd: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Icon(name: icon, size: 15)
                Text(label).font(.system(size: 12.5, weight: .medium))
                if let kbd { Kbd(kbd) }
            }
            .foregroundStyle(p.fg2)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Meta

    private func metaRow(email: Email, sender: Sender?, account: Account?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Avatar(sender: sender, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(sender?.name ?? (email.to?.first ?? "You"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(p.fg1).lineLimit(1)
                if let s = sender, !s.email.isEmpty {
                    Text(s.email).font(.system(size: 12)).foregroundStyle(p.fg3).lineLimit(1)
                }
                Text(toLine(email: email, account: account))
                    .font(.system(size: 12)).foregroundStyle(p.fg3).lineLimit(1)
                if let account {
                    HStack(spacing: 6) {
                        GradientTile(colors: account.gradientColors, text: account.initials,
                                     size: 14, cornerRadius: 4, fontSize: 9)
                        Text(account.name).font(.system(size: 11.5, weight: .medium)).foregroundStyle(p.fg2)
                    }
                    .padding(.leading, 5).padding(.trailing, 9).padding(.vertical, 3)
                    .background(p.bg3)
                    .clipShape(Capsule())
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 12)
            Text(email.day == "today" ? "Today, \(email.time)" : email.time)
                .font(.system(size: 12)).monospacedDigit()
                .foregroundStyle(p.fg3)
        }
    }

    private func toLine(email: Email, account: Account?) -> String {
        var s = "to \(account?.email ?? "me")"
        if let to = email.to, !to.isEmpty {
            s += ", " + to.prefix(2).joined(separator: ", ")
        }
        return s
    }

    // MARK: Thread

    private func threadSection(_ thread: [ThreadItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("EARLIER IN THIS THREAD")
                .font(.system(size: 11, weight: .bold)).tracking(0.6)
                .foregroundStyle(p.fg4)
                .padding(.bottom, 4)
            ForEach(thread) { t in
                let isYou = t.from == "you"
                let s = isYou ? nil : SampleData.senders[t.from]
                HStack(spacing: 12) {
                    if isYou {
                        GradientTile(colors: [Color(hex: "2D3DEC"), Color(hex: "7A5AE0")], text: "Y", size: 28, cornerRadius: 14, fontSize: 11)
                    } else {
                        Avatar(sender: s, size: 28)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isYou ? "You" : (s?.name ?? "")).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(p.fg1)
                        Text(t.preview).font(.system(size: 12.5)).foregroundStyle(p.fg3).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(t.time).font(.system(size: 11)).monospacedDigit().foregroundStyle(p.fg4)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(p.bg2)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(p.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(.top, 32)
        .overlay(Rectangle().fill(p.border).frame(height: 1), alignment: .top)
        .padding(.top, 0)
    }

    // MARK: Reply strip

    private func replyStrip(sender: Sender?) -> some View {
        Button { model.reply() } label: {
            HStack(spacing: 12) {
                Icon(name: "reply", size: 16).foregroundStyle(p.fg3)
                Text("Reply to \(sender?.firstName ?? "sender")…")
                    .font(.system(size: 13)).foregroundStyle(p.fg3)
                Spacer()
                Kbd("R")
            }
            .padding(16)
            .background(p.bg2)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(p.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.top, 24)
    }

    // MARK: Empty

    private var emptyState: some View {
        VStack(spacing: 8) {
            Icon(name: "mail", size: 48, weight: .light).foregroundStyle(p.fg3.opacity(0.5))
            Text("Select a message to read").font(.system(size: 13.5)).foregroundStyle(p.fg3)
            HStack(spacing: 8) {
                Kbd("J"); Kbd("K")
                Text("to navigate").font(.system(size: 11.5)).foregroundStyle(p.fg3)
            }
            .padding(.top, 8)
        }
    }
}

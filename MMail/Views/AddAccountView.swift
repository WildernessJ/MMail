import SwiftUI

struct AddAccountView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p

    struct Provider: Identifiable { let id: String; let name: String; let subtitle: String; let color: String; let initial: String }
    private let providers: [Provider] = [
        Provider(id: "google", name: "Google Workspace", subtitle: "Gmail, Workspace", color: "EA4335", initial: "G"),
        Provider(id: "icloud", name: "iCloud", subtitle: "@icloud.com", color: "1A1A1A", initial: "iC"),
        Provider(id: "outlook", name: "Outlook", subtitle: "Microsoft 365", color: "0078D4", initial: "O"),
        Provider(id: "fastmail", name: "Fastmail", subtitle: "fastmail.com", color: "5B9BD5", initial: "F"),
        Provider(id: "imap", name: "IMAP / SMTP", subtitle: "Custom server", color: "6B7088", initial: "@")
    ]
    private let gradients: [[String]] = [
        ["06B6D4", "0EA5E9"], ["1FB36B", "0F8A4D"], ["F4A52A", "C97A0E"], ["D946EF", "A21CAF"]
    ]

    @State private var step = 0  // 0 pick, 1 connect
    @State private var provider: Provider?
    @State private var email = ""

    private func finish() {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let acct = Account(
            id: "acct-\(Int(Date().timeIntervalSince1970 * 1000))",
            name: trimmed.split(separator: "@").first.map(String.init) ?? "New account",
            email: trimmed,
            initials: String(trimmed.prefix(1)).uppercased(),
            gradient: gradients.randomElement() ?? ["06B6D4", "0EA5E9"],
            colorHex: "0EA5E9",
            provider: provider?.name ?? "IMAP"
        )
        model.addAccount(acct)
    }

    var body: some View {
        ZStack(alignment: .top) {
            OverlayBackdrop { model.addingAccount = false }
            sheet.padding(.top, 88)
        }
    }

    private var sheet: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Icon(name: "user", size: 20).foregroundStyle(p.fg1)
                Text(step == 0 ? "Add an account" : "Connect \(provider?.name ?? "")")
                    .font(.system(size: 18, weight: .bold)).foregroundStyle(p.fg1)
                Spacer()
                Button { model.addingAccount = false } label: { Icon(name: "x", size: 16).foregroundStyle(p.fg2) }.buttonStyle(.plain)
            }
            .padding(.horizontal, 28).padding(.vertical, 20)
            .overlay(Rectangle().fill(p.border).frame(height: 1), alignment: .bottom)

            VStack(alignment: .leading, spacing: 8) {
                if step == 0 {
                    ForEach(providers) { pr in
                        Button { provider = pr; step = 1 } label: {
                            HStack(spacing: 12) {
                                Text(pr.initial)
                                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                                    .frame(width: 32, height: 32).background(Color(hex: pr.color))
                                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(pr.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(p.fg1)
                                    Text(pr.subtitle).font(.system(size: 12)).foregroundStyle(p.fg3)
                                }
                                Spacer()
                                Icon(name: "arrowRight", size: 16).foregroundStyle(p.fg3)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(p.borderStrong, lineWidth: 1))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(HoverBorderButtonStyle())
                    }
                } else {
                    Text("Email address").font(.system(size: 12, weight: .medium)).foregroundStyle(p.fg3)
                    TextField("name@\(provider?.id == "imap" ? "example.com" : (provider?.id ?? "") + ".com")", text: $email)
                        .textFieldStyle(.plain).font(.system(size: 14))
                        .padding(.horizontal, 12).frame(height: 40)
                        .background(p.bg2)
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(p.border, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .onSubmit { finish() }
                    HStack {
                        Spacer()
                        Button { step = 0 } label: {
                            Text("Back").font(.system(size: 13)).foregroundStyle(p.fg2)
                                .padding(.horizontal, 12).frame(height: 32)
                        }.buttonStyle(.plain)
                        Button(action: finish) {
                            Text("Connect").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                                .padding(.horizontal, 14).frame(height: 32)
                                .background(email.trimmingCharacters(in: .whitespaces).isEmpty ? p.fg4 : p.brandBlue)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }.buttonStyle(.plain)
                        .disabled(email.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.top, 4)
                    Text("MMail uses OAuth where available. Your password is never stored on our servers.")
                        .font(.system(size: 11.5)).foregroundStyle(p.fg3)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 28).padding(.vertical, 24)
        }
        .frame(width: 460)
        .background(p.bg1)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(p.borderStrong, lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 48, y: 24)
    }
}

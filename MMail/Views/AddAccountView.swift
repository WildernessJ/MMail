import SwiftUI

struct AddAccountView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p

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
                Text("Add an account").font(.system(size: 18, weight: .bold)).foregroundStyle(p.fg1)
                Spacer()
                Button { model.addingAccount = false } label: { Icon(name: "x", size: 16).foregroundStyle(p.fg2) }.buttonStyle(.plain)
            }
            .padding(.horizontal, 28).padding(.vertical, 20)
            .overlay(Rectangle().fill(p.border).frame(height: 1), alignment: .bottom)

            VStack(alignment: .leading, spacing: 8) {
                Text("Pick your provider — we'll fill in the server settings so you just enter your email and password.")
                    .font(.system(size: 12.5)).foregroundStyle(p.fg3)
                    .padding(.bottom, 4)
                ForEach(MailProvider.all) { pr in
                    providerRow(pr)
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

    private func providerRow(_ pr: MailProvider) -> some View {
        Button { model.openSetup(pr) } label: {
            HStack(spacing: 12) {
                if pr.isCustom {
                    Icon(name: "settings", size: 18).foregroundStyle(p.fg1).frame(width: 32, height: 32)
                } else {
                    Text(pr.initial)
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 32, height: 32).background(Color(hex: pr.colorHex))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(pr.isCustom ? "Other" : pr.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(p.fg1)
                    Text(pr.isCustom ? "Custom IMAP / SMTP server" : "\(pr.imapHost) · IMAP/SMTP")
                        .font(.system(size: 12)).foregroundStyle(p.fg3)
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
}

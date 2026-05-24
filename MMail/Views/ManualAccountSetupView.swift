import SwiftUI

struct ManualAccountSetupView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p

    @State private var provider: MailProvider = .custom
    @State private var showAdvanced = false

    @State private var displayName = ""
    @State private var email = ""
    @State private var lastEmail = ""
    @State private var imapHost = ""
    @State private var imapPort = "993"
    @State private var imapSecurity: ConnectionSecurity = .tls
    @State private var imapUsername = ""
    @State private var imapPassword = ""
    @State private var smtpHost = ""
    @State private var smtpPort = "465"
    @State private var smtpSecurity: ConnectionSecurity = .tls
    @State private var smtpUsername = ""
    @State private var smtpPassword = ""
    @State private var sameCredentials = true

    @State private var connecting = false
    @State private var error: String?

    private func applyProvider(_ pr: MailProvider) {
        provider = pr
        if !pr.isCustom {
            imapHost = pr.imapHost; imapPort = String(pr.imapPort); imapSecurity = pr.imapSecurity
            smtpHost = pr.smtpHost; smtpPort = String(pr.smtpPort); smtpSecurity = pr.smtpSecurity
            showAdvanced = false
        } else {
            showAdvanced = true
        }
    }

    private var canConnect: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
        !imapHost.trimmingCharacters(in: .whitespaces).isEmpty &&
        !smtpHost.trimmingCharacters(in: .whitespaces).isEmpty &&
        !imapPassword.isEmpty
    }

    var body: some View {
        ZStack(alignment: .top) {
            OverlayBackdrop { if !connecting { model.manualSetupOpen = false } }
            sheet.padding(.top, 56)
        }
        .onAppear { applyProvider(model.setupProvider ?? .custom) }
    }

    private var providerPicker: some View {
        let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: cols, spacing: 8) {
            ForEach(MailProvider.all) { pr in
                let active = provider.id == pr.id
                Button { applyProvider(pr) } label: {
                    HStack(spacing: 8) {
                        Text(pr.initial)
                            .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Color(hex: pr.colorHex))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        Text(pr.name).font(.system(size: 12.5, weight: .medium)).foregroundStyle(p.fg1).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 7)
                    .frame(maxWidth: .infinity)
                    .background(active ? p.brandBlue100 : p.bg2)
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(active ? p.brandBlue : p.border, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var sheet: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Icon(name: "settings", size: 16).foregroundStyle(p.brandBlue)
                Text("Set up mail account").font(.system(size: 16, weight: .bold)).foregroundStyle(p.fg1)
                Spacer()
                Button { model.manualSetupOpen = false } label: {
                    Icon(name: "x", size: 14).foregroundStyle(p.fg3).frame(width: 30, height: 30)
                }.buttonStyle(.plain).disabled(connecting)
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
            .overlay(Rectangle().fill(p.border).frame(height: 1), alignment: .bottom)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section("Provider") {
                        providerPicker
                        if !provider.hint.isEmpty {
                            HStack(alignment: .top, spacing: 8) {
                                Icon(name: "alert", size: 12).foregroundStyle(p.brandBlue).padding(.top, 1)
                                Text(provider.hint).font(.system(size: 11.5)).foregroundStyle(p.fg2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(p.brandBlue100)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                    section("Account") {
                        field("Display name (optional)", text: $displayName, placeholder: "Jane Doe")
                        field("Email address", text: $email, placeholder: "you@\(provider.domain)")
                            .onChange(of: email) { _, v in
                                if imapUsername.isEmpty || imapUsername == lastEmail { imapUsername = v }
                                lastEmail = v
                            }
                        secureField(provider.isCustom ? "Password" : "App password", text: $imapPassword)
                    }

                    Button { withAnimation(.easeOut(duration: 0.15)) { showAdvanced.toggle() } } label: {
                        HStack(spacing: 6) {
                            Icon(name: showAdvanced ? "chevronDown" : "chevronRight", size: 11)
                            Text("Server settings").font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(p.fg2)
                    }
                    .buttonStyle(.plain)

                    if showAdvanced {
                        section("Incoming — IMAP") {
                            HStack(spacing: 10) {
                                field("Host", text: $imapHost, placeholder: "imap.example.com").frame(maxWidth: .infinity)
                                field("Port", text: $imapPort, placeholder: "993").frame(width: 80)
                            }
                            securityRow("Security", selection: $imapSecurity)
                            field("Username", text: $imapUsername, placeholder: "you@example.com")
                        }
                        section("Outgoing — SMTP") {
                            Toggle(isOn: $sameCredentials) {
                                Text("Use the same username & password as IMAP").font(.system(size: 12.5)).foregroundStyle(p.fg2)
                            }
                            .toggleStyle(.checkbox)
                            HStack(spacing: 10) {
                                field("Host", text: $smtpHost, placeholder: "smtp.example.com").frame(maxWidth: .infinity)
                                field("Port", text: $smtpPort, placeholder: "587").frame(width: 80)
                            }
                            securityRow("Security", selection: $smtpSecurity)
                            if !sameCredentials {
                                field("Username", text: $smtpUsername, placeholder: "you@example.com")
                                secureField("Password", text: $smtpPassword)
                            }
                        }
                    }
                    if let error {
                        HStack(spacing: 8) {
                            Icon(name: "alert", size: 13).foregroundStyle(p.danger)
                            Text(error).font(.system(size: 12)).foregroundStyle(p.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(p.danger100)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding(.horizontal, 18).padding(.vertical, 16)
            }

            HStack(spacing: 8) {
                Text("Your password is stored in the macOS Keychain.")
                    .font(.system(size: 11.5)).foregroundStyle(p.fg3)
                Spacer()
                Button { model.manualSetupOpen = false } label: {
                    Text("Cancel").font(.system(size: 13, weight: .semibold)).foregroundStyle(p.fg2)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(p.border, lineWidth: 1))
                }.buttonStyle(.plain).disabled(connecting)
                Button(action: connect) {
                    HStack(spacing: 6) {
                        if connecting { ProgressView().controlSize(.small) }
                        Text(connecting ? "Connecting…" : "Connect").font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(canConnect && !connecting ? p.brandBlue : p.bg4)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }.buttonStyle(.plain).disabled(!canConnect || connecting)
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
            .background(p.bg2)
            .overlay(Rectangle().fill(p.border).frame(height: 1), alignment: .top)
        }
        .frame(width: 520)
        .frame(maxHeight: 640)
        .background(p.bg1)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 48, y: 24)
    }

    // MARK: Builders

    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(.system(size: 10.5, weight: .bold)).tracking(0.6).foregroundStyle(p.fg3)
            content()
        }
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(p.fg3)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain).font(.system(size: 13.5)).foregroundStyle(p.fg1)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(p.bg2)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(p.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .autocorrectionDisabled()
        }
    }

    private func secureField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(p.fg3)
            SecureField("••••••••", text: text)
                .textFieldStyle(.plain).font(.system(size: 13.5)).foregroundStyle(p.fg1)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(p.bg2)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(p.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func securityRow(_ label: String, selection: Binding<ConnectionSecurity>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(p.fg3)
            Picker("", selection: selection) {
                ForEach(ConnectionSecurity.allCases) { s in Text(s.label).tag(s) }
            }
            .labelsHidden().pickerStyle(.segmented)
        }
    }

    // MARK: Connect

    private func connect() {
        let id = "real-\(UUID().uuidString)"
        let user = imapUsername.trimmingCharacters(in: .whitespaces).isEmpty ? email : imapUsername
        let cfg = MailAccountConfig(
            id: id,
            displayName: displayName.trimmingCharacters(in: .whitespaces),
            email: email.trimmingCharacters(in: .whitespaces),
            imapHost: imapHost.trimmingCharacters(in: .whitespaces),
            imapPort: Int(imapPort) ?? 993,
            imapSecurity: imapSecurity,
            imapUsername: user,
            smtpHost: smtpHost.trimmingCharacters(in: .whitespaces),
            smtpPort: Int(smtpPort) ?? 587,
            smtpSecurity: smtpSecurity,
            smtpUsername: sameCredentials ? user : (smtpUsername.isEmpty ? email : smtpUsername)
        )
        let imapPw = imapPassword
        let smtpPw = sameCredentials ? imapPassword : smtpPassword
        connecting = true
        error = nil
        Task {
            do {
                let imap = IMAPService(config: cfg, password: imapPw)
                try await imap.connectAndLogin()
                _ = try await imap.select("INBOX")
                await imap.disconnect()
                await MainActor.run {
                    connecting = false
                    model.addRealAccount(config: cfg, imapPassword: imapPw, smtpPassword: smtpPw)
                }
            } catch {
                await MainActor.run {
                    connecting = false
                    self.error = error.localizedDescription
                }
            }
        }
    }
}

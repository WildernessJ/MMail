import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p

    private func connect() {
        model.persistOnboarded()
        withAnimation(.easeOut(duration: 0.25)) { model.onboarding = false }
    }

    var body: some View {
        ZStack {
            p.bg1.ignoresSafeArea()
            VStack(spacing: 0) {
                logoMark
                    .padding(.bottom, 24)

                Text("The mail client that gets out of your way.")
                    .font(.system(size: 32, weight: .heavy))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(p.fg1)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 12)

                Text("MMail is built for people who'd rather use their keyboard. Connect an account to get started — or skip and explore a demo inbox.")
                    .font(.system(size: 15))
                    .foregroundStyle(p.fg2)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 28)

                VStack(spacing: 8) {
                    providerButton(icon: "mail", title: "Continue with Google")
                    providerButton(icon: "mail", title: "Continue with iCloud")
                    providerButton(icon: "settings", title: "Set up IMAP manually") {
                        model.manualSetupOpen = true
                    }
                }
                .padding(.bottom, 4)

                Button(action: connect) {
                    Text("Skip and explore a demo inbox →")
                        .font(.system(size: 14))
                        .foregroundStyle(p.fg3)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)

                HStack(spacing: 2) {
                    Text("Tip: press").font(.system(size: 12)).foregroundStyle(p.fg3)
                    Kbd("?")
                    Text("anytime to see every shortcut.").font(.system(size: 12)).foregroundStyle(p.fg3)
                }
                .padding(.top, 16)
            }
            .frame(width: 460)
            .padding(40)
        }
    }

    private var logoMark: some View {
        ZStack(alignment: .topTrailing) {
            Text("M")
                .font(.system(size: 26, weight: .heavy, design: .default))
                .italic()
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(
                    LinearGradient(colors: [p.brandBlue, p.brandBlue700],
                                   startPoint: .top, endPoint: .bottom)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: p.brandBlue.opacity(0.32), radius: 12, y: 8)
            Circle()
                .fill(p.magenta)
                .frame(width: 14, height: 14)
                .shadow(color: p.magenta.opacity(0.5), radius: 6, y: 4)
                .offset(x: 4, y: -4)
        }
    }

    private func providerButton(icon: String, title: String, action: (() -> Void)? = nil) -> some View {
        Button(action: { (action ?? connect)() }) {
            HStack(spacing: 12) {
                Icon(name: icon, size: 18).foregroundStyle(p.fg1)
                Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(p.fg1)
                Spacer()
                Icon(name: "arrowRight", size: 16).foregroundStyle(p.fg3)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(p.bg1)
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(p.borderStrong, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(HoverBorderButtonStyle())
    }
}

// Provider button hover: border turns blue, bg tints.
struct HoverBorderButtonStyle: ButtonStyle {
    @Environment(\.palette) private var p
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(hovered ? p.bg2 : Color.clear)
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(hovered ? p.brandBlue : Color.clear, lineWidth: 1))
            .onHover { hovered = $0 }
    }
}

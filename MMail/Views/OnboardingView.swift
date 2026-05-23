import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p

    private func openSetup() { model.manualSetupOpen = true }

    var body: some View {
        ZStack {
            p.bg1.ignoresSafeArea()
            SynthwaveBackground().ignoresSafeArea()
            VStack(spacing: 0) {
                logoMark
                    .padding(.bottom, 24)

                Text("The mail client that gets out of your way.")
                    .font(.system(size: 32, weight: .heavy))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(p.fg1)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 12)

                Text("MMail is built for people who'd rather use their keyboard. Connect an account to get started.")
                    .font(.system(size: 15))
                    .foregroundStyle(p.fg2)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 28)

                VStack(spacing: 8) {
                    providerButton(icon: "mail", title: "Continue with Google", action: openSetup)
                    providerButton(icon: "mail", title: "Continue with iCloud", action: openSetup)
                    providerButton(icon: "settings", title: "Set up IMAP manually", action: openSetup)
                }
                .padding(.bottom, 8)

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

    private func providerButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
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
        .focusable(false)
        .focusEffectDisabled()
    }
}

// Subtle animated synthwave backdrop: drifting blue/pink neon glows over a
// faint scrolling perspective grid. Decorative only.
struct SynthwaveBackground: View {
    @Environment(\.palette) private var p

    private let blue = (r: 45.0, g: 61.0, b: 236.0)    // #2D3DEC
    private let pink = (r: 233.0, g: 30.0, b: 120.0)   // #E91E78

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let w = size.width, h = size.height
                let strong = p.isDark ? 1.4 : 1.0

                // Drifting corner glows.
                glow(ctx, center: CGPoint(x: 0.18 * w + sin(t * 0.25) * 0.05 * w,
                                          y: 0.14 * h + cos(t * 0.20) * 0.05 * h),
                     color: color(blue), radius: w * 0.55, intensity: 0.20 * strong)
                glow(ctx, center: CGPoint(x: 0.84 * w + sin(t * 0.22 + 2) * 0.05 * w,
                                          y: 0.18 * h + cos(t * 0.27 + 1) * 0.04 * h),
                     color: color(pink), radius: w * 0.5, intensity: 0.20 * strong)

                // Horizon "sun" glow + grid.
                let horizon = h * 0.52
                let pulse = 0.14 + 0.03 * sin(t * 0.8)
                glow(ctx, center: CGPoint(x: w * 0.5, y: horizon),
                     color: color(pink), radius: w * 0.32, intensity: pulse * strong)

                drawGrid(ctx, size: size, horizon: horizon, time: t, strong: strong)
            }
        }
        .blur(radius: 0.5)
        .allowsHitTesting(false)
    }

    private func color(_ c: (r: Double, g: Double, b: Double)) -> Color {
        Color(.sRGB, red: c.r / 255, green: c.g / 255, blue: c.b / 255, opacity: 1)
    }
    private func lerp(_ f: Double) -> Color {
        Color(.sRGB,
              red: (blue.r + (pink.r - blue.r) * f) / 255,
              green: (blue.g + (pink.g - blue.g) * f) / 255,
              blue: (blue.b + (pink.b - blue.b) * f) / 255,
              opacity: 1)
    }

    private func glow(_ ctx: GraphicsContext, center: CGPoint, color: Color, radius: CGFloat, intensity: Double) {
        let grad = Gradient(colors: [color.opacity(intensity), color.opacity(0)])
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        ctx.fill(Path(ellipseIn: rect),
                 with: .radialGradient(grad, center: center, startRadius: 0, endRadius: radius))
    }

    private func drawGrid(_ ctx: GraphicsContext, size: CGSize, horizon: CGFloat, time: Double, strong: Double) {
        let w = size.width, h = size.height
        let vanish = CGPoint(x: w * 0.5, y: horizon)
        let phase = (time * 0.18).truncatingRemainder(dividingBy: 1.0)

        // Receding horizontal lines (scroll toward the viewer).
        var i = 0
        while i < 80 {
            let depth = Double(i) + phase
            let y = horizon + CGFloat(depth * depth) * (h * 0.0065)
            if y > h { break }
            let frac = Double((y - horizon) / max(1, h - horizon))
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: w, y: y))
            ctx.stroke(path, with: .color(lerp(frac).opacity((0.02 + 0.12 * frac) * strong)), lineWidth: 1)
            i += 1
        }

        // Vertical lines fanning out from the vanishing point.
        let cols = 16
        for c in -cols...cols {
            let bottomX = w * 0.5 + CGFloat(c) * (w / CGFloat(cols)) * 1.5
            var path = Path()
            path.move(to: vanish)
            path.addLine(to: CGPoint(x: bottomX, y: h))
            ctx.stroke(path, with: .color(lerp(0.6).opacity(0.06 * strong)), lineWidth: 1)
        }
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

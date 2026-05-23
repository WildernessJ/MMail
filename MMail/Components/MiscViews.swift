import SwiftUI

struct ToastView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p
    let toast: ToastModel

    var body: some View {
        HStack(spacing: 10) {
            Icon(name: "check", size: 14)
            Text(toast.message).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
            if let label = toast.actionLabel {
                Button(label) {
                    toast.action?()
                    model.toast = nil
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .opacity(0.85)
            }
        }
        .foregroundStyle(p.bg1)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(p.fg1)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
    }
}

struct FocusCounterView: View {
    @Environment(\.palette) private var p
    let pos: Int
    let total: Int

    var body: some View {
        if total > 0 {
            HStack(spacing: 10) {
                Text("\(pos)/\(total)")
                    .font(.system(size: 11, weight: .bold)).monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(p.brandBlue)
                    .clipShape(Capsule())
                Text("in this view").font(.system(size: 11)).foregroundStyle(p.fg3)
            }
            .padding(.leading, 4).padding(.trailing, 12).padding(.vertical, 4)
            .background(p.bg1)
            .overlay(Capsule().stroke(p.border, lineWidth: 1))
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
            .opacity(0.92)
        }
    }
}

// Dimmed backdrop used by overlays (palette, help, settings, add-account).
struct OverlayBackdrop: View {
    @Environment(\.palette) private var p
    let onTap: () -> Void
    var body: some View {
        Rectangle()
            .fill(p.isDark ? Color.black.opacity(0.55) : Color(hex: "0E0F1A").opacity(0.32))
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
    }
}

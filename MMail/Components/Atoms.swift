import SwiftUI

// MARK: - Icon (design icon name -> SF Symbol)

enum Icons {
    static let map: [String: String] = [
        "inbox": "tray",
        "star": "star",
        "star.fill": "star.fill",
        "clock": "clock",
        "check": "checkmark",
        "send": "paperplane",
        "file": "doc",
        "ban": "nosign",
        "trash": "trash",
        "reply": "arrowshape.turn.up.left",
        "replyAll": "arrowshape.turn.up.left.2",
        "forward": "arrowshape.turn.up.right",
        "archive": "archivebox",
        "pencil": "pencil",
        "search": "magnifyingglass",
        "settings": "gearshape",
        "sidebar": "sidebar.left",
        "panel": "sidebar.right",
        "command": "command",
        "attach": "paperclip",
        "x": "xmark",
        "chevronRight": "chevron.right",
        "chevronLeft": "chevron.left",
        "chevronDown": "chevron.down",
        "arrowRight": "arrow.right",
        "alert": "exclamationmark.circle",
        "user": "person",
        "refresh": "arrow.clockwise",
        "draft": "doc.text",
        "spam": "exclamationmark.triangle",
        "done": "checkmark.circle",
        "zap": "bolt.fill",
        "bell": "bell",
        "tag": "tag",
        "mail": "envelope",
        "home": "house",
        "sparkles": "sparkles",
        "sun": "sun.max",
        "plus": "plus",
        "more": "ellipsis",
        "copy": "doc.on.doc",
        "sliders": "slider.horizontal.3",
        "crown": "crown.fill",
        "outbox": "tray.and.arrow.up",
        "photo": "photo",
        "shield": "lock.shield"
    ]
}

struct Icon: View {
    let name: String
    var size: CGFloat = 16
    var weight: Font.Weight = .regular

    var body: some View {
        Image(systemName: Icons.map[name] ?? "questionmark")
            .font(.system(size: size, weight: weight))
    }
}

// MARK: - Avatar

struct Avatar: View {
    let sender: Sender?
    var size: CGFloat = 36

    var body: some View {
        let isBot = sender?.org == .bot
        Group {
            if let s = sender {
                Text(isBot ? String(s.name.prefix(1)) : s.initials)
                    .font(.system(size: max(10, size * 0.35), weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(s.color)
                    .clipShape(RoundedRectangle(cornerRadius: isBot ? 7 : size / 2, style: .continuous))
            } else {
                Text("?")
                    .font(.system(size: max(10, size * 0.35), weight: .semibold))
                    .foregroundStyle(Color.gray)
                    .frame(width: size, height: size)
                    .background(Color.gray.opacity(0.2))
                    .clipShape(Circle())
            }
        }
        .textCase(.uppercase)
    }
}

// A gradient or solid tile with text (for accounts).
struct GradientTile: View {
    var colors: [Color]
    var text: String
    var size: CGFloat = 38
    var cornerRadius: CGFloat = 11
    var fontSize: CGFloat = 14

    var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: colors.isEmpty ? [.blue] : colors,
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Kbd

struct Kbd: View {
    let text: String
    var onAccent: Bool = false
    init(_ text: String, onAccent: Bool = false) { self.text = text; self.onAccent = onAccent }

    var body: some View {
        KbdInner(text: text, onAccent: onAccent)
    }
}

private struct KbdInner: View {
    @Environment(\.palette) private var p
    let text: String
    let onAccent: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(onAccent ? Color.white : p.fg2)
            .frame(minWidth: 18, minHeight: 18)
            .padding(.horizontal, 5)
            .background(onAccent ? Color.white.opacity(0.18) : p.bg3)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(onAccent ? Color.clear : p.border, lineWidth: 1)
            )
    }
}

// MARK: - Pill (label badge)

struct Pill: View {
    @Environment(\.palette) private var p
    let label: String
    var kind: String = ""
    var colorHex: String? = nil

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(fg)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(bg)
            .clipShape(Capsule())
    }

    private var bg: Color {
        if let hex = colorHex { return Color(hex: hex).opacity(0.16) }
        switch kind {
        case "team": return p.success100
        case "design": return p.magenta100
        case "eng": return p.brandBlue100
        case "recruit": return p.warning100
        case "receipt": return p.bg3
        default: return p.bg3
        }
    }
    private var fg: Color {
        if let hex = colorHex { return Color(hex: hex) }
        switch kind {
        case "team": return p.success
        case "design": return p.magenta600
        case "eng": return p.brandBlue
        case "recruit": return p.warning
        case "receipt": return p.fg3
        default: return p.fg2
        }
    }
}

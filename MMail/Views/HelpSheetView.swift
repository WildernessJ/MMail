import SwiftUI

struct HelpSheetView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p

    struct Shortcut: Identifiable { let id = UUID(); let label: String; let keys: [String] }
    struct Section: Identifiable { let id = UUID(); let title: String; let items: [Shortcut] }

    private let sections: [Section] = [
        Section(title: "Navigation", items: [
            Shortcut(label: "Next message", keys: ["J"]),
            Shortcut(label: "Previous message", keys: ["K"]),
            Shortcut(label: "Open / focus reader", keys: ["↵"]),
            Shortcut(label: "Back to list", keys: ["esc"]),
            Shortcut(label: "Go to inbox", keys: ["G", "I"]),
            Shortcut(label: "Go to snoozed", keys: ["G", "Z"]),
            Shortcut(label: "Go to done", keys: ["G", "E"]),
            Shortcut(label: "Go to sent", keys: ["G", "T"])
        ]),
        Section(title: "Triage", items: [
            Shortcut(label: "Mark as done", keys: ["H"]),
            Shortcut(label: "Archive", keys: ["E"]),
            Shortcut(label: "Delete", keys: ["#"]),
            Shortcut(label: "Mark unread", keys: ["U"]),
            Shortcut(label: "Star", keys: ["S"]),
            Shortcut(label: "Snooze", keys: ["Z"])
        ]),
        Section(title: "Composition", items: [
            Shortcut(label: "Compose new", keys: ["C"]),
            Shortcut(label: "Reply", keys: ["R"]),
            Shortcut(label: "Reply all", keys: ["⇧", "R"]),
            Shortcut(label: "Forward", keys: ["F"]),
            Shortcut(label: "Send", keys: ["⌘", "↵"]),
            Shortcut(label: "Discard draft", keys: ["⌘", "⌫"])
        ]),
        Section(title: "App", items: [
            Shortcut(label: "Command palette", keys: ["⌘", "K"]),
            Shortcut(label: "Search", keys: ["/"]),
            Shortcut(label: "Shortcut help", keys: ["?"]),
            Shortcut(label: "Toggle sidebar", keys: ["⌘", "⇧", "S"]),
            Shortcut(label: "Toggle reading pane", keys: ["⌘", "⇧", "R"]),
            Shortcut(label: "Toggle dark mode", keys: ["⌘", "⇧", "D"]),
            Shortcut(label: "All inboxes (unified)", keys: ["⌘", "0"]),
            Shortcut(label: "Switch to account 1 / 2 / 3", keys: ["⌘", "1…3"])
        ])
    ]

    private let columns = [GridItem(.flexible(), spacing: 28), GridItem(.flexible(), spacing: 28)]

    var body: some View {
        ZStack(alignment: .top) {
            OverlayBackdrop { model.help = false }
            sheet.padding(.top, 88)
        }
    }

    private var sheet: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Keyboard shortcuts").font(.system(size: 18, weight: .bold)).foregroundStyle(p.fg1)
                    Text("Everything in MMail is one or two keys away.").font(.system(size: 12.5)).foregroundStyle(p.fg3)
                }
                Spacer()
                Button { model.help = false } label: { Icon(name: "x", size: 16).foregroundStyle(p.fg2) }.buttonStyle(.plain)
            }
            .padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 16)
            .overlay(Rectangle().fill(p.border).frame(height: 1), alignment: .bottom)

            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 28) {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(section.title.uppercased())
                                .font(.system(size: 10.5, weight: .bold)).tracking(0.6)
                                .foregroundStyle(p.fg4).padding(.bottom, 10)
                            ForEach(Array(section.items.enumerated()), id: \.element.id) { idx, it in
                                HStack {
                                    Text(it.label).font(.system(size: 13)).foregroundStyle(p.fg2)
                                    Spacer()
                                    HStack(spacing: 4) { ForEach(it.keys, id: \.self) { Kbd($0) } }
                                }
                                .padding(.vertical, 7)
                                if idx < section.items.count - 1 {
                                    Rectangle().fill(p.border).frame(height: 1)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 28).padding(.vertical, 24)
            }

            HStack(spacing: 8) {
                Icon(name: "zap", size: 14).foregroundStyle(p.fg3)
                Text("Press").font(.system(size: 12)).foregroundStyle(p.fg3)
                Kbd("?")
                Text("from anywhere to bring this back.").font(.system(size: 12)).foregroundStyle(p.fg3)
                Spacer()
                Text("Press").font(.system(size: 12)).foregroundStyle(p.fg3)
                Kbd("esc")
                Text("to close.").font(.system(size: 12)).foregroundStyle(p.fg3)
            }
            .padding(.horizontal, 28).padding(.vertical, 14)
            .overlay(Rectangle().fill(p.border).frame(height: 1), alignment: .top)
        }
        .frame(width: 720)
        .frame(maxHeight: 620)
        .background(p.bg1)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(p.borderStrong, lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 48, y: 24)
    }
}

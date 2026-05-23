import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p
    @State private var vimNav = true
    @State private var sendOnCmdReturn = true
    @State private var confirmDiscard = false

    var body: some View {
        ZStack(alignment: .top) {
            OverlayBackdrop { model.settings = false }
            sheet.padding(.top, 88)
        }
    }

    private var sheet: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Icon(name: "settings", size: 20).foregroundStyle(p.fg1)
                Text("Settings").font(.system(size: 18, weight: .bold)).foregroundStyle(p.fg1)
                Spacer()
                Button { model.settings = false } label: { Icon(name: "x", size: 16).foregroundStyle(p.fg2) }.buttonStyle(.plain)
            }
            .padding(.horizontal, 28).padding(.vertical, 20)
            .overlay(Rectangle().fill(p.border).frame(height: 1), alignment: .bottom)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("Appearance") {
                        toggleRow("Dark mode", "Use a dark interface, day or night.",
                                  on: Binding(get: { model.dark }, set: { model.setDark($0) }))
                        toggleRow("Show sidebar", "Folders and labels rail on the left.",
                                  on: Binding(get: { model.sidebarVisible }, set: { model.setSidebar($0) }))
                        toggleRow("Reading pane", "Read messages alongside the list (off goes full-width).",
                                  on: Binding(get: { model.readingPane }, set: { model.setReadingPane($0) }), last: true)
                    }
                    section("Account") {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("you@cobalt.studio").font(.system(size: 13.5, weight: .medium)).foregroundStyle(p.fg1)
                                Text("IMAP · synced 2 minutes ago").font(.system(size: 12)).foregroundStyle(p.fg3)
                            }
                            Spacer()
                            Button {} label: {
                                HStack(spacing: 6) { Icon(name: "refresh", size: 14); Text("Resync").font(.system(size: 12.5, weight: .medium)) }
                                    .foregroundStyle(p.fg2).padding(.horizontal, 10).frame(height: 30)
                                    .clipShape(RoundedRectangle(cornerRadius: 7))
                            }.buttonStyle(.plain)
                        }.padding(.vertical, 12)
                        Rectangle().fill(p.border).frame(height: 1)
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Signature").font(.system(size: 13.5, weight: .medium)).foregroundStyle(p.fg1)
                                Text("Appended to every reply.").font(.system(size: 12)).foregroundStyle(p.fg3)
                            }
                            Spacer()
                            Text("Sent from MMail").font(.system(size: 12)).foregroundStyle(p.fg3)
                        }.padding(.vertical, 12)
                    }
                    section("Keyboard") {
                        toggleRow("Vim-style navigation", "J / K to move through messages, G prefix for go-to.", on: $vimNav)
                        toggleRow("Send on ⌘↵", "Press Cmd-Enter from any compose field to send.", on: $sendOnCmdReturn)
                        toggleRow("Confirm before discarding", "Ask before throwing away a draft.", on: $confirmDiscard, last: true)
                    }
                }
                .padding(.horizontal, 28).padding(.vertical, 24)
            }
        }
        .frame(width: 720)
        .frame(maxHeight: 620)
        .background(p.bg1)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(p.borderStrong, lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 48, y: 24)
    }

    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 13, weight: .bold)).foregroundStyle(p.fg1).padding(.bottom, 12)
            content()
        }
    }

    private func toggleRow(_ label: String, _ desc: String, on: Binding<Bool>, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.system(size: 13.5, weight: .medium)).foregroundStyle(p.fg1)
                    Text(desc).font(.system(size: 12)).foregroundStyle(p.fg3)
                }
                Spacer()
                MMToggle(on: on)
            }
            .padding(.vertical, 12)
            if !last { Rectangle().fill(p.border).frame(height: 1) }
        }
    }
}

struct MMToggle: View {
    @Environment(\.palette) private var p
    @Binding var on: Bool
    var body: some View {
        Button { on.toggle() } label: {
            ZStack(alignment: on ? .trailing : .leading) {
                Capsule().fill(on ? p.success : p.bg4).frame(width: 36, height: 20)
                Circle().fill(.white).frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                    .padding(2)
            }
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: on)
    }
}

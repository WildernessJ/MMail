import SwiftUI
import AppKit

struct CommandPaletteView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p
    @State private var query = ""
    @State private var activeIndex = 0
    @State private var monitor: Any?
    @FocusState private var focused: Bool

    private var commands: [Command] { model.buildCommands() }

    private var matches: [Command] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return commands }
        return commands
            .compactMap { c -> (Command, Int)? in
                let hay = "\(c.label) \(c.hint ?? "") \(c.group)".lowercased()
                guard let r = hay.range(of: q) else { return nil }
                return (c, hay.distance(from: hay.startIndex, to: r.lowerBound))
            }
            .sorted { $0.1 < $1.1 }
            .map { $0.0 }
    }

    private var groupedMatches: [(String, [(Int, Command)])] {
        var order: [String] = []
        var map: [String: [(Int, Command)]] = [:]
        for (i, c) in matches.enumerated() {
            if map[c.group] == nil { order.append(c.group) }
            map[c.group, default: []].append((i, c))
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    private func run(_ c: Command) {
        c.run()
        model.palette = false
    }

    var body: some View {
        ZStack(alignment: .top) {
            OverlayBackdrop { model.palette = false }
            palette
                .padding(.top, 88)
        }
        .onAppear { focused = true; installMonitor() }
        .onDisappear { removeMonitor() }
        .onChange(of: query) { _, _ in activeIndex = 0 }
    }

    private var palette: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Icon(name: "search", size: 16).foregroundStyle(p.fg3)
                TextField("Type a command, search anything…", text: $query)
                    .textFieldStyle(.plain).font(.system(size: 16)).foregroundStyle(p.fg1)
                    .focused($focused)
                Kbd("esc")
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
            .overlay(Rectangle().fill(p.border).frame(height: 1), alignment: .bottom)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if matches.isEmpty {
                            Text("No commands match \"\(query)\".")
                                .font(.system(size: 13)).foregroundStyle(p.fg3)
                                .padding(.horizontal, 18).padding(.vertical, 24)
                        } else {
                            ForEach(groupedMatches, id: \.0) { group, items in
                                Text(group.uppercased())
                                    .font(.system(size: 10.5, weight: .bold)).tracking(0.6)
                                    .foregroundStyle(p.fg4)
                                    .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 4)
                                ForEach(items, id: \.1.id) { idx, c in
                                    paletteItem(c, index: idx)
                                        .id(idx)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                .frame(maxHeight: 360)
                .onChange(of: activeIndex) { _, i in
                    withAnimation(.linear(duration: 0.08)) { proxy.scrollTo(i, anchor: .center) }
                }
            }

            HStack(spacing: 14) {
                HStack(spacing: 6) { Kbd("↑"); Kbd("↓"); Text("to navigate").font(.system(size: 11.5)).foregroundStyle(p.fg3) }
                HStack(spacing: 6) { Kbd("↵"); Text("to select").font(.system(size: 11.5)).foregroundStyle(p.fg3) }
                Spacer()
                HStack(spacing: 6) { Kbd("esc"); Text("to close").font(.system(size: 11.5)).foregroundStyle(p.fg3) }
            }
            .padding(.horizontal, 18).padding(.vertical, 10)
            .background(p.bg2)
            .overlay(Rectangle().fill(p.border).frame(height: 1), alignment: .top)
        }
        .frame(width: 560)
        .background(p.bg1)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(p.borderStrong, lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 48, y: 24)
    }

    private func paletteItem(_ c: Command, index: Int) -> some View {
        let active = index == activeIndex
        return HStack(spacing: 12) {
            Icon(name: c.icon, size: 16).foregroundStyle(active ? p.brandBlue : p.fg3).frame(width: 16)
            Text(c.label).font(.system(size: 13.5)).foregroundStyle(p.fg1)
            Spacer()
            if let hint = c.hint { Text(hint).font(.system(size: 11.5)).foregroundStyle(p.fg3) }
            if let s = c.shortcut { Text(s).font(.system(size: 11, design: .monospaced)).foregroundStyle(p.fg3) }
        }
        .padding(.horizontal, 18).padding(.vertical, 9)
        .background(active ? (p.isDark ? p.bg3 : p.brandBlue100) : Color.clear)
        .contentShape(Rectangle())
        .onHover { if $0 { activeIndex = index } }
        .onTapGesture { run(c) }
    }

    // Local key monitor: arrows + enter (typing still flows to the field).
    private func installMonitor() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 125: // down
                activeIndex = min(matches.count - 1, activeIndex + 1); return nil
            case 126: // up
                activeIndex = max(0, activeIndex - 1); return nil
            case 36, 76: // return / keypad enter
                if matches.indices.contains(activeIndex) { run(matches[activeIndex]) }
                return nil
            default:
                return event
            }
        }
    }
    private func removeMonitor() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}

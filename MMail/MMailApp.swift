import SwiftUI

@main
struct MMailApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 920, minHeight: 600)
                .preferredColorScheme(model.dark ? .dark : .light)
                .environment(\.palette, model.dark ? .dark : .light)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1340, height: 860)
        .commands {
            CommandGroup(replacing: .help) {
                Button("MMail Keyboard Shortcuts") { model.help = true }
                    .keyboardShortcut("?", modifiers: [])
            }

            // Read-only discovery + click layer over buildCommands(), projected by the pure
            // MenuModel. Each item shows its shortcut as TEXT only — NO `.keyboardShortcut`
            // is attached to any Message/Go/View item, so the menu never competes with
            // handleKeyDown. (The lone accelerator the feature adds is Settings ⌘, below.)
            CommandMenu("Message") {
                menuRows(menuModel.message)
            }
            CommandMenu("Go") {
                menuRows(menuModel.go)
            }
            // View-insertion items land in the SYSTEM View menu (`.sidebar` placement keeps
            // exactly one View menu — no duplicate top-level "View").
            CommandGroup(after: .sidebar) {
                ForEach(menuModel.viewInsertion, id: \.commandId) { item in
                    Button(titleWithHint(item)) { model.run(item.commandId) }
                }
                Menu("Account Rail Size") {
                    Picker("Account Rail Size", selection: Binding(get: { model.railSize }, set: { model.setRailSize($0) })) {
                        Text("Small").tag(RailSize.small)
                        Text("Medium").tag(RailSize.medium)
                        Text("Large").tag(RailSize.large)
                    }
                    .pickerStyle(.inline)
                }
                Toggle("Show Folder Labels", isOn: Binding(get: { model.sidebarLabelsVisible }, set: { model.setSidebarLabels($0) }))
            }

            // The ONLY accelerator this feature adds: Settings ⌘, in the application menu.
            // The Settings command has no existing handleKeyDown binding, so this introduces
            // no double-fire risk. (Live-verified in /verify; spec allows a handleKeyDown
            // fallback if `.appSettings` fails to bind on the target OS — that is T007, NOT
            // applied here.)
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { model.settings = true }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }

    /// The current menu projection. Re-derived from `buildCommands()` so the menu and the
    /// command palette stay one source of truth, and so SwiftUI re-evaluates it when
    /// `@Published accounts` (etc.) change.
    private var menuModel: MenuModel { MenuModel.build(from: model.buildCommands()) }

    /// Render a list of `MenuRow`s: items as text-hint buttons, dividers as `Divider()`.
    @ViewBuilder
    private func menuRows(_ rows: [MenuRow]) -> some View {
        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
            switch row {
            case .divider:
                Divider()
            case let .item(item):
                Button(titleWithHint(item)) { model.run(item.commandId) }
            }
        }
    }

    /// Compose an item's visible title with its shortcut hint as trailing TEXT
    /// (e.g. `"Archive    E"`). Commands with no shortcut show just the label.
    private func titleWithHint(_ item: MenuItem) -> String {
        guard let hint = item.hint, !hint.isEmpty else { return item.label }
        return "\(item.label)    \(hint)"
    }
}

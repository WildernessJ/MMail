import Foundation

/// A single menu item projected from a `Command`. SwiftUI-free so it can be unit-tested
/// without instantiating any view. `hint` carries the command's shortcut as display TEXT
/// (e.g. `"E"`, `"⌘⇧D"`, `"G I"`); it is nil for commands with no shortcut.
struct MenuItem: Equatable {
    let commandId: String
    let label: String
    let hint: String?
}

/// A row in a rendered menu: either a clickable item or a visual divider between sections.
enum MenuRow: Equatable {
    case item(MenuItem)
    case divider
}

/// Pure, SwiftUI-independent projection of `AppModel.buildCommands()` into ordered menu
/// placements. This is the SINGLE place that decides which command goes where and how its
/// shortcut hint is formatted — the menu and the command palette stay one source of truth.
///
/// Routing (see specs/menu-bar.md):
/// - `Mail` group   → Message menu (first section)
/// - `Triage` group → Message menu (second section, after a divider)
/// - `Go to` group  → Go menu (first section)
/// - `Accounts`     → Go menu (second section, after a divider)
/// - `App` group    → View-insertion group, EXCLUDING `settings` (→ app menu) and `help`
///                    (→ Help menu, already registered).
///
/// Within every placement the relative order of commands as they appear in `buildCommands()`
/// is preserved — it is a faithful group projection (filter by group, keep source order),
/// it does NOT reorder.
struct MenuModel: Equatable {
    let message: [MenuRow]
    let go: [MenuRow]
    let viewInsertion: [MenuItem]

    /// Command ids routed OUT of the View-insertion group (rendered elsewhere).
    static let viewExcludedIds: Set<String> = ["settings", "help"]

    static func build(from commands: [Command]) -> MenuModel {
        // Faithful group projection: filter by group, preserve source order, never reorder.
        func rows(_ group: String) -> [MenuRow] {
            commands
                .filter { $0.group == group }
                .map { .item(MenuItem(commandId: $0.id, label: $0.label, hint: $0.shortcut)) }
        }

        // Message = Mail-group rows + divider + Triage-group rows.
        let message = rows("Mail") + [.divider] + rows("Triage")
        // Go = Go-to-group rows + divider + Accounts-group rows.
        let go = rows("Go to") + [.divider] + rows("Accounts")
        // View-insertion = App-group items EXCLUDING settings (→ app menu) and help (→ Help menu).
        let viewInsertion = commands
            .filter { $0.group == "App" && !viewExcludedIds.contains($0.id) }
            .map { MenuItem(commandId: $0.id, label: $0.label, hint: $0.shortcut) }

        return MenuModel(message: message, go: go, viewInsertion: viewInsertion)
    }
}

import Testing
import Foundation
@testable import MMail

/// Unit tests for `MenuModel.build(from:)`: the PURE, SwiftUI-free projection that owns the
/// single decision of which `buildCommands()` command goes into which menu and how its
/// shortcut hint is formatted. Everything is exercised with hand-built `[Command]` arrays
/// (NO live `AppModel` for the pure-transform cases), proving the transform is decoupled
/// from view + state. Asserted here, mirroring specs/menu-bar.md scenarios:
/// - Message menu composition + order + hint text (Mail then divider then Triage) (SC-001/004)
/// - Go menu composition with two accounts (Go to then divider then Accounts) (SC-001/004)
/// - View-insertion = App group MINUS settings + help, in source order (SC-001/004)
/// - Edge case: a `shortcut == nil` command yields `hint == nil`, no placeholder (SC-004)
/// - Order preservation: items follow input order within group, no reordering (SC-001)
/// - T004 guard: from the REAL `buildCommands()`, `palette` is last in viewInsertion and
///   neither `settings` nor `help` appears there.
/// SwiftUI rendering, ⌘,, single-View-menu, no-double-fire, and dynamic accounts are live
/// (GUI) verification, not assertable by this target (SC-002/003/005/006).
@Suite struct MenuModelTests {

    // Helper to build a Command with the common fields (hint omitted, matching call sites).
    private static func cmd(_ id: String, _ group: String, _ label: String, shortcut: String? = nil) -> Command {
        Command(id: id, group: group, label: label, icon: "x", shortcut: shortcut) { }
    }

    /// The default (no-accounts) command list mirroring `buildCommands()` source order,
    /// including the new `palette` command appended at the end of the App group.
    private static func defaultCommands() -> [Command] {
        [
            cmd("compose", "Mail", "Compose new message", shortcut: "C"),
            cmd("reply", "Mail", "Reply to current message", shortcut: "R"),
            cmd("replyAll", "Mail", "Reply all", shortcut: "A"),
            cmd("forward", "Mail", "Forward", shortcut: "F"),
            cmd("archive", "Triage", "Archive", shortcut: "E"),
            cmd("done", "Triage", "Mark as done", shortcut: "H"),
            cmd("snooze", "Triage", "Snooze", shortcut: "Z"),
            cmd("delete", "Triage", "Delete", shortcut: "#"),
            cmd("unread", "Triage", "Mark unread", shortcut: "U"),
            cmd("star", "Triage", "Star / unstar", shortcut: "S"),
            cmd("go-inbox", "Go to", "Go to Inbox", shortcut: "G I"),
            cmd("go-home", "Go to", "Go to Home", shortcut: "G H"),
            cmd("go-starred", "Go to", "Go to Starred", shortcut: "G S"),
            cmd("go-snoozed", "Go to", "Go to Snoozed", shortcut: "G Z"),
            cmd("go-done", "Go to", "Go to Done", shortcut: "G E"),
            cmd("go-sent", "Go to", "Go to Sent", shortcut: "G T"),
            cmd("go-drafts", "Go to", "Go to Drafts", shortcut: "G D"),
            cmd("search", "App", "Search mail", shortcut: "/"),
            cmd("help", "App", "Show keyboard shortcuts", shortcut: "?"),
            cmd("settings", "App", "Open settings", shortcut: "⌘,"),
            cmd("dark", "App", "Toggle dark mode", shortcut: "⌘⇧D"),
            cmd("sidebar", "App", "Toggle sidebar", shortcut: "⌘⇧S"),
            cmd("reading", "App", "Toggle reading pane", shortcut: "⌘⇧R"),
            cmd("palette", "App", "Command palette", shortcut: "⌘K"),
            cmd("acct-all", "Accounts", "All inboxes (unified)", shortcut: "⌘0"),
            cmd("acct-add", "Accounts", "Add account…", shortcut: nil),
        ]
    }

    /// Extract the ordered `MenuItem`s from a `[MenuRow]`, dropping dividers.
    private static func items(_ rows: [MenuRow]) -> [MenuItem] {
        rows.compactMap { if case let .item(i) = $0 { return i } else { return nil } }
    }

    /// Extract the (commandId, hint) of every row in order, with dividers marked.
    private static func shape(_ rows: [MenuRow]) -> [String] {
        rows.map { row in
            switch row {
            case .divider: return "—"
            case let .item(i): return i.commandId
            }
        }
    }

    // MARK: - Message menu composition + order + hint text (SC-001/004)

    @Test func messageMenuCompositionAndOrder() {
        let model = MenuModel.build(from: Self.defaultCommands())
        // Mail group, divider, Triage group — in source order.
        #expect(Self.shape(model.message) == [
            "compose", "reply", "replyAll", "forward",
            "—",
            "archive", "done", "snooze", "delete", "unread", "star",
        ])
        let items = Self.items(model.message)
        // Hint text equals each command's shortcut string verbatim.
        #expect(items.first { $0.commandId == "archive" }?.hint == "E")
        #expect(items.first { $0.commandId == "compose" }?.hint == "C")
        #expect(items.first { $0.commandId == "reply" }?.hint == "R")
        #expect(items.first { $0.commandId == "replyAll" }?.hint == "A")
        #expect(items.first { $0.commandId == "forward" }?.hint == "F")
        #expect(items.first { $0.commandId == "done" }?.hint == "H")
        #expect(items.first { $0.commandId == "snooze" }?.hint == "Z")
        #expect(items.first { $0.commandId == "delete" }?.hint == "#")
        #expect(items.first { $0.commandId == "unread" }?.hint == "U")
        #expect(items.first { $0.commandId == "star" }?.hint == "S")
        #expect(items.first { $0.commandId == "compose" }?.label == "Compose new message")
    }

    // MARK: - Go menu composition with two accounts (SC-001/004)

    @Test func goMenuCompositionWithTwoAccounts() {
        var cmds = Self.defaultCommands()
        // Insert two per-account Switch-to commands between acct-all and acct-add,
        // mirroring how buildCommands() interleaves enumerated accounts.
        guard let addIdx = cmds.firstIndex(where: { $0.id == "acct-add" }) else {
            Issue.record("acct-add missing from fixture"); return
        }
        cmds.insert(Self.cmd("acct-a", "Accounts", "Switch to A", shortcut: "⌘1"), at: addIdx)
        cmds.insert(Self.cmd("acct-b", "Accounts", "Switch to B", shortcut: "⌘2"), at: addIdx + 1)

        let model = MenuModel.build(from: cmds)
        #expect(Self.shape(model.go) == [
            "go-inbox", "go-home", "go-starred", "go-snoozed", "go-done", "go-sent", "go-drafts",
            "—",
            "acct-all", "acct-a", "acct-b", "acct-add",
        ])
        let items = Self.items(model.go)
        // Two-key chord hints keep the space verbatim ("G I", not "GI").
        #expect(items.first { $0.commandId == "go-inbox" }?.hint == "G I")
        #expect(items.first { $0.commandId == "go-home" }?.hint == "G H")
        #expect(items.first { $0.commandId == "go-starred" }?.hint == "G S")
        #expect(items.first { $0.commandId == "go-snoozed" }?.hint == "G Z")
        #expect(items.first { $0.commandId == "go-done" }?.hint == "G E")
        #expect(items.first { $0.commandId == "go-sent" }?.hint == "G T")
        #expect(items.first { $0.commandId == "go-drafts" }?.hint == "G D")
        #expect(items.first { $0.commandId == "acct-all" }?.hint == "⌘0")
        #expect(items.first { $0.commandId == "acct-a" }?.hint == "⌘1")
        #expect(items.first { $0.commandId == "acct-b" }?.hint == "⌘2")
        // Add Account… has no shortcut → nil hint (edge case, no placeholder).
        #expect(items.first { $0.commandId == "acct-add" }?.hint == nil)
    }

    // MARK: - View-insertion = App group minus settings + help, source order (SC-001/004)

    @Test func viewInsertionExcludesSettingsAndHelpInSourceOrder() {
        let model = MenuModel.build(from: Self.defaultCommands())
        #expect(model.viewInsertion.map(\.commandId) == [
            "search", "dark", "sidebar", "reading", "palette",
        ])
        #expect(!model.viewInsertion.map(\.commandId).contains("settings"))
        #expect(!model.viewInsertion.map(\.commandId).contains("help"))
        // Hints carried verbatim.
        #expect(model.viewInsertion.first { $0.commandId == "search" }?.hint == "/")
        #expect(model.viewInsertion.first { $0.commandId == "dark" }?.hint == "⌘⇧D")
        #expect(model.viewInsertion.first { $0.commandId == "sidebar" }?.hint == "⌘⇧S")
        #expect(model.viewInsertion.first { $0.commandId == "reading" }?.hint == "⌘⇧R")
        #expect(model.viewInsertion.first { $0.commandId == "palette" }?.hint == "⌘K")
    }

    // MARK: - Edge case: nil shortcut → nil hint, no placeholder (SC-004)

    @Test func nilShortcutYieldsNilHint() {
        let cmds = [Self.cmd("acct-add", "Accounts", "Add account…", shortcut: nil)]
        let model = MenuModel.build(from: cmds)
        let item = Self.items(model.go).first { $0.commandId == "acct-add" }
        #expect(item != nil)
        #expect(item?.hint == nil)
    }

    // MARK: - Order preservation within group, no reordering (SC-001)

    @Test func buildPreservesSourceOrderWithinGroup() {
        // Triage commands fed in a deliberately scrambled order; output must mirror input.
        let cmds = [
            Self.cmd("star", "Triage", "Star / unstar", shortcut: "S"),
            Self.cmd("archive", "Triage", "Archive", shortcut: "E"),
            Self.cmd("delete", "Triage", "Delete", shortcut: "#"),
        ]
        let model = MenuModel.build(from: cmds)
        #expect(Self.items(model.message).map(\.commandId) == ["star", "archive", "delete"])
    }

    // MARK: - T004 guard: REAL buildCommands() output routes palette/settings/help correctly

    @MainActor
    @Test func realBuildCommandsPlacesPaletteLastAndExcludesSettingsAndHelp() {
        let model = MenuModel.build(from: AppModel().buildCommands())
        // palette present and LAST in the View-insertion group.
        #expect(model.viewInsertion.last?.commandId == "palette")
        #expect(model.viewInsertion.contains { $0.commandId == "palette" })
        // settings + help routed elsewhere (guards against a future regroup/rename).
        #expect(!model.viewInsertion.map(\.commandId).contains("settings"))
        #expect(!model.viewInsertion.map(\.commandId).contains("help"))
    }
}

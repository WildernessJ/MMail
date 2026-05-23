import SwiftUI
import AppKit

enum InboxFilter: String, CaseIterable {
    case all, unread, people, updates
    var title: String {
        switch self {
        case .all: return "All"
        case .unread: return "Unread"
        case .people: return "People"
        case .updates: return "Updates"
        }
    }
}

struct ComposeDraft: Identifiable {
    let id = UUID()
    var to: String
    var cc: String = ""
    var bcc: String = ""
    var subject: String
    var body: String
    var titleLabel: String
    var fromId: String
}

struct ToastModel: Identifiable {
    let id = UUID()
    var message: String
    var actionLabel: String?
    var action: (() -> Void)?
}

struct ScheduledSend: Codable, Identifiable {
    var id: String
    var fromId: String
    var to: String
    var cc: String
    var bcc: String
    var subject: String
    var body: String
    var sendAt: Date
}

struct Command: Identifiable {
    let id: String
    let group: String
    let label: String
    var hint: String?
    let icon: String
    var shortcut: String?
    let run: () -> Void
}

final class AppModel: ObservableObject {
    // Persistence keys
    private let kOnboarded = "mmail.onboarded"
    private let kTodos = "mmail.todos"
    private let kJournal = "mmail.journal.today"
    private let kDark = "mmail.dark"
    private let kSidebar = "mmail.sidebar"
    private let kReadingPane = "mmail.readingPane"
    private let kJournalRecent = "mmail.journal.recent"
    private let kTemplates = "mmail.templates"
    private let kRealAccounts = "mmail.realAccounts"
    private let kVimNav = "mmail.vimNav"
    private let kConfirmDiscard = "mmail.confirmDiscard"
    private let kNotifications = "mmail.notifications"
    private var lastSeenUID: [String: UInt32] = [:]

    // Core state
    @Published var onboarding: Bool
    @Published var accounts: [Account] = []
    @Published var currentAccount: String = "all"
    @Published var folder: String = "home"
    @Published var emails: [Email] = []
    @Published var selectedId: String?
    @Published var filter: InboxFilter = .all

    // Tweaks / appearance
    @Published var dark: Bool
    @Published var sidebarVisible: Bool
    @Published var readingPane: Bool
    @Published var vimNav: Bool
    @Published var confirmDiscard: Bool
    @Published var notificationsEnabled: Bool

    // Overlays
    @Published var palette = false
    @Published var help = false
    @Published var settings = false
    @Published var compose: ComposeDraft?
    @Published var addingAccount = false
    @Published var searchActive = false
    @Published var searchQuery = ""
    @Published var searchFocusRequested = false
    @Published var toast: ToastModel?
    @Published var pendingG = false
    @Published var journalArchiveOpen = false
    @Published var manualSetupOpen = false

    // Home dashboard
    @Published var todos: [Todo]
    @Published var journal: String
    @Published var journalRecent: [JournalEntry]

    // Reply templates
    @Published var templates: [ReplyTemplate]

    // Real (IMAP/SMTP) accounts
    @Published var realConfigs: [MailAccountConfig] = []
    @Published var loadingAccounts: Set<String> = []
    @Published var accountErrors: [String: String] = [:]
    // accountId -> canonical folder id ("sent"/"drafts"/"trash"/"spam"/"archive") -> server mailbox name
    @Published var realMailboxes: [String: [String: String]] = [:]
    @Published var serverSearchResults: [Email]?
    @Published var searching = false
    @Published var scheduled: [ScheduledSend] = []
    @Published var snoozedUntil: [String: Date] = [:]   // "accountId#uid" -> wake date
    private let kScheduled = "mmail.scheduled"
    private let kSnoozed = "mmail.snoozed"
    private var pollTimer: Timer?
    private var imapSessions: [String: IMAPSession] = [:]
    private var didBootstrap = false

    private static let seedJournalRecent: [JournalEntry] = [
        JournalEntry(id: "jr-yesterday", date: "Yesterday", text: "Crit went well. Sarah's instinct on the empty state was right — copy carries it. Need to write down the lighter ring decision before I forget."),
        JournalEntry(id: "jr-mar-18", date: "Mon · Mar 18", text: "Started the week underwater but the Lumen sign-off felt great. Need to make space tomorrow for the Q3 roadmap doc Theo shared.")
    ]

    private var keyMonitor: Any?
    private var toastWorkItem: DispatchWorkItem?

    init() {
        let d = UserDefaults.standard
        onboarding = true
        dark = d.object(forKey: kDark) as? Bool ?? false
        sidebarVisible = d.object(forKey: kSidebar) as? Bool ?? true
        readingPane = d.object(forKey: kReadingPane) as? Bool ?? true
        vimNav = d.object(forKey: kVimNav) as? Bool ?? true
        confirmDiscard = d.object(forKey: kConfirmDiscard) as? Bool ?? false
        notificationsEnabled = d.object(forKey: kNotifications) as? Bool ?? true
        journal = d.string(forKey: kJournal) ?? ""
        if let data = d.data(forKey: kTodos),
           let decoded = try? JSONDecoder().decode([Todo].self, from: data) {
            todos = decoded
        } else {
            todos = SampleData.seedTodos
        }
        if let data = d.data(forKey: kJournalRecent),
           let decoded = try? JSONDecoder().decode([JournalEntry].self, from: data) {
            journalRecent = decoded
        } else {
            journalRecent = AppModel.seedJournalRecent
        }
        if let data = d.data(forKey: kTemplates),
           let decoded = try? JSONDecoder().decode([ReplyTemplate].self, from: data), !decoded.isEmpty {
            templates = decoded
        } else {
            templates = SampleData.replyTemplates
        }
        if let data = d.data(forKey: kRealAccounts),
           let decoded = try? JSONDecoder().decode([MailAccountConfig].self, from: data) {
            realConfigs = decoded
            for cfg in decoded { accounts.append(AppModel.uiAccount(for: cfg)) }
        }
        if let data = d.data(forKey: kScheduled),
           let decoded = try? JSONDecoder().decode([ScheduledSend].self, from: data) { scheduled = decoded }
        if let data = d.data(forKey: kSnoozed),
           let decoded = try? JSONDecoder().decode([String: Date].self, from: data) { snoozedUntil = decoded }
        // Welcome shows on first launch and whenever no account is connected.
        onboarding = accounts.isEmpty
    }

    // MARK: - Derived

    var accountsById: [String: Account] {
        Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
    }

    private var accountFiltered: [Email] {
        currentAccount == "all" ? emails : emails.filter { $0.account == currentAccount }
    }

    private var searchIsActive: Bool {
        searchActive && !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var visibleEmails: [Email] {
        if searchIsActive {
            if let results = serverSearchResults { return results }
            let ql = searchQuery.lowercased()
            return accountFiltered.filter { e in
                e.subject.lowercased().contains(ql) ||
                e.preview.lowercased().contains(ql) ||
                e.body.lowercased().contains(ql) ||
                (SampleData.senders[e.from]?.name.lowercased().contains(ql) ?? false)
            }
        }
        if folder == "snoozed" { return accountFiltered.filter { isSnoozed($0) } }
        return accountFiltered.filter { e in
            if isSnoozed(e) { return false }
            if folder == "starred" { return e.starred && e.folder != "trash" }
            return e.folder == folder
        }
    }

    func isSnoozed(_ e: Email) -> Bool {
        guard let uid = e.uid, let until = snoozedUntil["\(e.account)#\(uid)"] else { return false }
        return until > Date()
    }

    var filteredEmails: [Email] {
        if searchIsActive { return visibleEmails }
        if folder != "inbox" { return visibleEmails }
        switch filter {
        case .unread: return visibleEmails.filter { $0.unread }
        case .people: return visibleEmails.filter { SampleData.senders[$0.from]?.org != .bot }
        case .updates: return visibleEmails.filter { SampleData.senders[$0.from]?.org == .bot }
        case .all: return visibleEmails
        }
    }

    var selectedEmail: Email? {
        filteredEmails.first(where: { $0.id == selectedId }) ?? filteredEmails.first
    }

    var unreadCounts: [String: Int] {
        var m: [String: Int] = [:]
        for e in accountFiltered where e.unread { m[e.folder, default: 0] += 1 }
        return m
    }

    var unreadByAccount: [String: Int] {
        var m: [String: Int] = [:]
        for e in emails where e.unread && e.folder == "inbox" { m[e.account, default: 0] += 1 }
        return m
    }

    var position: Int {
        max(1, (filteredEmails.firstIndex(where: { $0.id == selectedId }) ?? 0) + 1)
    }
    var total: Int { filteredEmails.count }

    var anyOverlayOpen: Bool {
        palette || help || settings || compose != nil || addingAccount || journalArchiveOpen || manualSetupOpen
    }

    // MARK: - Persistence side-effects

    func persistOnboarded() { UserDefaults.standard.set(true, forKey: kOnboarded) }
    func persistTweaks() {
        let d = UserDefaults.standard
        d.set(dark, forKey: kDark)
        d.set(sidebarVisible, forKey: kSidebar)
        d.set(readingPane, forKey: kReadingPane)
    }
    func persistTodos() {
        if let data = try? JSONEncoder().encode(todos) {
            UserDefaults.standard.set(data, forKey: kTodos)
        }
    }
    func persistJournal() { UserDefaults.standard.set(journal, forKey: kJournal) }
    func persistJournalRecent() {
        if let data = try? JSONEncoder().encode(journalRecent) {
            UserDefaults.standard.set(data, forKey: kJournalRecent)
        }
    }
    func removeJournalEntry(_ id: String) {
        journalRecent.removeAll { $0.id == id }
        persistJournalRecent()
    }
    func persistTemplates() {
        if let data = try? JSONEncoder().encode(templates) {
            UserDefaults.standard.set(data, forKey: kTemplates)
        }
    }
    @discardableResult
    func addTemplate(name: String, body: String) -> Bool {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, !body.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        let used = Set(templates.map { $0.shortcut })
        var shortcut = ""
        for i in 1...9 where !used.contains(String(i)) { shortcut = String(i); break }
        templates.append(ReplyTemplate(id: "tpl-user-\(Int(Date().timeIntervalSince1970 * 1000))",
                                       name: n, shortcut: shortcut, body: body, custom: true))
        persistTemplates()
        return true
    }
    func removeTemplate(_ id: String) {
        templates.removeAll { $0.id == id }
        persistTemplates()
    }

    // MARK: - Selection / read

    func select(_ id: String?) {
        selectedId = id
        markSelectedReadSoon()
        loadBodyIfNeeded()
    }

    func markSelectedReadSoon() {
        guard let e = selectedEmail, e.unread else { return }
        let id = e.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, let i = self.emails.firstIndex(where: { $0.id == id }) else { return }
            self.emails[i].unread = false
        }
    }

    func navigate(_ delta: Int) {
        let fe = filteredEmails
        guard !fe.isEmpty else { return }
        let idx = fe.firstIndex(where: { $0.id == selectedId }) ?? 0
        let ni = max(0, min(fe.count - 1, idx + delta))
        select(fe[ni].id)
    }

    // MARK: - Triage

    func moveTo(_ id: String?, dest: String, verb: String) {
        guard let id, let idx = emails.firstIndex(where: { $0.id == id }) else { return }
        let original = emails[idx]
        let prevFolder = original.folder
        let fe = filteredEmails
        let curIdx = fe.firstIndex(where: { $0.id == id })
        emails[idx].folder = dest
        if let ci = curIdx {
            let next: Email? = (ci + 1 < fe.count) ? fe[ci + 1] : (ci - 1 >= 0 ? fe[ci - 1] : nil)
            selectedId = next?.id
        }
        let subjectClipped = String("\(verb) · \(original.subject)".prefix(60))
        showToast(subjectClipped, actionLabel: "Undo") { [weak self] in
            guard let self, let i = self.emails.firstIndex(where: { $0.id == id }) else { return }
            self.emails[i].folder = prevFolder
        }
    }

    func archive(_ id: String? = nil) {
        let target = id ?? selectedId
        if let target, let e = emails.first(where: { $0.id == target }), isRealAccount(e.account),
           mailboxName(e.account, "archive") != nil {
            realMove(e, to: "archive")
        }
        moveTo(target, dest: "archive", verb: "Archived")
    }
    func markDone(_ id: String? = nil) {
        let target = id ?? selectedId
        if let target, let e = emails.first(where: { $0.id == target }), isRealAccount(e.account),
           mailboxName(e.account, "archive") != nil {
            realMove(e, to: "archive")
        }
        moveTo(target, dest: "done", verb: "Marked done")
    }
    func delete(_ id: String? = nil) {
        let target = id ?? selectedId
        if let target, let e = emails.first(where: { $0.id == target }), isRealAccount(e.account) {
            if mailboxName(e.account, "trash") != nil { realMove(e, to: "trash") }
            else { applyRealFlag(e, .deleted, add: true) }
        }
        moveTo(target, dest: "trash", verb: "Deleted")
    }
    func markSpam(_ id: String? = nil) {
        let target = id ?? selectedId
        if let target, let e = emails.first(where: { $0.id == target }), isRealAccount(e.account),
           mailboxName(e.account, "spam") != nil {
            realMove(e, to: "spam")
        }
        moveTo(target, dest: "spam", verb: "Marked as spam")
    }
    func snooze(_ id: String? = nil) {
        let target = id ?? selectedId
        guard let target, let e = emails.first(where: { $0.id == target }) else { return }
        if isRealAccount(e.account), let uid = e.uid {
            // Snooze until tomorrow morning (8am).
            let cal = Calendar.current
            let wake = cal.date(byAdding: .day, value: 1, to: Date())
                .flatMap { cal.date(bySettingHour: 8, minute: 0, second: 0, of: $0) } ?? Date().addingTimeInterval(57600)
            let key = "\(e.account)#\(uid)"
            // pick next selection before it disappears from view
            let fe = filteredEmails
            let idx = fe.firstIndex { $0.id == target }
            snoozedUntil[key] = wake
            persistSnoozed()
            if let idx { selectedId = (fe[safe: idx + 1] ?? fe[safe: idx - 1])?.id }
            showToast("Snoozed until tomorrow", actionLabel: "Undo") { [weak self] in
                self?.snoozedUntil[key] = nil; self?.persistSnoozed()
            }
        } else {
            moveTo(target, dest: "snoozed", verb: "Snoozed")
        }
    }

    func markUnread(_ id: String? = nil) {
        guard let id = id ?? selectedId, let i = emails.firstIndex(where: { $0.id == id }) else { return }
        emails[i].unread = true
        applyRealFlag(emails[i], .seen, add: false)
        showToast("Marked as unread")
    }

    func toggleStar(_ id: String? = nil) {
        guard let id = id ?? selectedId, let i = emails.firstIndex(where: { $0.id == id }) else { return }
        emails[i].starred.toggle()
        applyRealFlag(emails[i], .flagged, add: emails[i].starred)
    }

    // MARK: - Compose

    func startCompose(to: String = "", subject: String = "", body: String = "",
                      titleLabel: String = "New message", fromId: String? = nil) {
        let defaultFrom = currentAccount != "all" ? currentAccount : (accounts.first?.id ?? "work")
        compose = ComposeDraft(to: to, subject: subject, body: body,
                               titleLabel: titleLabel, fromId: fromId ?? defaultFrom)
    }

    func sendDraft(_ draft: ComposeDraft) {
        let dest = draft.to.isEmpty ? "(unknown)" : draft.to
        if isRealAccount(draft.fromId) {
            guard let cfg = config(for: draft.fromId), cfg.smtpPassword != nil else { showToast("Missing SMTP password."); return }
            let recipients = AppModel.parseRecipients(draft.to) + AppModel.parseRecipients(draft.cc) + AppModel.parseRecipients(draft.bcc)
            guard !recipients.isEmpty else { showToast("Add a recipient first."); return }
            compose = nil
            showToast("Sending…")
            performSend(draft)
            return
        }
        compose = nil
        let acct = accountsById[draft.fromId]
        showToast("Sent to \(dest) from \(acct?.email ?? "you")")
    }

    // MARK: - Scheduled send

    func scheduleSend(_ draft: ComposeDraft, at date: Date, label: String) {
        compose = nil
        scheduled.append(ScheduledSend(id: UUID().uuidString, fromId: draft.fromId, to: draft.to,
                                       cc: draft.cc, bcc: draft.bcc, subject: draft.subject,
                                       body: draft.body, sendAt: date))
        persistScheduled()
        showToast("Scheduled for \(label) · \(draft.to.isEmpty ? "(unknown)" : draft.to)")
    }

    func processScheduledSends() {
        let now = Date()
        let due = scheduled.filter { $0.sendAt <= now }
        guard !due.isEmpty else { return }
        scheduled.removeAll { s in due.contains { $0.id == s.id } }
        persistScheduled()
        for s in due {
            let draft = ComposeDraft(to: s.to, cc: s.cc, bcc: s.bcc, subject: s.subject,
                                     body: s.body, titleLabel: "", fromId: s.fromId)
            performSend(draft)
        }
    }

    private func persistScheduled() {
        if let data = try? JSONEncoder().encode(scheduled) { UserDefaults.standard.set(data, forKey: kScheduled) }
    }

    /// The actual SMTP send + Sent-copy, shared by immediate and scheduled sends.
    private func performSend(_ draft: ComposeDraft) {
        guard isRealAccount(draft.fromId), let cfg = config(for: draft.fromId), let pw = cfg.smtpPassword else { return }
        let recipients = AppModel.parseRecipients(draft.to) + AppModel.parseRecipients(draft.cc) + AppModel.parseRecipients(draft.bcc)
        guard !recipients.isEmpty else { return }
        let display = accountsById[cfg.id]?.name
        let message = MIME.buildMessage(from: cfg.email, fromName: display, to: draft.to, cc: draft.cc,
                                        subject: draft.subject, body: draft.body)
        let session = session(for: cfg.id)
        Task {
            do {
                let smtp = SMTPService(config: cfg, password: pw)
                try await smtp.send(from: cfg.email, fromName: display, recipients: recipients, message: message)
                if let session, let sentBox = await self.resolveMailbox(cfg.id, kind: .sent, session: session) {
                    try? await session.append(mailbox: sentBox, rawMessage: message, seen: true, draft: false)
                    await MainActor.run { self.loadFolder(cfg.id, "sent", silent: true) }
                }
                await MainActor.run { self.showToast("Sent to \(draft.to)") }
            } catch {
                await MainActor.run { self.showToast("Send failed: \(error.localizedDescription)") }
            }
        }
    }

    private func quotedBody(_ e: Email) -> String {
        let s = e.resolvedSender
        let header = "On \(e.time), \(s.name) wrote:"
        let quoted = e.body.split(separator: "\n", omittingEmptySubsequences: false)
            .map { "> \($0)" }.joined(separator: "\n")
        return "\n\n\(header)\n\(quoted)"
    }
    func reply() {
        guard let e = selectedEmail else { return }
        let s = e.resolvedSender
        startCompose(to: s.email, subject: e.subject.hasPrefix("Re:") ? e.subject : "Re: \(e.subject)",
                     body: quotedBody(e),
                     titleLabel: "Reply · \(s.name)", fromId: e.account)
    }
    func replyAll() {
        guard let e = selectedEmail else { return }
        let s = e.resolvedSender
        let recipients = ([s.email] + (e.to ?? [])).filter { !$0.isEmpty }.joined(separator: ", ")
        startCompose(to: recipients, subject: e.subject.hasPrefix("Re:") ? e.subject : "Re: \(e.subject)",
                     body: quotedBody(e),
                     titleLabel: "Reply all · \(s.name)", fromId: e.account)
    }
    func forward() {
        guard let e = selectedEmail else { return }
        startCompose(subject: e.subject.hasPrefix("Fwd:") ? e.subject : "Fwd: \(e.subject)",
                     body: "\n\n--- Forwarded message ---\n\(e.body)",
                     titleLabel: "Forward", fromId: e.account)
    }

    // MARK: - Accounts

    func addAccount(_ acct: Account) {
        accounts.append(acct)
        currentAccount = acct.id
        addingAccount = false
        showToast("Added \(acct.email)")
    }

    // MARK: - Home: todos

    func addTodo(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        todos.insert(Todo(id: "td-\(Int(Date().timeIntervalSince1970 * 1000))", text: trimmed, done: false, source: nil), at: 0)
        persistTodos()
    }
    func toggleTodo(_ id: String) {
        guard let i = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[i].done.toggle()
        persistTodos()
    }
    func removeTodo(_ id: String) {
        todos.removeAll { $0.id == id }
        persistTodos()
    }

    // MARK: - Toast

    func showToast(_ message: String, actionLabel: String? = nil, action: (() -> Void)? = nil) {
        toast = ToastModel(message: message, actionLabel: actionLabel, action: action)
        toastWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: work)
    }

    func closeOverlays() {
        palette = false; help = false; settings = false; compose = nil; addingAccount = false
        journalArchiveOpen = false; manualSetupOpen = false
    }

    func setFolder(_ f: String) {
        folder = f
        searchActive = false
        searchQuery = ""
        serverSearchResults = nil
        searching = false
        loadForCurrentScope(f)
    }

    // MARK: - Commands (palette)

    func buildCommands() -> [Command] {
        var cmds: [Command] = [
            Command(id: "compose", group: "Mail", label: "Compose new message", icon: "pencil", shortcut: "C") { [weak self] in self?.startCompose() },
            Command(id: "reply", group: "Mail", label: "Reply to current message", icon: "reply", shortcut: "R") { [weak self] in self?.reply() },
            Command(id: "replyAll", group: "Mail", label: "Reply all", icon: "replyAll", shortcut: "A") { [weak self] in self?.replyAll() },
            Command(id: "forward", group: "Mail", label: "Forward", icon: "forward", shortcut: "F") { [weak self] in self?.forward() },
            Command(id: "archive", group: "Triage", label: "Archive", icon: "archive", shortcut: "E") { [weak self] in self?.archive() },
            Command(id: "done", group: "Triage", label: "Mark as done", icon: "check", shortcut: "H") { [weak self] in self?.markDone() },
            Command(id: "snooze", group: "Triage", label: "Snooze", icon: "clock", shortcut: "Z") { [weak self] in self?.snooze() },
            Command(id: "delete", group: "Triage", label: "Delete", icon: "trash", shortcut: "#") { [weak self] in self?.delete() },
            Command(id: "unread", group: "Triage", label: "Mark unread", icon: "mail", shortcut: "U") { [weak self] in self?.markUnread() },
            Command(id: "star", group: "Triage", label: "Star / unstar", icon: "star", shortcut: "S") { [weak self] in self?.toggleStar() },
            Command(id: "go-inbox", group: "Go to", label: "Go to Inbox", icon: "inbox", shortcut: "G I") { [weak self] in self?.setFolder("inbox") },
            Command(id: "go-home", group: "Go to", label: "Go to Home", icon: "home", shortcut: "G H") { [weak self] in self?.setFolder("home") },
            Command(id: "go-starred", group: "Go to", label: "Go to Starred", icon: "star", shortcut: "G S") { [weak self] in self?.setFolder("starred") },
            Command(id: "go-snoozed", group: "Go to", label: "Go to Snoozed", icon: "clock", shortcut: "G Z") { [weak self] in self?.setFolder("snoozed") },
            Command(id: "go-done", group: "Go to", label: "Go to Done", icon: "done", shortcut: "G E") { [weak self] in self?.setFolder("done") },
            Command(id: "go-sent", group: "Go to", label: "Go to Sent", icon: "send", shortcut: "G T") { [weak self] in self?.setFolder("sent") },
            Command(id: "go-drafts", group: "Go to", label: "Go to Drafts", icon: "draft", shortcut: "G D") { [weak self] in self?.setFolder("drafts") },
            Command(id: "search", group: "App", label: "Search mail", icon: "search", shortcut: "/") { [weak self] in self?.activateSearch() },
            Command(id: "help", group: "App", label: "Show keyboard shortcuts", icon: "command", shortcut: "?") { [weak self] in self?.help = true },
            Command(id: "settings", group: "App", label: "Open settings", icon: "settings") { [weak self] in self?.settings = true },
            Command(id: "dark", group: "App", label: "Toggle dark mode (now \(dark ? "on" : "off"))", icon: "zap", shortcut: "⌘⇧D") { [weak self] in self?.setDark(!(self?.dark ?? false)) },
            Command(id: "sidebar", group: "App", label: "Toggle sidebar (now \(sidebarVisible ? "shown" : "hidden"))", icon: "sidebar", shortcut: "⌘⇧S") { [weak self] in self?.setSidebar(!(self?.sidebarVisible ?? true)) },
            Command(id: "reading", group: "App", label: "Toggle reading pane (now \(readingPane ? "on" : "off"))", icon: "panel", shortcut: "⌘⇧R") { [weak self] in self?.setReadingPane(!(self?.readingPane ?? true)) },
            Command(id: "acct-all", group: "Accounts", label: "All inboxes (unified)", icon: "inbox", shortcut: "⌘0") { [weak self] in self?.currentAccount = "all" }
        ]
        for (i, a) in accounts.enumerated() {
            cmds.append(Command(id: "acct-\(a.id)", group: "Accounts", label: "Switch to \(a.name)", hint: a.email, icon: "mail", shortcut: "⌘\(i + 1)") { [weak self] in self?.currentAccount = a.id })
        }
        cmds.append(Command(id: "acct-add", group: "Accounts", label: "Add account…", icon: "user") { [weak self] in self?.addingAccount = true })
        return cmds
    }

    // MARK: - Tweak setters (persist)

    func setDark(_ v: Bool) { dark = v; persistTweaks() }
    func setSidebar(_ v: Bool) { sidebarVisible = v; persistTweaks() }
    func setReadingPane(_ v: Bool) { readingPane = v; persistTweaks() }
    func setVimNav(_ v: Bool) { vimNav = v; UserDefaults.standard.set(v, forKey: kVimNav) }
    func setConfirmDiscard(_ v: Bool) { confirmDiscard = v; UserDefaults.standard.set(v, forKey: kConfirmDiscard) }
    func setNotifications(_ v: Bool) {
        notificationsEnabled = v
        UserDefaults.standard.set(v, forKey: kNotifications)
        if v { Notifier.requestAuthorization() }
    }

    // MARK: - Account removal

    func removeRealAccount(_ accountId: String) {
        guard let cfg = config(for: accountId) else { return }
        Keychain.deletePassword(account: cfg.imapPasswordKey)
        Keychain.deletePassword(account: cfg.smtpPasswordKey)
        MailCache.clear(account: accountId)
        if let session = imapSessions[accountId] { Task { await session.close() } }
        imapSessions[accountId] = nil
        realMailboxes[accountId] = nil
        accountErrors[accountId] = nil
        lastSeenUID[accountId] = nil
        realConfigs.removeAll { $0.id == accountId }
        accounts.removeAll { $0.id == accountId }
        emails.removeAll { $0.account == accountId }
        persistRealAccounts()
        if currentAccount == accountId { currentAccount = "all" }
        if realConfigs.isEmpty { onboarding = true; selectedId = nil }
        showToast("Removed \(cfg.email)")
    }

    func activateSearch() {
        searchActive = true
        searchFocusRequested = true
    }

    // MARK: - Real mail (IMAP/SMTP)

    func isRealAccount(_ id: String) -> Bool { realConfigs.contains { $0.id == id } }
    func config(for id: String) -> MailAccountConfig? { realConfigs.first { $0.id == id } }

    static func uiAccount(for cfg: MailAccountConfig) -> Account {
        let display = cfg.displayName.isEmpty ? cfg.email : cfg.displayName
        let base = Sender.stableColorHex(for: cfg.email)
        return Account(id: cfg.id, name: display, email: cfg.email,
                       initials: String(display.prefix(1)).uppercased(),
                       gradient: [base, "1E2DB0"], colorHex: base, provider: "IMAP / SMTP")
    }

    func persistRealAccounts() {
        if let data = try? JSONEncoder().encode(realConfigs) {
            UserDefaults.standard.set(data, forKey: kRealAccounts)
        }
    }

    func addRealAccount(config: MailAccountConfig, imapPassword: String, smtpPassword: String) {
        Keychain.setPassword(imapPassword, account: config.imapPasswordKey)
        Keychain.setPassword(smtpPassword, account: config.smtpPasswordKey)
        realConfigs.append(config)
        accounts.append(AppModel.uiAccount(for: config))
        persistRealAccounts()
        addingAccount = false
        manualSetupOpen = false
        if onboarding { persistOnboarded(); onboarding = false }
        currentAccount = config.id
        folder = "inbox"
        loadFolder(config.id, "inbox")
    }

    /// Called whenever the selected account changes; refreshes the current folder.
    func didSelectAccount(_ id: String) {
        let f = folder == "home" ? "inbox" : folder
        guard isServerFolder(f) else { return }
        if id == "all" {
            for cfg in realConfigs { loadFolder(cfg.id, f, silent: true) }
        } else if isRealAccount(id) {
            loadFolder(id, f)
        }
    }

    /// Load a folder for whatever account scope is selected — a single real
    /// account, or every real account when the unified "All inboxes" is active.
    func loadForCurrentScope(_ folderId: String, silent: Bool = false) {
        guard isServerFolder(folderId) else { return }
        if currentAccount == "all" {
            for cfg in realConfigs { loadFolder(cfg.id, folderId, silent: silent) }
        } else if isRealAccount(currentAccount) {
            loadFolder(currentAccount, folderId, silent: silent)
        }
    }

    /// Resolve a canonical folder id to a server mailbox name.
    func mailboxName(_ accountId: String, _ folderId: String) -> String? {
        if folderId == "inbox" { return "INBOX" }
        return realMailboxes[accountId]?[folderId]
    }

    /// Folders that map to a real server mailbox / search and can be loaded.
    private func isServerFolder(_ folderId: String) -> Bool {
        !["home", "snoozed"].contains(folderId)
    }

    func refreshCurrentRealFolder(silent: Bool = false) {
        loadForCurrentScope(folder, silent: silent)
    }

    /// Long-lived IMAP connection per account (reused across operations).
    private func session(for accountId: String) -> IMAPSession? {
        if let s = imapSessions[accountId] { return s }
        guard let cfg = config(for: accountId), let pw = cfg.imapPassword else { return nil }
        let s = IMAPSession(config: cfg, password: pw)
        imapSessions[accountId] = s
        return s
    }

    /// Show real accounts' cached inboxes immediately on launch, then refresh.
    func bootstrapRealAccounts() {
        guard !didBootstrap else { return }
        didBootstrap = true
        if notificationsEnabled { Notifier.requestAuthorization() }
        processScheduledSends()
        for cfg in realConfigs {
            if let cached = MailCache.load(account: cfg.id, folder: "inbox"), !cached.isEmpty {
                emails.removeAll { $0.account == cfg.id && $0.folder == "inbox" }
                emails.append(contentsOf: cached)
            }
            loadFolder(cfg.id, "inbox", silent: true)
        }
        if selectedId == nil { selectedId = filteredEmails.first?.id }
    }

    func loadFolder(_ accountId: String, _ folderId: String, silent: Bool = false) {
        guard isRealAccount(accountId), isServerFolder(folderId), let session = session(for: accountId) else {
            if config(for: accountId)?.imapPassword == nil { accountErrors[accountId] = "Missing saved password." }
            return
        }
        // Show cached content instantly; only spin when there's nothing to show.
        var hasContent = emails.contains { $0.account == accountId && $0.folder == folderId }
        if !hasContent, let cached = MailCache.load(account: accountId, folder: folderId), !cached.isEmpty {
            mergeRealFolder(cached, accountId: accountId, folderId: folderId, persist: false)
            hasContent = true
        }
        if !silent && !hasContent { loadingAccounts.insert(accountId) }
        accountErrors[accountId] = nil
        let needDiscover = realMailboxes[accountId] == nil
        Task {
            do {
                if needDiscover {
                    let boxes = try await session.listMailboxes()
                    var m: [String: String] = [:]
                    for b in boxes where b.selectable {
                        switch b.kind {
                        case .sent: m["sent"] = b.name
                        case .drafts: m["drafts"] = b.name
                        case .trash: m["trash"] = b.name
                        case .junk: m["spam"] = b.name
                        case .archive: m["archive"] = b.name
                        default: break
                        }
                    }
                    await MainActor.run { self.realMailboxes[accountId] = m }
                }
                let map = await MainActor.run { self.realMailboxes[accountId] ?? [:] }

                let msgs: [IMAPMessage]
                switch folderId {
                case "inbox": msgs = try await session.fetchRecent(mailbox: "INBOX", limit: 50)
                case "starred": msgs = try await session.searchFlagged(mailbox: "INBOX", limit: 50)
                case "done":
                    if let arch = map["archive"] { msgs = try await session.fetchRecent(mailbox: arch, limit: 50) }
                    else { msgs = [] }
                default:
                    if let name = map[folderId] { msgs = try await session.fetchRecent(mailbox: name, limit: 50) }
                    else { msgs = [] }
                }
                let mapped = msgs.map { AppModel.makeEmail($0, accountId: accountId, folder: folderId) }
                await MainActor.run {
                    self.mergeRealFolder(mapped, accountId: accountId, folderId: folderId, persist: true)
                    self.loadingAccounts.remove(accountId)
                }
            } catch {
                await MainActor.run {
                    if !silent && !hasContent { self.accountErrors[accountId] = error.localizedDescription }
                    self.loadingAccounts.remove(accountId)
                }
            }
        }
    }

    /// Server-side full-text search across the whole mailbox (instant local
    /// filtering already covers loaded mail as you type; this augments it).
    func runServerSearch() {
        guard searchActive else { return }
        let q = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { serverSearchResults = nil; searching = false; return }
        let f = folder
        let accountIds: [String] = currentAccount == "all"
            ? realConfigs.map { $0.id }
            : (isRealAccount(currentAccount) ? [currentAccount] : [])
        guard !accountIds.isEmpty else { return }
        searching = true
        Task {
            var results: [Email] = []
            for acct in accountIds {
                guard let session = await MainActor.run(body: { self.session(for: acct) }) else { continue }
                let box = await MainActor.run { self.mailboxName(acct, f) } ?? "INBOX"
                if let msgs = try? await session.searchText(mailbox: box, query: q, limit: 50) {
                    results.append(contentsOf: msgs.map { AppModel.makeEmail($0, accountId: acct, folder: f) })
                }
            }
            await MainActor.run {
                self.serverSearchResults = results
                self.selectedId = results.first?.id
                self.searching = false
            }
        }
    }

    /// Replace a folder's messages, preserving already-fetched bodies and
    /// (optionally) writing the result to the on-disk cache.
    private func mergeRealFolder(_ newEmails: [Email], accountId: String, folderId: String, persist: Bool) {
        let existing = emails.filter { $0.account == accountId && $0.folder == folderId }
        var bodyByUID: [UInt32: (body: String, preview: String)] = [:]
        for e in existing where e.bodyLoaded && e.uid != nil { bodyByUID[e.uid!] = (e.body, e.preview) }
        var merged = newEmails
        for i in merged.indices {
            if let uid = merged[i].uid, !merged[i].bodyLoaded, let cached = bodyByUID[uid] {
                merged[i].body = cached.body
                merged[i].preview = cached.preview
                merged[i].bodyLoaded = true
            }
        }
        // New-mail notifications (inbox only, after a server refresh).
        if persist && folderId == "inbox" {
            let maxUID = merged.compactMap { $0.uid }.max() ?? 0
            if let last = lastSeenUID[accountId] {
                if notificationsEnabled {
                    for e in merged.filter({ ($0.uid ?? 0) > last && $0.unread }).prefix(5) {
                        Notifier.notify(title: e.resolvedSender.name, body: e.subject)
                    }
                }
                lastSeenUID[accountId] = max(last, maxUID)
            } else {
                lastSeenUID[accountId] = maxUID
            }
        }
        emails.removeAll { $0.account == accountId && $0.folder == folderId }
        emails.append(contentsOf: merged)
        if persist { MailCache.save(merged, account: accountId, folder: folderId) }
        let inScope = (currentAccount == accountId || currentAccount == "all")
        if inScope && folder == folderId && serverSearchResults == nil {
            if !filteredEmails.contains(where: { $0.id == selectedId }) {
                selectedId = filteredEmails.first?.id
            }
        }
    }

    static func makeEmail(_ m: IMAPMessage, accountId: String, folder: String) -> Email {
        let (day, time) = dayAndTime(m.date)
        let fromKey = m.fromEmail.isEmpty ? "imap-unknown" : m.fromEmail
        return Email(id: "\(accountId)#\(folder)#\(m.uid)", account: accountId, from: fromKey, to: nil,
                     subject: m.subject.isEmpty ? "(no subject)" : m.subject,
                     preview: "", body: "", time: time, day: day,
                     unread: !m.seen, starred: m.flagged, hasAttachment: false,
                     labels: [], folder: folder, thread: nil, snoozeUntil: nil,
                     fromName: m.fromName, fromEmail: m.fromEmail, uid: m.uid, bodyLoaded: false)
    }

    static func dayAndTime(_ date: Date) -> (String, String) {
        let cal = Calendar.current
        let f = DateFormatter(); f.locale = .current
        if cal.isDateInToday(date) { f.dateFormat = "h:mm a"; return ("today", f.string(from: date)) }
        if cal.isDateInYesterday(date) { return ("yesterday", "Yesterday") }
        if let days = cal.dateComponents([.day], from: date, to: Date()).day, days < 7 {
            f.dateFormat = "EEE"; return ("earlier", f.string(from: date))
        }
        f.dateFormat = "MMM d"; return ("earlier", f.string(from: date))
    }

    /// Fetch the body (and mark seen) the first time a real message is opened.
    func loadBodyIfNeeded() {
        guard let e = selectedEmail, isRealAccount(e.account), !e.bodyLoaded, let uid = e.uid,
              let session = session(for: e.account) else { return }
        let box = mailboxName(e.account, e.folder) ?? "INBOX"
        let id = e.id
        let acct = e.account, fld = e.folder
        Task {
            do {
                let body = try await session.fetchBody(mailbox: box, uid: uid)
                try? await session.store(mailbox: box, uid: uid, .seen, add: true)
                await MainActor.run {
                    if let i = self.emails.firstIndex(where: { $0.id == id }) {
                        self.emails[i].body = body
                        self.emails[i].preview = String(body.replacingOccurrences(of: "\n", with: " ").prefix(140))
                        self.emails[i].bodyLoaded = true
                    }
                    if let j = self.serverSearchResults?.firstIndex(where: { $0.id == id }) {
                        self.serverSearchResults?[j].body = body
                        self.serverSearchResults?[j].bodyLoaded = true
                    }
                    // Persist the loaded body so reopening is instant next time.
                    MailCache.save(self.emails.filter { $0.account == acct && $0.folder == fld },
                                   account: acct, folder: fld)
                }
            } catch { /* leave placeholder; surfaced via empty body */ }
        }
    }

    func applyRealFlag(_ email: Email, _ kind: MailFlagKind, add: Bool) {
        guard isRealAccount(email.account), let uid = email.uid, let session = session(for: email.account) else { return }
        let box = mailboxName(email.account, email.folder) ?? "INBOX"
        Task {
            try? await session.store(mailbox: box, uid: uid, kind, add: add)
        }
    }

    func realMove(_ email: Email, to folderId: String) {
        guard isRealAccount(email.account), let uid = email.uid, let session = session(for: email.account),
              let from = mailboxName(email.account, email.folder),
              let to = mailboxName(email.account, folderId) else { return }
        Task {
            try? await session.move(uid: uid, from: from, to: to)
        }
    }

    func startPolling() {
        guard pollTimer == nil else { return }
        // Every 30s: refresh current folder, fire any due scheduled sends, wake snoozed.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.refreshCurrentRealFolder(silent: true)
            self.processScheduledSends()
            self.wakeSnoozedIfDue()
        }
    }

    private func wakeSnoozedIfDue() {
        let now = Date()
        let expired = snoozedUntil.filter { $0.value <= now }
        guard !expired.isEmpty else { return }
        for key in expired.keys { snoozedUntil[key] = nil }
        persistSnoozed()
        refreshCurrentRealFolder(silent: true)
    }

    func persistSnoozed() {
        if let data = try? JSONEncoder().encode(snoozedUntil) { UserDefaults.standard.set(data, forKey: kSnoozed) }
    }

    /// Save the compose contents as a draft (best-effort APPEND to Drafts), then close.
    func saveDraftAndClose(_ draft: ComposeDraft) {
        compose = nil
        let hasContent = !draft.to.isEmpty || !draft.subject.isEmpty
            || !draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasContent, isRealAccount(draft.fromId), let cfg = config(for: draft.fromId),
              let session = session(for: draft.fromId) else { return }
        let display = accountsById[cfg.id]?.name
        let message = MIME.buildMessage(from: cfg.email, fromName: display, to: draft.to, cc: draft.cc,
                                        subject: draft.subject, body: draft.body)
        Task {
            if let draftsBox = await self.resolveMailbox(cfg.id, kind: .drafts, session: session) {
                try? await session.append(mailbox: draftsBox, rawMessage: message, seen: false, draft: true)
                await MainActor.run { self.showToast("Draft saved"); self.loadFolder(cfg.id, "drafts", silent: true) }
            }
        }
    }

    /// Resolve a special mailbox name, discovering the folder list if needed.
    private func resolveMailbox(_ accountId: String, kind: MailboxKind, session: IMAPSession) async -> String? {
        let folderId: String = {
            switch kind {
            case .sent: return "sent"; case .drafts: return "drafts"; case .trash: return "trash"
            case .junk: return "spam"; case .archive: return "archive"; default: return ""
            }
        }()
        if let name = await MainActor.run(body: { self.realMailboxes[accountId]?[folderId] }) { return name }
        guard let boxes = try? await session.listMailboxes() else { return nil }
        var m: [String: String] = [:]
        for b in boxes where b.selectable {
            switch b.kind {
            case .sent: m["sent"] = b.name; case .drafts: m["drafts"] = b.name
            case .trash: m["trash"] = b.name; case .junk: m["spam"] = b.name
            case .archive: m["archive"] = b.name; default: break
            }
        }
        await MainActor.run { self.realMailboxes[accountId] = m }
        return m[folderId]
    }

    static func parseRecipients(_ field: String) -> [String] {
        field.split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { piece -> String in
                let s = piece.trimmingCharacters(in: .whitespaces)
                if let lt = s.range(of: "<"), let gt = s.range(of: ">") {
                    return String(s[lt.upperBound..<gt.lowerBound]).trimmingCharacters(in: .whitespaces)
                }
                return s
            }
            .filter { $0.contains("@") }
    }

    // MARK: - Keyboard engine (NSEvent monitor)

    func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDown(event) ? nil : event
        }
    }

    func removeKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    private var isTyping: Bool {
        guard let r = NSApp.keyWindow?.firstResponder else { return false }
        return r is NSText || r is NSTextView
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags
        let cmd = flags.contains(.command)
        let shift = flags.contains(.shift)
        let chars = event.charactersIgnoringModifiers ?? ""
        let lower = chars.lowercased()

        // ⌘K — always
        if cmd && lower == "k" { palette.toggle(); return true }

        // ⌘0..9 — switch account
        if cmd && !shift, chars.count == 1, let n = Int(chars) {
            if n == 0 { currentAccount = "all"; return true }
            if n >= 1 && n <= accounts.count { currentAccount = accounts[n - 1].id; return true }
        }

        // ⌘⇧S / R / D
        if cmd && shift {
            switch lower {
            case "s": setSidebar(!sidebarVisible); return true
            case "r": setReadingPane(!readingPane); return true
            case "d": setDark(!dark); return true
            default: break
            }
        }

        // Escape (keyCode 53)
        if event.keyCode == 53 {
            if anyOverlayOpen { closeOverlays(); return true }
            if searchActive { searchActive = false; searchQuery = ""; return true }
            return false
        }

        // Below: single-key. Don't intercept when typing, an overlay owns focus,
        // or the user has turned off keyboard (vim) navigation in Settings.
        if isTyping || anyOverlayOpen || onboarding || !vimNav { return false }

        // ? help
        if chars == "?" { help = true; return true }
        // / search
        if chars == "/" { activateSearch(); return true }

        // g-prefix
        if pendingG {
            let dest = ["h": "home", "i": "inbox", "z": "snoozed", "e": "done", "t": "sent", "s": "starred", "d": "drafts"][lower]
            if let d = dest { setFolder(d) }
            pendingG = false
            return true
        }
        if lower == "g" {
            pendingG = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.pendingG = false }
            return true
        }

        // Home view has no list to triage/navigate
        let listActive = folder != "home"

        switch chars {
        case "j": if listActive { navigate(1) }; return listActive
        case "k": if listActive { navigate(-1) }; return listActive
        case "e": if listActive { archive() }; return listActive
        case "h": if listActive { markDone() }; return listActive
        case "#": if listActive { delete() }; return listActive
        case "u": if listActive { markUnread() }; return listActive
        case "s": if listActive { toggleStar() }; return listActive
        case "z": if listActive { snooze() }; return listActive
        case "c": startCompose(); return true
        case "r": reply(); return true
        case "a": replyAll(); return true
        case "f": forward(); return true
        default: return false
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

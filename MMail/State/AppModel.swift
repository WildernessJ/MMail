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
    var attachments: [ComposeAttachment] = []
    var bodyHTML: String? = nil   // set when the body uses rich formatting
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
    var attachments: [ComposeAttachment] = []
    var bodyHTML: String? = nil
}

struct AdvancedSearchForm {
    var text = ""
    var from = ""
    var to = ""
    var subject = ""
    var account = "all"        // "all" or a specific account id
    var useAfter = false
    var after = Date()
    var useBefore = false
    var before = Date()
    var unreadOnly = false
    var flaggedOnly = false
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
    // When the reading pane is off, this opens the selected message full-width.
    @Published var readerFullScreen = false
    // Bulk selection (checkboxes in the list).
    @Published var selectedIds: Set<String> = []
    var selectionActive: Bool { !selectedIds.isEmpty }

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
    @Published var advancedSearchOpen = false
    @Published var advForm = AdvancedSearchForm()
    @Published var searchModalOpen = false
    @Published var toast: ToastModel?
    @Published var pendingG = false
    @Published var journalArchiveOpen = false
    @Published var manualSetupOpen = false
    @Published var setupProvider: MailProvider?   // preset to pre-fill manual setup

    // Home dashboard
    @Published var todos: [Todo]
    @Published var journal: String
    @Published var journalRecent: [JournalEntry]

    // Reply templates
    @Published var templates: [ReplyTemplate]

    // Per-account signatures (auto-appended when composing).
    @Published var signatures: [String: String] = [:]
    private let kSignatures = "mmail.signatures"

    // Labels
    @Published var labels: [MailLabel]
    @Published var labelFilter: String?
    private let kLabels = "mmail.labels"

    // Blocked senders — their mail is moved to Trash immediately.
    @Published var blockedSenders: Set<String> = []
    private let kBlocked = "mmail.blocked"

    // Rules — auto label / archive / trash incoming mail.
    @Published var rules: [MailRule] = []
    private let kRules = "mmail.rules"

    // VIP senders — highlighted, and exempt from rules / blocking.
    @Published var vipSenders: Set<String> = []
    private let kVIP = "mmail.vip"

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
    @Published var downloadingAttachments: Set<String> = []
    private let kScheduled = "mmail.scheduled"
    private let kSnoozed = "mmail.snoozed"
    private var pollTimer: Timer?
    private var pollCount = 0
    private var imapSessions: [String: IMAPSession] = [:]
    private var didBootstrap = false
    private var pageLimits: [String: Int] = [:]
    @Published var weather: WeatherInfo?
    @Published var weatherCity = ""   // empty = auto (IP geolocation)
    @Published var peopleOpen = false
    private let kWeatherCity = "mmail.weatherCity"

    private var keyMonitor: Any?
    private var toastWorkItem: DispatchWorkItem?
    private var pendingSendWork: DispatchWorkItem?

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
            todos = []
        }
        if let data = d.data(forKey: kJournalRecent),
           let decoded = try? JSONDecoder().decode([JournalEntry].self, from: data) {
            journalRecent = decoded
        } else {
            journalRecent = []
        }
        if let data = d.data(forKey: kTemplates),
           let decoded = try? JSONDecoder().decode([ReplyTemplate].self, from: data), !decoded.isEmpty {
            templates = decoded
        } else {
            templates = SampleData.replyTemplates
        }
        if let data = d.data(forKey: kSignatures),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) { signatures = decoded }
        if let data = d.data(forKey: kLabels),
           let decoded = try? JSONDecoder().decode([MailLabel].self, from: data), !decoded.isEmpty {
            labels = decoded
        } else {
            labels = SampleData.labels
        }
        if let arr = d.array(forKey: kBlocked) as? [String] { blockedSenders = Set(arr) }
        if let arr = d.array(forKey: kVIP) as? [String] { vipSenders = Set(arr) }
        if let data = d.data(forKey: kRules),
           let decoded = try? JSONDecoder().decode([MailRule].self, from: data) { rules = decoded }
        if let data = d.data(forKey: kRealAccounts),
           let decoded = try? JSONDecoder().decode([MailAccountConfig].self, from: data) {
            realConfigs = decoded
            for cfg in decoded { accounts.append(AppModel.uiAccount(for: cfg)) }
        }
        weatherCity = d.string(forKey: kWeatherCity) ?? ""
        if let data = d.data(forKey: kScheduled),
           let decoded = try? JSONDecoder().decode([ScheduledSend].self, from: data) { scheduled = decoded }
        if let data = d.data(forKey: kSnoozed),
           let decoded = try? JSONDecoder().decode([String: Date].self, from: data) { snoozedUntil = decoded }
        // Welcome shows on first launch and whenever no account is connected.
        onboarding = accounts.isEmpty
        purgeSeedData()
    }

    /// Remove the old demo to-dos / journal entries that earlier builds seeded,
    /// so existing installs also end up clean. User-created items (different ids)
    /// are preserved.
    private func purgeSeedData() {
        let seedTodoIds: Set<String> = ["td1", "td2", "td3", "td4", "td5"]
        let cleanTodos = todos.filter { !seedTodoIds.contains($0.id) }
        if cleanTodos.count != todos.count { todos = cleanTodos; persistTodos() }

        let seedJournalIds: Set<String> = ["jr-yesterday", "jr-mar-18"]
        let cleanJournal = journalRecent.filter { !seedJournalIds.contains($0.id) }
        if cleanJournal.count != journalRecent.count { journalRecent = cleanJournal; persistJournalRecent() }
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
        if let lf = labelFilter {
            return accountFiltered.filter { $0.labels.contains(lf) && !isSnoozed($0) }
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
        if labelFilter != nil { return visibleEmails }
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
        palette || help || settings || compose != nil || addingAccount || journalArchiveOpen || manualSetupOpen || advancedSearchOpen || peopleOpen || searchModalOpen
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

    /// A row tap: select, and when the reading pane is off, open the full reader.
    func activate(_ id: String) {
        select(id)
        if !readingPane { readerFullScreen = true }
    }

    // MARK: - Bulk selection

    func toggleSelect(_ id: String) {
        if selectedIds.contains(id) { selectedIds.remove(id) } else { selectedIds.insert(id) }
    }
    func clearSelection() { selectedIds.removeAll() }
    func selectAllVisible() { selectedIds = Set(filteredEmails.map { $0.id }) }

    func bulkArchive() { bulkTriage(localFolder: "archive", serverFolder: "archive", verb: "Archived") }
    func bulkDone() { bulkTriage(localFolder: "done", serverFolder: "archive", verb: "Marked done") }

    func bulkDelete() {
        let ids = selectedIds
        for id in ids {
            guard let e = emails.first(where: { $0.id == id }) else { continue }
            if isRealAccount(e.account) {
                if mailboxName(e.account, "trash") != nil { realMove(e, to: "trash") }
                else { applyRealFlag(e, .deleted, add: true) }
            }
            if let i = emails.firstIndex(where: { $0.id == id }) { emails[i].folder = "trash" }
        }
        finishBulk(ids.count, "Deleted")
    }

    func bulkMarkRead(_ read: Bool) {
        let ids = selectedIds
        for id in ids {
            guard let i = emails.firstIndex(where: { $0.id == id }) else { continue }
            emails[i].unread = !read
            applyRealFlag(emails[i], .seen, add: read)
        }
        finishBulk(ids.count, read ? "Marked read" : "Marked unread")
    }

    private func bulkTriage(localFolder: String, serverFolder: String, verb: String) {
        let ids = selectedIds
        for id in ids {
            guard let e = emails.first(where: { $0.id == id }) else { continue }
            if isRealAccount(e.account), mailboxName(e.account, serverFolder) != nil { realMove(e, to: serverFolder) }
            if let i = emails.firstIndex(where: { $0.id == id }) { emails[i].folder = localFolder }
        }
        finishBulk(ids.count, verb)
    }

    private func finishBulk(_ n: Int, _ verb: String) {
        clearSelection()
        if !filteredEmails.contains(where: { $0.id == selectedId }) { selectedId = filteredEmails.first?.id }
        showToast("\(n) message\(n == 1 ? "" : "s") · \(verb.lowercased())")
    }

    func closeFullReader() { readerFullScreen = false }

    func markSelectedReadSoon() {
        guard let e = selectedEmail, e.unread else { return }
        let id = e.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, let i = self.emails.firstIndex(where: { $0.id == id }) else { return }
            self.emails[i].unread = false
            // Mark seen on the server here (not in loadBodyIfNeeded), so prefetched
            // messages — whose body is already loaded — still get marked read on open.
            self.applyRealFlag(self.emails[i], .seen, add: true)
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

    // MARK: - Labels

    func label(for id: String) -> MailLabel? { labels.first { $0.id == id } }

    func persistLabels() {
        if let data = try? JSONEncoder().encode(labels) { UserDefaults.standard.set(data, forKey: kLabels) }
    }

    /// Turn a free-form label name into a valid IMAP keyword (atom): lowercase,
    /// alphanumerics plus `-`/`_`, everything else collapsed to a dash.
    static func sanitizeLabelId(_ name: String) -> String {
        let lowered = name.lowercased()
        var out = ""
        var lastDash = false
        for ch in lowered {
            if ch.isLetter || ch.isNumber || ch == "-" || ch == "_" {
                out.append(ch); lastDash = false
            } else if !lastDash {
                out.append("-"); lastDash = true
            }
        }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    static func prettifyLabel(_ id: String) -> String {
        let words = id.split(whereSeparator: { $0 == "-" || $0 == "_" }).map(String.init)
        return words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    /// Create a new label from a display name (idempotent on the derived id).
    @discardableResult
    func addLabel(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let id = AppModel.sanitizeLabelId(trimmed)
        guard !id.isEmpty else { return nil }
        if labels.contains(where: { $0.id == id }) { return id }
        labels.append(MailLabel(id: id, name: trimmed.isEmpty ? AppModel.prettifyLabel(id) : trimmed,
                                colorHex: Sender.stableColorHex(for: id)))
        persistLabels()
        return id
    }

    /// Add or remove a label on a message (local + on the server via IMAP keyword).
    func applyLabel(_ email: Email, _ labelId: String, add: Bool) {
        guard let i = emails.firstIndex(where: { $0.id == email.id }) else { return }
        if add {
            if !emails[i].labels.contains(labelId) { emails[i].labels.append(labelId) }
        } else {
            emails[i].labels.removeAll { $0 == labelId }
        }
        let updated = emails[i]
        MailCache.save(emails.filter { $0.account == updated.account && $0.folder == updated.folder },
                       account: updated.account, folder: updated.folder)
        guard isRealAccount(email.account), let uid = email.uid, let session = session(for: email.account) else { return }
        let box = mailboxName(email.account, email.folder) ?? "INBOX"
        Task { try? await session.storeKeyword(mailbox: box, uid: uid, keyword: labelId, add: add) }
    }

    /// Register any labels encountered on freshly loaded mail so they show up in
    /// the sidebar and label menu.
    private func registerLabels(from list: [Email]) {
        let known = Set(labels.map { $0.id })
        let encountered = Set(list.flatMap { $0.labels })
        let fresh = encountered.subtracting(known)
        guard !fresh.isEmpty else { return }
        for id in fresh.sorted() {
            labels.append(MailLabel(id: id, name: AppModel.prettifyLabel(id), colorHex: Sender.stableColorHex(for: id)))
        }
        persistLabels()
    }

    /// Filter the list to a single label (across all loaded folders).
    func selectLabel(_ id: String) {
        labelFilter = id
        searchActive = false
        searchQuery = ""
        serverSearchResults = nil
        searching = false
        loadForCurrentScope("inbox", silent: true)
        selectedId = filteredEmails.first?.id
    }

    // MARK: - Blocked senders

    func isBlocked(_ email: String?) -> Bool {
        guard let e = email?.lowercased(), !e.isEmpty else { return false }
        return blockedSenders.contains(e)
    }

    private func persistBlocked() {
        UserDefaults.standard.set(Array(blockedSenders), forKey: kBlocked)
    }

    /// Block a sender: remember the address and move any of their loaded mail to
    /// Trash now. Future arrivals are trashed on load (see `autoTrashBlocked`).
    func blockSender(_ email: String) {
        let e = email.lowercased().trimmingCharacters(in: .whitespaces)
        guard e.contains("@") else { return }
        blockedSenders.insert(e)
        persistBlocked()
        let skip: Set<String> = ["trash", "sent", "drafts"]
        let targets = emails.filter { ($0.fromEmail?.lowercased() == e) && !skip.contains($0.folder) }
        for t in targets where isRealAccount(t.account) && mailboxName(t.account, "trash") != nil {
            realMove(t, to: "trash")
        }
        for i in emails.indices where (emails[i].fromEmail?.lowercased() == e) && !skip.contains(emails[i].folder) {
            emails[i].folder = "trash"
        }
        if !filteredEmails.contains(where: { $0.id == selectedId }) { selectedId = filteredEmails.first?.id }
        showToast("Blocked \(e)")
    }

    func unblockSender(_ email: String) {
        blockedSenders.remove(email.lowercased())
        persistBlocked()
    }

    // MARK: - VIP senders

    func isVIP(_ email: String?) -> Bool {
        guard let e = email?.lowercased(), !e.isEmpty else { return false }
        return vipSenders.contains(e)
    }

    func toggleVIP(_ email: String) {
        let e = email.lowercased().trimmingCharacters(in: .whitespaces)
        guard e.contains("@") else { return }
        if vipSenders.contains(e) { vipSenders.remove(e) } else { vipSenders.insert(e) }
        UserDefaults.standard.set(Array(vipSenders), forKey: kVIP)
    }

    func removeVIP(_ email: String) {
        vipSenders.remove(email.lowercased())
        UserDefaults.standard.set(Array(vipSenders), forKey: kVIP)
    }

    // MARK: - Rules

    func persistRules() {
        if let data = try? JSONEncoder().encode(rules) { UserDefaults.standard.set(data, forKey: kRules) }
    }

    @discardableResult
    func addRule(field: MailRule.Field, value: String, action: MailRule.Action, labelId: String?) -> Bool {
        let v = value.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty else { return false }
        rules.append(MailRule(field: field, value: v, action: action,
                              labelId: action == .label ? labelId : nil))
        persistRules()
        return true
    }

    func removeRule(_ id: String) {
        rules.removeAll { $0.id == id }
        persistRules()
    }

    /// Run rules over freshly-loaded inbox mail: apply labels, then move
    /// (Trash wins over Archive). Runs after block filtering.
    private func applyRules(accountId: String, folderId: String) {
        guard folderId == "inbox", !rules.isEmpty else { return }
        let inbox = emails.filter { $0.account == accountId && $0.folder == "inbox" }
        for e in inbox where !isVIP(e.fromEmail) {
            var move: String?
            var labelsToAdd: [String] = []
            for rule in rules where rule.matches(e) {
                switch rule.action {
                case .trash: move = "trash"
                case .archive: if move != "trash" { move = "archive" }
                case .label: if let l = rule.labelId { labelsToAdd.append(l) }
                }
            }
            for l in labelsToAdd { applyLabel(e, l, add: true) }
            if let move, let cur = emails.first(where: { $0.id == e.id }) {
                if isRealAccount(accountId), mailboxName(accountId, move) != nil { realMove(cur, to: move) }
                if let i = emails.firstIndex(where: { $0.id == e.id }) { emails[i].folder = move }
            }
        }
    }

    /// Act on a message's List-Unsubscribe header: open the https page, or
    /// compose the unsubscribe email in-app for a mailto: link.
    func unsubscribe(_ email: Email) {
        guard let raw = email.unsubscribe else { return }
        var https: URL?, mailto: URL?
        for part in raw.components(separatedBy: ",") {
            let inner = part.trimmingCharacters(in: CharacterSet(charactersIn: "<> \t"))
            if inner.lowercased().hasPrefix("http"), https == nil { https = URL(string: inner) }
            else if inner.lowercased().hasPrefix("mailto:"), mailto == nil { mailto = URL(string: inner) }
        }
        if let https {
            NSWorkspace.shared.open(https)
            showToast("Opening unsubscribe page…")
        } else if let mailto, let comps = URLComponents(url: mailto, resolvingAgainstBaseURL: false) {
            let to = comps.path
            let subject = comps.queryItems?.first { $0.name.lowercased() == "subject" }?.value ?? "Unsubscribe"
            let body = comps.queryItems?.first { $0.name.lowercased() == "body" }?.value ?? "Please unsubscribe me."
            startCompose(to: to, subject: subject, body: body, titleLabel: "Unsubscribe", fromId: email.account)
        } else {
            showToast("No usable unsubscribe link found")
        }
    }

    /// Move freshly-loaded inbox mail from blocked senders straight to Trash.
    private func autoTrashBlocked(accountId: String, folderId: String) {
        guard folderId == "inbox", !blockedSenders.isEmpty else { return }
        let targets = emails.filter {
            $0.account == accountId && $0.folder == "inbox" && isBlocked($0.fromEmail) && !isVIP($0.fromEmail)
        }
        guard !targets.isEmpty else { return }
        for t in targets where isRealAccount(t.account) && mailboxName(t.account, "trash") != nil {
            realMove(t, to: "trash")
        }
        let ids = Set(targets.map { $0.id })
        for i in emails.indices where ids.contains(emails[i].id) { emails[i].folder = "trash" }
    }

    static let labelPalette = ["E5484D", "1FB36B", "7A5AE0", "F4A52A", "2D3DEC",
                               "0EA5E9", "D946EF", "06B6D4", "B25A2A", "635BFF"]

    func renameLabel(_ id: String, to newName: String) {
        guard let i = labels.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        labels[i] = MailLabel(id: id, name: trimmed.isEmpty ? AppModel.prettifyLabel(id) : trimmed,
                              colorHex: labels[i].colorHex)
        persistLabels()
    }

    func setLabelColor(_ id: String, hex: String) {
        guard let i = labels.firstIndex(where: { $0.id == id }) else { return }
        labels[i] = MailLabel(id: id, name: labels[i].name, colorHex: hex)
        persistLabels()
    }

    /// Delete a label: strip the keyword off every loaded message (local + server)
    /// then drop the definition.
    func deleteLabel(_ id: String) {
        let targets = emails.filter { $0.labels.contains(id) }
        for e in targets { applyLabel(e, id, add: false) }
        labels.removeAll { $0.id == id }
        if labelFilter == id { labelFilter = nil }
        persistLabels()
    }

    // MARK: - Weather

    func setWeatherCity(_ city: String) {
        weatherCity = city.trimmingCharacters(in: .whitespaces)
        UserDefaults.standard.set(weatherCity, forKey: kWeatherCity)
        refreshWeather()
    }

    func refreshWeather() {
        let city = weatherCity
        Task {
            let w = await WeatherService.fetch(city: city.isEmpty ? nil : city)
            await MainActor.run { if let w { self.weather = w } }
        }
    }

    // MARK: - Contacts (derived from the inbox)

    /// Distinct human senders from the current account scope's inbox, most recent first.
    func contacts(limit: Int? = nil) -> [Sender] {
        let scope = currentAccount == "all" ? emails : emails.filter { $0.account == currentAccount }
        var seen = Set<String>()
        var result: [Sender] = []
        for e in scope where e.folder == "inbox" {
            let s = e.resolvedSender
            guard !s.email.isEmpty, s.id != "you", s.org != .bot else { continue }
            if seen.insert(s.email).inserted {
                result.append(s)
                if let limit, result.count == limit { break }
            }
        }
        return result
    }

    // MARK: - Compose

    func startCompose(to: String = "", subject: String = "", body: String = "",
                      titleLabel: String = "New message", fromId: String? = nil) {
        // Reply/forward pass the receiving account; a fresh compose uses the first account.
        let defaultFrom = accounts.first?.id ?? "work"
        let from = fromId ?? defaultFrom
        let sig = signature(for: from)
        // Signature sits above any quoted history; the caret opens at the very top.
        let finalBody = sig.isEmpty ? body : "\n\n-- \n\(sig)\(body)"
        compose = ComposeDraft(to: to, subject: subject, body: finalBody,
                               titleLabel: titleLabel, fromId: from)
    }

    func signature(for accountId: String) -> String { signatures[accountId] ?? "" }

    func setSignature(_ accountId: String, _ text: String) {
        signatures[accountId] = text
        if let data = try? JSONEncoder().encode(signatures) { UserDefaults.standard.set(data, forKey: kSignatures) }
    }

    func sendDraft(_ draft: ComposeDraft) {
        let dest = draft.to.isEmpty ? "(unknown)" : draft.to
        if isRealAccount(draft.fromId) {
            guard let cfg = config(for: draft.fromId), cfg.smtpPassword != nil else { showToast("Missing SMTP password."); return }
            let recipients = AppModel.parseRecipients(draft.to) + AppModel.parseRecipients(draft.cc) + AppModel.parseRecipients(draft.bcc)
            guard !recipients.isEmpty else { showToast("Add a recipient first."); return }
            compose = nil
            // Undo Send: hold the message briefly so it can be called back.
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pendingSendWork = nil
                self.performSend(draft)
            }
            pendingSendWork = work
            showToast("Sending to \(dest)…", actionLabel: "Undo", duration: 5) { [weak self] in
                guard let self else { return }
                self.pendingSendWork?.cancel()
                self.pendingSendWork = nil
                self.compose = draft   // reopen so it can be edited or re-sent
                self.showToast("Send canceled")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
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
                                       body: draft.body, sendAt: date, attachments: draft.attachments,
                                       bodyHTML: draft.bodyHTML))
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
                                     body: s.body, titleLabel: "", fromId: s.fromId, attachments: s.attachments,
                                     bodyHTML: s.bodyHTML)
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
                                        subject: draft.subject, body: draft.body, attachments: draft.attachments,
                                        bodyHTML: draft.bodyHTML)
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

    func showToast(_ message: String, actionLabel: String? = nil, duration: TimeInterval = 3.5, action: (() -> Void)? = nil) {
        toast = ToastModel(message: message, actionLabel: actionLabel, action: action)
        toastWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    func closeOverlays() {
        palette = false; help = false; settings = false; compose = nil; addingAccount = false
        journalArchiveOpen = false; manualSetupOpen = false; advancedSearchOpen = false; peopleOpen = false
        searchModalOpen = false
    }

    func setFolder(_ f: String) {
        folder = f
        labelFilter = nil
        readerFullScreen = false
        clearSelection()
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
    func setReadingPane(_ v: Bool) { readingPane = v; readerFullScreen = false; persistTweaks() }
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

    /// Open the manual IMAP/SMTP setup, optionally pre-filled for a provider.
    func openSetup(_ provider: MailProvider? = nil) {
        setupProvider = provider
        addingAccount = false
        manualSetupOpen = true
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
    func loadForCurrentScope(_ folderId: String, silent: Bool = false, incremental: Bool = false) {
        guard isServerFolder(folderId) else { return }
        if currentAccount == "all" {
            for cfg in realConfigs { loadFolder(cfg.id, folderId, silent: silent, incremental: incremental) }
        } else if isRealAccount(currentAccount) {
            loadFolder(currentAccount, folderId, silent: silent, incremental: incremental)
        }
    }

    /// Resolve a canonical folder id to a server mailbox name.
    func mailboxName(_ accountId: String, _ folderId: String) -> String? {
        if folderId == "inbox" { return "INBOX" }
        return realMailboxes[accountId]?[folderId]
    }

    /// Folders that map to a real server mailbox / search and can be loaded.
    private func isServerFolder(_ folderId: String) -> Bool {
        !["home", "snoozed", "outbox"].contains(folderId)
    }

    func cancelScheduled(_ id: String) {
        scheduled.removeAll { $0.id == id }
        persistScheduled()
        showToast("Scheduled send canceled")
    }

    func sendScheduledNow(_ id: String) {
        guard let s = scheduled.first(where: { $0.id == id }) else { return }
        scheduled.removeAll { $0.id == id }
        persistScheduled()
        let draft = ComposeDraft(to: s.to, cc: s.cc, bcc: s.bcc, subject: s.subject,
                                 body: s.body, titleLabel: "", fromId: s.fromId,
                                 attachments: s.attachments, bodyHTML: s.bodyHTML)
        performSend(draft)
    }

    func refreshCurrentRealFolder(silent: Bool = false, incremental: Bool = false) {
        loadForCurrentScope(folder, silent: silent, incremental: incremental)
    }

    // MARK: - Pagination

    func pageLimit(_ account: String, _ folderId: String) -> Int { pageLimits["\(account)#\(folderId)"] ?? 50 }

    var canLoadMore: Bool {
        guard isServerFolder(folder), serverSearchResults == nil,
              !(searchActive && !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty) else { return false }
        let scope = currentAccount == "all" ? realConfigs.map { $0.id } : [currentAccount]
        for a in scope where isRealAccount(a) {
            if emails.filter({ $0.account == a && $0.folder == folder }).count >= pageLimit(a, folder) { return true }
        }
        return false
    }

    func loadMore() {
        guard isServerFolder(folder) else { return }
        let ids = currentAccount == "all" ? realConfigs.map { $0.id } : (isRealAccount(currentAccount) ? [currentAccount] : [])
        for a in ids { pageLimits["\(a)#\(folder)"] = pageLimit(a, folder) + 50 }
        loadForCurrentScope(folder, silent: true)
    }

    // MARK: - Threading (client-side, from loaded mail)

    static func normalizeSubject(_ s: String) -> String {
        var t = s.lowercased().trimmingCharacters(in: .whitespaces)
        while true {
            if t.hasPrefix("re:") { t = String(t.dropFirst(3)).trimmingCharacters(in: .whitespaces) }
            else if t.hasPrefix("fwd:") { t = String(t.dropFirst(4)).trimmingCharacters(in: .whitespaces) }
            else if t.hasPrefix("fw:") { t = String(t.dropFirst(3)).trimmingCharacters(in: .whitespaces) }
            else { break }
        }
        return t
    }

    private static func normMessageID(_ s: String?) -> String? {
        guard let s else { return nil }
        let t = s.trimmingCharacters(in: CharacterSet(charactersIn: "<> \t")).trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t
    }

    func relatedThread(for email: Email) -> [ThreadItem] {
        guard isRealAccount(email.account) else { return [] }
        let pool = emails.filter { $0.account == email.account }

        // Build a graph linking replies to parents via In-Reply-To -> Message-ID.
        var byMID: [String: Email] = [:]
        for e in pool { if let m = AppModel.normMessageID(e.messageID) { byMID[m] = e } }
        var adj: [String: Set<String>] = [:]
        for e in pool {
            if let irt = AppModel.normMessageID(e.inReplyTo), let parent = byMID[irt], parent.id != e.id {
                adj[e.id, default: []].insert(parent.id)
                adj[parent.id, default: []].insert(e.id)
            }
        }
        // Connected component containing this email (its conversation).
        var seen: Set<String> = [email.id]
        var stack = [email.id]
        while let cur = stack.popLast() {
            for n in adj[cur] ?? [] where seen.insert(n).inserted { stack.append(n) }
        }
        let byId = Dictionary(uniqueKeysWithValues: pool.map { ($0.id, $0) })
        var thread = seen.compactMap { byId[$0] }.filter { $0.id != email.id }

        // Fall back to normalized-subject grouping when there are no header links.
        if thread.isEmpty {
            let norm = AppModel.normalizeSubject(email.subject)
            guard !norm.isEmpty else { return [] }
            thread = pool.filter { $0.id != email.id && AppModel.normalizeSubject($0.subject) == norm }
        }
        return thread.prefix(8).map {
            ThreadItem(from: $0.resolvedSender.name, time: $0.time,
                       preview: $0.preview.isEmpty ? $0.subject : $0.preview,
                       emailId: $0.id)
        }
    }

    /// Open another message from the current conversation in the reader.
    func openThreadMessage(_ id: String) {
        guard let e = emails.first(where: { $0.id == id }) else { return }
        labelFilter = nil
        searchActive = false
        searchQuery = ""
        serverSearchResults = nil
        if currentAccount != "all" && currentAccount != e.account { currentAccount = e.account }
        folder = e.folder
        selectedId = id
        if !readingPane { readerFullScreen = true }
        loadBodyIfNeeded()
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
        refreshWeather()
        for cfg in realConfigs {
            if let cached = MailCache.load(account: cfg.id, folder: "inbox"), !cached.isEmpty {
                emails.removeAll { $0.account == cfg.id && $0.folder == "inbox" }
                emails.append(contentsOf: cached)
            }
            loadFolder(cfg.id, "inbox", silent: true)
        }
        if selectedId == nil { selectedId = filteredEmails.first?.id }
    }

    func loadFolder(_ accountId: String, _ folderId: String, silent: Bool = false, incremental: Bool = false) {
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
        let limit = pageLimit(accountId, folderId)
        // Incremental only for plain mailboxes (starred is a live search) when we
        // already have a loaded window and don't need folder discovery.
        let loaded = emails.filter { $0.account == accountId && $0.folder == folderId }
        let canIncrement = incremental && !needDiscover && folderId != "starred"
            && !loaded.isEmpty && loaded.compactMap { $0.uid }.max() != nil
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

                let box: String? = {
                    switch folderId {
                    case "inbox": return "INBOX"
                    case "starred": return nil
                    case "done": return map["archive"]
                    default: return map[folderId]
                    }
                }()

                if canIncrement, let box {
                    let uids = loaded.compactMap { $0.uid }
                    let sync = try await session.syncFolder(mailbox: box, afterUID: uids.max() ?? 0,
                                                            oldestUID: uids.min() ?? 0, newLimit: limit)
                    await MainActor.run {
                        self.mergeIncremental(sync, accountId: accountId, folderId: folderId)
                        self.loadingAccounts.remove(accountId)
                    }
                    return
                }

                let msgs: [IMAPMessage]
                switch folderId {
                case "inbox": msgs = try await session.fetchRecent(mailbox: "INBOX", limit: limit)
                case "starred": msgs = try await session.searchFlagged(mailbox: "INBOX", limit: limit)
                default:
                    if let box { msgs = try await session.fetchRecent(mailbox: box, limit: limit) }
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

    /// Enter in the search field: open the results modal and run the query.
    func submitSearch() {
        let q = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        searchActive = true
        serverSearchResults = localSearch(q)   // instant offline results from cache
        searchModalOpen = true
        runServerSearch()                        // augment with server-side matches
    }

    /// Search every cached message on disk (plus in-memory) — works offline and
    /// covers folders/messages not currently loaded.
    func localSearch(_ query: String) -> [Email] {
        let q = query.lowercased()
        guard !q.isEmpty else { return [] }
        var byId: [String: Email] = [:]
        for e in emails { byId[e.id] = e }
        for e in MailCache.loadAll() where byId[e.id] == nil { byId[e.id] = e }
        let scope = byId.values.filter { currentAccount == "all" || $0.account == currentAccount }
        return scope.filter { e in
            e.subject.lowercased().contains(q) || e.preview.lowercased().contains(q)
                || e.body.lowercased().contains(q)
                || (e.fromName?.lowercased().contains(q) ?? false)
                || (e.fromEmail?.lowercased().contains(q) ?? false)
        }
        .sorted { ($0.uid ?? 0) > ($1.uid ?? 0) }
        .prefix(100).map { $0 }
    }

    /// Dismiss the search modal and clear the query/results.
    func dismissSearch() {
        searchModalOpen = false
        searchActive = false
        searchQuery = ""
        serverSearchResults = nil
        searching = false
    }

    /// Open a tapped search result in the reader, leaving search behind.
    func openSearchResult(_ email: Email) {
        if !emails.contains(where: { $0.id == email.id }) { emails.append(email) }
        searchModalOpen = false
        searchActive = false
        searchQuery = ""
        serverSearchResults = nil
        searching = false
        labelFilter = nil
        if currentAccount != "all" && currentAccount != email.account { currentAccount = email.account }
        folder = email.folder
        selectedId = email.id
        readerFullScreen = !readingPane
        loadBodyIfNeeded()
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
                // Merge server hits into the instant offline results, deduping by id.
                var combined = self.serverSearchResults ?? []
                let have = Set(combined.map { $0.id })
                combined.append(contentsOf: results.filter { !have.contains($0.id) })
                self.serverSearchResults = combined
                self.selectedId = combined.first?.id
                self.searching = false
            }
        }
    }

    // MARK: - Advanced search

    func openAdvancedSearch() {
        if advForm.account == "all" && currentAccount != "all" && isRealAccount(currentAccount) {
            advForm.account = currentAccount
        }
        advancedSearchOpen = true
    }

    /// Run a structured server-side search built from the advanced-search form.
    func runAdvancedSearch() {
        let f = advForm
        var crit = MailSearchCriteria()
        crit.text = f.text.trimmingCharacters(in: .whitespaces)
        crit.from = f.from.trimmingCharacters(in: .whitespaces)
        crit.to = f.to.trimmingCharacters(in: .whitespaces)
        crit.subject = f.subject.trimmingCharacters(in: .whitespaces)
        crit.since = f.useAfter ? Calendar.current.startOfDay(for: f.after) : nil
        // BEFORE is exclusive; bump to the next day so the chosen date is included.
        crit.before = f.useBefore ? Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: f.before)) : nil
        crit.unseenOnly = f.unreadOnly
        crit.flaggedOnly = f.flaggedOnly
        guard !crit.isEmpty else { showToast("Add at least one filter"); return }

        let scope: [String] = f.account == "all" ? realConfigs.map { $0.id } : [f.account]
        let accountIds = scope.filter { isRealAccount($0) }
        guard !accountIds.isEmpty else { showToast("No mail account to search"); return }

        advancedSearchOpen = false
        searchActive = true
        searchQuery = describeAdvanced(f)
        searching = true
        serverSearchResults = []
        searchModalOpen = true
        let fld = folder == "home" ? "inbox" : folder
        Task {
            var results: [Email] = []
            for acct in accountIds {
                guard let session = await MainActor.run(body: { self.session(for: acct) }) else { continue }
                let box = await MainActor.run { self.mailboxName(acct, fld) } ?? "INBOX"
                if let msgs = try? await session.searchAdvanced(mailbox: box, criteria: crit, limit: 100) {
                    results.append(contentsOf: msgs.map { AppModel.makeEmail($0, accountId: acct, folder: fld) })
                }
            }
            await MainActor.run {
                self.serverSearchResults = results
                self.selectedId = results.first?.id
                self.searching = false
            }
        }
    }

    private func describeAdvanced(_ f: AdvancedSearchForm) -> String {
        var parts: [String] = []
        if !f.text.isEmpty { parts.append(f.text) }
        if !f.from.isEmpty { parts.append("from:\(f.from)") }
        if !f.to.isEmpty { parts.append("to:\(f.to)") }
        if !f.subject.isEmpty { parts.append("subject:\(f.subject)") }
        if f.unreadOnly { parts.append("is:unread") }
        if f.flaggedOnly { parts.append("is:starred") }
        let df = DateFormatter(); df.dateFormat = "MMM d"
        if f.useAfter { parts.append("after:\(df.string(from: f.after))") }
        if f.useBefore { parts.append("before:\(df.string(from: f.before))") }
        return parts.isEmpty ? "Advanced search" : parts.joined(separator: " ")
    }

    /// Replace a folder's messages, preserving already-fetched bodies and
    /// (optionally) writing the result to the on-disk cache.
    private func mergeRealFolder(_ newEmails: [Email], accountId: String, folderId: String, persist: Bool) {
        let existing = emails.filter { $0.account == accountId && $0.folder == folderId }
        var loadedByUID: [UInt32: Email] = [:]
        for e in existing where e.bodyLoaded && e.uid != nil { loadedByUID[e.uid!] = e }
        var merged = newEmails
        for i in merged.indices {
            if let uid = merged[i].uid, !merged[i].bodyLoaded, let old = loadedByUID[uid] {
                merged[i].body = old.body
                merged[i].preview = old.preview
                merged[i].bodyLoaded = true
                merged[i].attachments = old.attachments
                merged[i].hasAttachment = old.hasAttachment
                merged[i].bodyHTML = old.bodyHTML
                merged[i].unsubscribe = old.unsubscribe
            }
        }
        // New-mail notifications (inbox only, after a server refresh).
        if persist && folderId == "inbox" {
            let maxUID = merged.compactMap { $0.uid }.max() ?? 0
            if let last = lastSeenUID[accountId] {
                if notificationsEnabled {
                    for e in merged.filter({ ($0.uid ?? 0) > last && $0.unread && !isBlocked($0.fromEmail) }).prefix(5) {
                        Notifier.notify(title: e.resolvedSender.name, body: e.subject)
                    }
                }
                lastSeenUID[accountId] = max(last, maxUID)
            } else {
                lastSeenUID[accountId] = maxUID
            }
        }
        registerLabels(from: merged)
        emails.removeAll { $0.account == accountId && $0.folder == folderId }
        emails.append(contentsOf: merged)
        if persist { MailCache.save(merged, account: accountId, folder: folderId) }
        if persist { autoTrashBlocked(accountId: accountId, folderId: folderId); applyRules(accountId: accountId, folderId: folderId) }
        let inScope = (currentAccount == accountId || currentAccount == "all")
        if inScope && folder == folderId && serverSearchResults == nil {
            if !filteredEmails.contains(where: { $0.id == selectedId }) {
                selectedId = filteredEmails.first?.id
            }
        }
        if persist { prefetchBodies(accountId, folderId) }
    }

    /// Apply an incremental refresh: update flags on the loaded window, append
    /// any new messages, persist, and prefetch the newest/starred bodies.
    private func mergeIncremental(_ sync: IMAPFolderSync, accountId: String, folderId: String) {
        for (uid, fs) in sync.flags {
            if let i = emails.firstIndex(where: { $0.account == accountId && $0.folder == folderId && $0.uid == uid }) {
                emails[i].unread = !fs.seen
                emails[i].starred = fs.flagged
                emails[i].labels = fs.keywords.map { $0.lowercased() }
            }
        }
        let existingUIDs = Set(emails.filter { $0.account == accountId && $0.folder == folderId }.compactMap { $0.uid })
        let fresh = sync.newMessages.filter { !existingUIDs.contains($0.uid) }
        if !fresh.isEmpty {
            let mapped = fresh.map { AppModel.makeEmail($0, accountId: accountId, folder: folderId) }
            if folderId == "inbox", notificationsEnabled, let last = lastSeenUID[accountId] {
                for e in mapped.filter({ ($0.uid ?? 0) > last && $0.unread && !isBlocked($0.fromEmail) }).prefix(5) {
                    Notifier.notify(title: e.resolvedSender.name, body: e.subject)
                }
            }
            emails.append(contentsOf: mapped)
            registerLabels(from: mapped)
        }
        if folderId == "inbox" {
            let maxUID = emails.filter { $0.account == accountId && $0.folder == folderId }.compactMap { $0.uid }.max() ?? 0
            lastSeenUID[accountId] = max(lastSeenUID[accountId] ?? 0, maxUID)
        }
        autoTrashBlocked(accountId: accountId, folderId: folderId)
        applyRules(accountId: accountId, folderId: folderId)
        MailCache.save(emails.filter { $0.account == accountId && $0.folder == folderId }, account: accountId, folder: folderId)
        let inScope = (currentAccount == accountId || currentAccount == "all")
        if inScope && folder == folderId && serverSearchResults == nil {
            if !filteredEmails.contains(where: { $0.id == selectedId }) {
                selectedId = filteredEmails.first?.id
            }
        }
        prefetchBodies(accountId, folderId)
    }

    /// Warm the cache for the messages most likely to be opened: the newest few
    /// in the folder and every starred message. Uses BODY.PEEK so it never marks
    /// anything as read. Bodies already loaded are skipped.
    private func prefetchBodies(_ accountId: String, _ folderId: String) {
        guard isRealAccount(accountId), let session = session(for: accountId) else { return }
        let box = mailboxName(accountId, folderId) ?? "INBOX"
        let pool = emails.filter { $0.account == accountId && $0.folder == folderId && !$0.bodyLoaded && $0.uid != nil }
        guard !pool.isEmpty else { return }
        let newest = pool.sorted { ($0.uid ?? 0) > ($1.uid ?? 0) }.prefix(8)
        let starred = pool.filter { $0.starred }
        var targets: [Email] = []
        var seen = Set<String>()
        for e in (Array(newest) + starred) where seen.insert(e.id).inserted { targets.append(e) }
        let acct = accountId, fld = folderId
        Task {
            for e in targets {
                guard let uid = e.uid else { continue }
                let stillNeeded = await MainActor.run {
                    self.emails.first(where: { $0.id == e.id })?.bodyLoaded == false
                }
                guard stillNeeded == true else { continue }
                guard let data = try? await session.fetchMessageData(mailbox: box, uid: uid, byteLimit: 262_144) else { continue }
                let parsed = MIME.parse(data)
                let metas = parsed.attachments.map { AttachmentMeta(filename: $0.filename, mimeType: $0.mimeType, size: $0.data.count) }
                await MainActor.run {
                    if let i = self.emails.firstIndex(where: { $0.id == e.id }) {
                        self.emails[i].body = parsed.text
                        self.emails[i].preview = String(parsed.text.replacingOccurrences(of: "\n", with: " ").prefix(140))
                        self.emails[i].bodyLoaded = true
                        self.emails[i].attachments = metas
                        self.emails[i].hasAttachment = !metas.isEmpty
                        self.emails[i].unsubscribe = parsed.listUnsubscribe
                        self.emails[i].bodyHTML = parsed.html
                    }
                }
            }
            await MainActor.run {
                MailCache.save(self.emails.filter { $0.account == acct && $0.folder == fld }, account: acct, folder: fld)
            }
        }
    }

    static func makeEmail(_ m: IMAPMessage, accountId: String, folder: String) -> Email {
        let (day, time) = dayAndTime(m.date)
        let fromKey = m.fromEmail.isEmpty ? "imap-unknown" : m.fromEmail
        var email = Email(id: "\(accountId)#\(folder)#\(m.uid)", account: accountId, from: fromKey, to: nil,
                          subject: m.subject.isEmpty ? "(no subject)" : m.subject,
                          preview: "", body: "", time: time, day: day,
                          unread: !m.seen, starred: m.flagged, hasAttachment: false,
                          labels: m.keywords.map { $0.lowercased() }, folder: folder, thread: nil, snoozeUntil: nil,
                          fromName: m.fromName, fromEmail: m.fromEmail, uid: m.uid, bodyLoaded: false)
        email.messageID = m.messageID.isEmpty ? nil : m.messageID
        email.inReplyTo = m.inReplyTo.isEmpty ? nil : m.inReplyTo
        return email
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
                let data = try await session.fetchMessageData(mailbox: box, uid: uid, byteLimit: 262_144)
                let parsed = MIME.parse(data)
                let metas = parsed.attachments.map { AttachmentMeta(filename: $0.filename, mimeType: $0.mimeType, size: $0.data.count) }
                await MainActor.run {
                    if let i = self.emails.firstIndex(where: { $0.id == id }) {
                        self.emails[i].body = parsed.text
                        self.emails[i].preview = String(parsed.text.replacingOccurrences(of: "\n", with: " ").prefix(140))
                        self.emails[i].bodyLoaded = true
                        self.emails[i].attachments = metas
                        self.emails[i].hasAttachment = !metas.isEmpty
                        self.emails[i].unsubscribe = parsed.listUnsubscribe
                        self.emails[i].bodyHTML = parsed.html
                    }
                    if let j = self.serverSearchResults?.firstIndex(where: { $0.id == id }) {
                        self.serverSearchResults?[j].body = parsed.text
                        self.serverSearchResults?[j].bodyLoaded = true
                        self.serverSearchResults?[j].attachments = metas
                    }
                    MailCache.save(self.emails.filter { $0.account == acct && $0.folder == fld },
                                   account: acct, folder: fld)
                }
            } catch { /* leave placeholder; surfaced via empty body */ }
        }
    }

    enum AttachmentOpenMode { case quickLook, defaultApp, app(URL), reveal, saveToDownloads }

    func isDownloading(_ email: Email, _ meta: AttachmentMeta) -> Bool {
        downloadingAttachments.contains("\(email.id)#\(meta.filename)")
    }

    /// Per-message cache location for an attachment (original filename preserved).
    private func attachmentCacheURL(_ email: Email, _ meta: AttachmentMeta) -> URL {
        let safeKey = "\(email.account)#\(email.uid ?? 0)".replacingOccurrences(of: "/", with: "_")
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("MMailAttachments", isDirectory: true)
            .appendingPathComponent(safeKey, isDirectory: true)
            .appendingPathComponent(meta.filename)
    }

    /// Open an attachment per `mode` (Quick Look by default). Reuses the cached
    /// file if it was already downloaded; otherwise fetches the full message.
    func openAttachment(_ email: Email, _ meta: AttachmentMeta, mode: AttachmentOpenMode = .quickLook) {
        let url = attachmentCacheURL(email, meta)
        if FileManager.default.fileExists(atPath: url.path) {
            performOpen(mode, url: url)
            return
        }
        guard isRealAccount(email.account), let uid = email.uid, let session = session(for: email.account) else { return }
        let box = mailboxName(email.account, email.folder) ?? "INBOX"
        let key = "\(email.id)#\(meta.filename)"
        guard !downloadingAttachments.contains(key) else { return }
        downloadingAttachments.insert(key)
        Task {
            do {
                let data = try await session.fetchMessageData(mailbox: box, uid: uid, byteLimit: nil)
                let parsed = MIME.parse(data)
                guard let att = parsed.attachments.first(where: { $0.filename == meta.filename }) else {
                    await MainActor.run { self.downloadingAttachments.remove(key); self.showToast("Attachment not found") }
                    return
                }
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try att.data.write(to: url)
                await MainActor.run {
                    self.downloadingAttachments.remove(key)
                    self.performOpen(mode, url: url)
                }
            } catch {
                await MainActor.run { self.downloadingAttachments.remove(key); self.showToast("Download failed: \(error.localizedDescription)") }
            }
        }
    }

    private func performOpen(_ mode: AttachmentOpenMode, url: URL) {
        switch mode {
        case .quickLook: QuickLook.shared.show(url)
        case .defaultApp: NSWorkspace.shared.open(url)
        case .app(let appURL): NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
        case .reveal: NSWorkspace.shared.activateFileViewerSelecting([url])
        case .saveToDownloads: saveToDownloads(url)
        }
    }

    private func saveToDownloads(_ source: URL) {
        let fm = FileManager.default
        let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        var dest = downloads.appendingPathComponent(source.lastPathComponent)
        if fm.fileExists(atPath: dest.path) {
            let base = source.deletingPathExtension().lastPathComponent
            let ext = source.pathExtension
            var i = 1
            repeat {
                let name = ext.isEmpty ? "\(base) \(i)" : "\(base) \(i).\(ext)"
                dest = downloads.appendingPathComponent(name); i += 1
            } while fm.fileExists(atPath: dest.path)
        }
        do {
            try fm.copyItem(at: source, to: dest)
            showToast("Saved \(dest.lastPathComponent) to Downloads")
        } catch {
            showToast("Couldn't save: \(error.localizedDescription)")
        }
    }

    /// Applications that can open a file with the given name (by type), for the
    /// right-click "Open With" menu.
    static func appsForAttachment(_ filename: String) -> [URL] {
        let probe = FileManager.default.temporaryDirectory.appendingPathComponent("mmail-probe").appendingPathExtension((filename as NSString).pathExtension)
        return NSWorkspace.shared.urlsForApplications(toOpen: probe)
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
        // Every 30s: incrementally refresh the current folder (new mail + flag
        // changes only). Every 10th tick (~5 min) do a full fetch to self-heal
        // expunges / UID-validity resets. Also run scheduled sends + snooze wakes.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.pollCount += 1
            self.refreshCurrentRealFolder(silent: true, incremental: self.pollCount % 10 != 0)
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
                                        subject: draft.subject, body: draft.body, attachments: draft.attachments,
                                        bodyHTML: draft.bodyHTML)
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
        // Only treat *editable* text as typing — a selectable (read-only) text
        // view like the reader body shouldn't swallow single-key shortcuts.
        if let tv = r as? NSTextView { return tv.isEditable }
        if let t = r as? NSText { return t.isEditable }
        return false
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
            if searchModalOpen { dismissSearch(); return true }
            if anyOverlayOpen { closeOverlays(); return true }
            if selectionActive { clearSelection(); return true }
            if searchActive { searchActive = false; searchQuery = ""; return true }
            if readerFullScreen { readerFullScreen = false; return true }
            return false
        }

        // Below: single-key. Don't intercept when typing, an overlay owns focus,
        // or the user has turned off keyboard (vim) navigation in Settings.
        if isTyping || anyOverlayOpen || onboarding || !vimNav { return false }

        // Return: open the selected message full-width when the reading pane is off.
        if event.keyCode == 36 {
            if !readingPane && !readerFullScreen && folder != "home" && selectedId != nil {
                readerFullScreen = true; return true
            }
            return false
        }

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

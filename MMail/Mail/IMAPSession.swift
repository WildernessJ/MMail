import Foundation

// A long-lived IMAP connection for one account. Keeps the channel open and
// reuses it across operations (no reconnect/login per request), serializing
// commands via actor isolation. Transparently reconnects once if the
// connection has dropped (idle timeout, etc.).
actor IMAPSession {
    private let config: MailAccountConfig
    private let password: String
    private var service: IMAPService?

    init(config: MailAccountConfig, password: String) {
        self.config = config
        self.password = password
    }

    private func connected() async throws -> IMAPService {
        if let s = service { return s }
        let s = IMAPService(config: config, password: password)
        try await s.connectAndLogin()
        service = s
        return s
    }

    private func run<T>(_ body: (IMAPService) async throws -> T) async throws -> T {
        do {
            return try await body(try await connected())
        } catch {
            // The connection may be stale — drop it and retry once on a fresh one.
            if let s = service { await s.disconnect() }
            service = nil
            let s = IMAPService(config: config, password: password)
            try await s.connectAndLogin()
            service = s
            return try await body(s)
        }
    }

    func listMailboxes() async throws -> [IMAPMailbox] {
        try await run { try await $0.listMailboxes() }
    }
    func fetchRecent(mailbox: String, limit: Int) async throws -> [IMAPMessage] {
        try await run { try await $0.fetchRecent(mailbox: mailbox, limit: limit) }
    }
    func fetchBody(mailbox: String, uid: UInt32) async throws -> String {
        try await run { try await $0.fetchBody(mailbox: mailbox, uid: uid) }
    }
    func searchText(mailbox: String, query: String, limit: Int) async throws -> [IMAPMessage] {
        try await run { try await $0.searchText(mailbox: mailbox, query: query, limit: limit) }
    }
    func searchFlagged(mailbox: String, limit: Int) async throws -> [IMAPMessage] {
        try await run { try await $0.searchFlagged(mailbox: mailbox, limit: limit) }
    }
    func store(mailbox: String, uid: UInt32, _ kind: MailFlagKind, add: Bool) async throws {
        try await run { try await $0.store(mailbox: mailbox, uid: uid, kind, add: add) }
    }
    func move(uid: UInt32, from: String, to: String) async throws {
        try await run { try await $0.move(uid: uid, from: from, to: to) }
    }
    func append(mailbox: String, rawMessage: String, seen: Bool, draft: Bool) async throws {
        try await run { try await $0.append(mailbox: mailbox, rawMessage: rawMessage, seen: seen, draft: draft) }
    }
    func close() async {
        if let s = service { await s.disconnect() }
        service = nil
    }
}

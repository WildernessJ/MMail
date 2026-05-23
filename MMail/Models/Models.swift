import SwiftUI

enum Org: String {
    case team, ext, bot
}

struct Sender: Identifiable {
    let id: String
    let name: String
    let email: String
    let colorHex: String
    let org: Org
    var color: Color { Color(hex: colorHex) }
    var initials: String {
        name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined()
    }
    var firstName: String { String(name.split(separator: " ").first ?? "") }
}

struct Account: Identifiable {
    let id: String
    let name: String
    let email: String
    let initials: String
    let gradient: [String]
    let colorHex: String
    let provider: String
    var color: Color { Color(hex: colorHex) }
    var gradientColors: [Color] { gradient.map { Color(hex: $0) } }
}

struct MailLabel: Identifiable {
    let id: String
    let name: String
    let colorHex: String
    var color: Color { Color(hex: colorHex) }
}

struct ThreadItem: Identifiable {
    let id = UUID()
    let from: String
    let time: String
    let preview: String
}

struct Email: Identifiable {
    let id: String
    var account: String
    var from: String          // sender id, or "you"
    var to: [String]?
    var subject: String
    var preview: String
    var body: String
    var time: String
    var day: String           // today | yesterday | earlier | snoozed
    var unread: Bool
    var starred: Bool
    var hasAttachment: Bool
    var labels: [String]
    var folder: String
    var thread: [ThreadItem]?
    var snoozeUntil: String?

    init(id: String, account: String, from: String, to: [String]? = nil,
         subject: String, preview: String, body: String, time: String, day: String,
         unread: Bool = false, starred: Bool = false, hasAttachment: Bool = false,
         labels: [String] = [], folder: String, thread: [ThreadItem]? = nil,
         snoozeUntil: String? = nil) {
        self.id = id; self.account = account; self.from = from; self.to = to
        self.subject = subject; self.preview = preview; self.body = body
        self.time = time; self.day = day; self.unread = unread; self.starred = starred
        self.hasAttachment = hasAttachment; self.labels = labels; self.folder = folder
        self.thread = thread; self.snoozeUntil = snoozeUntil
    }
}

struct Todo: Identifiable, Codable {
    var id: String
    var text: String
    var done: Bool
    var source: String?
}

struct JournalEntry: Identifiable, Codable {
    var id: String
    var date: String
    var text: String
}

struct ReplyTemplate: Identifiable, Codable {
    var id: String
    var name: String
    var shortcut: String
    var body: String
    var custom: Bool = false
}

struct Folder: Identifiable {
    let id: String
    let name: String
    let shortcut: String?
}

struct WeatherInfo {
    let temp: Int
    let feels: Int
    let hi: Int
    let lo: Int
    let condition: String
    let location: String
}

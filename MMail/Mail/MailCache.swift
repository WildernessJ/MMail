import Foundation

// Temporary on-disk cache of fetched messages, keyed by account + folder.
// Lives in the Caches directory (the OS may purge it; that's fine).
enum MailCache {
    private static var dir: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let d = base.appendingPathComponent("MMailCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private static func fileURL(_ account: String, _ folder: String) -> URL {
        let safe = "\(account)__\(folder)"
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return dir.appendingPathComponent(safe + ".json")
    }

    static func load(account: String, folder: String) -> [Email]? {
        guard let data = try? Data(contentsOf: fileURL(account, folder)) else { return nil }
        return try? JSONDecoder().decode([Email].self, from: data)
    }

    static func save(_ emails: [Email], account: String, folder: String) {
        guard let data = try? JSONEncoder().encode(emails) else { return }
        try? data.write(to: fileURL(account, folder), options: .atomic)
    }

    static func clear(account: String) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for f in files where f.lastPathComponent.hasPrefix("\(account)__") {
            try? fm.removeItem(at: f)
        }
    }
}

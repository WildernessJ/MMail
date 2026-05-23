import AppKit
import Quartz

// Shows a file in a Quick Look window (QLPreviewView in a small panel).
final class QuickLook: NSObject {
    static let shared = QuickLook()
    private var window: NSWindow?

    func show(_ url: URL) {
        let preview = QLPreviewView(frame: NSRect(x: 0, y: 0, width: 720, height: 560), style: .normal)
        preview?.previewItem = url as NSURL
        preview?.autostarts = true

        let win: NSWindow
        if let existing = window {
            win = existing
        } else {
            win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
                           styleMask: [.titled, .closable, .resizable],
                           backing: .buffered, defer: false)
            win.isReleasedWhenClosed = false
            win.center()
            window = win
        }
        win.title = url.lastPathComponent
        win.contentView = preview
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

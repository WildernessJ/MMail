import SwiftUI

/// A detached, standalone macOS reader window bound to a single fixed `Email.id`.
///
/// Decoupled from the main window's moving selection (INV-3): it looks its email up by the
/// fixed `emailId` from the SHARED `AppModel` (INV-2) via the pure `AppModel.email(withId:in:)`
/// seam, and NEVER reads or mutates `selectedId`/`selectedEmail`. It reuses the inline
/// `ReaderContent` for full render parity (INV-7).
///
/// On first appear it captures the email's current `folder` as its opener folder (INV-9) —
/// at fresh-open AND at relaunch-restore — which the auto-close predicate (Phase E) consumes.
/// If the id resolves to nil it renders an empty surface; the nil-lookup self-dismiss and the
/// folder-change/expunge auto-close wiring land in Phase E (T019/T022), not here.
struct DetachedReaderView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p

    let emailId: String

    /// The folder the email was in when this window's content first appeared (INV-9).
    /// Captured once; nil until the first `.onAppear`.
    @State private var openerFolder: String?

    private var email: Email? { AppModel.email(withId: emailId, in: model.emails) }

    var body: some View {
        Group {
            if let email {
                ReaderContent(email: email, account: model.accountsById[email.account], detached: true)
                    .id(email.id)
                    .onAppear {
                        // Capture the opener folder once, on the content's first appear
                        // (covers fresh-open AND relaunch-restore, INV-9).
                        if openerFolder == nil { openerFolder = email.folder }
                        // Trigger the shared body-load path for THIS id (not the selection,
                        // INV-3) so an unloaded body loads in the detached window (SC-007a).
                        model.loadBodyIfNeeded(forId: emailId)
                    }
            } else {
                // Lookup nil (e.g. a relaunch-restored window for an expunged id). Render
                // empty; self-dismiss wiring is Phase E (T022).
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(p.bg2)
    }
}

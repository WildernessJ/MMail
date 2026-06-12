import SwiftUI

/// A detached, standalone macOS reader window bound to a single fixed `Email.id`.
///
/// Decoupled from the main window's moving selection (INV-3): it looks its email up by the
/// fixed `emailId` from the SHARED `AppModel` (INV-2) via the pure `AppModel.email(withId:in:)`
/// seam, and NEVER reads or mutates `selectedId`/`selectedEmail`. It reuses the inline
/// `ReaderContent` for full render parity (INV-7).
///
/// On first appear it captures the email's current `folder` as its opener folder (INV-9) —
/// at fresh-open AND at relaunch-restore. The window auto-closes (INV-9, SC-005) when the
/// email's current folder differs from that opener folder OR the email is expunged from the
/// shared model, via the pure `AppModel.shouldCloseDetached(id:openerFolder:in:)` predicate.
///
/// Dismissal goes through the VIEW LAYER (`@Environment(\.dismiss)`), never AppModel (INV-4),
/// and is always deferred onto the next runloop turn (`Task { @MainActor }`) — calling it
/// synchronously from `.onChange` is a "modifying state during view update" hazard.
///
/// Relaunch race (SC-008): on cold launch `model.emails` loads asynchronously, so a restored
/// window may appear before emails populate and the lookup is transiently nil. A nil lookup
/// self-dismisses ONLY once `model.emailsLoaded` is true (bootstrap's cache seed has run) —
/// a nil-while-loading window waits for the email to resolve rather than killing itself.
struct DetachedReaderView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p
    /// Dismisses THIS WindowGroup window. The view layer owns window lifecycle (INV-4);
    /// AppModel never references `dismiss`/`dismissWindow`/`openWindow`.
    @Environment(\.dismiss) private var dismiss

    let emailId: String

    /// The folder the email was in when this window's content first appeared (INV-9).
    /// Captured once; nil until the first `.onAppear`.
    @State private var openerFolder: String?

    private var email: Email? { AppModel.email(withId: emailId, in: model.emails) }

    /// Narrow auto-close observation token: this email's CURRENT folder, or nil if its row is
    /// gone. Changes on BOTH an in-place folder mutation (archive/delete/move keep the row but
    /// rewrite `folder`, AppModel.swift:645-684 → folder string changes) AND row removal
    /// (external expunge, AppModel.swift:2552-2555 → nil). So a single `.onChange` on it covers
    /// the folder-change arm and the expunge arm of `shouldCloseDetached`.
    private var folderToken: String? { model.emails.first(where: { $0.id == emailId })?.folder }

    var body: some View {
        Group {
            if let email {
                ReaderContent(email: email, account: model.accountsById[email.account], detached: true)
                    .id(email.id)
                    .onAppear {
                        // Capture the opener folder once, on the content's first appear
                        // (covers fresh-open AND relaunch-restore, INV-9). A window restored
                        // for an email MOVED while the app was closed captures its CURRENT
                        // folder here, so it does NOT auto-close on launch — only on a later
                        // in-session move/expunge (SC-008 moved-while-closed scenario).
                        if openerFolder == nil { openerFolder = email.folder }
                        // Trigger the shared body-load path for THIS id (not the selection,
                        // INV-3) so an unloaded body loads in the detached window (SC-007a).
                        model.loadBodyIfNeeded(forId: emailId)
                    }
            } else {
                // Lookup nil in `model.emails`. Before considering dismissal, try to resolve
                // the email from the on-disk cache (any folder for its account) and seed it into
                // `model.emails` — `bootstrapRealAccounts` seeds ONLY the inbox synchronously, so
                // a window restored for a non-inbox email (done/sent/starred/spam/trash/label)
                // lands here even though the email IS cached (FIX 1). A successful resolve
                // mutates `model.emails` → `email` recomputes → the `if let email` arm renders.
                // Only if the cache ALSO lacks it AND the model has finished loading do we
                // dismiss (truly gone, SC-008). No placeholder (SC-005): render an empty surface.
                Color.clear
                    .onAppear { resolveOrDismiss() }
            }
        }
        // Folder-change + expunge auto-close (T019, INV-9, SC-005). Re-evaluate the close
        // predicate whenever this email's folder changes or its row is removed. Only fires
        // once the opener folder is captured (predicate needs it).
        .onChange(of: folderToken) { _, _ in
            guard let opener = openerFolder else { return }
            if AppModel.shouldCloseDetached(id: emailId, openerFolder: opener, in: model.emails) {
                deferredDismiss()
            }
        }
        // Relaunch truly-gone check (T022, SC-008): if this window appeared while the model
        // was still loading (nil lookup, no opener captured), re-check once the cache seed
        // completes. Before dismissing, try the on-disk cache resolve (FIX 1): a non-inbox
        // email is in the cache but not yet in `emails` once `emailsLoaded` flips, so resolve
        // it first. Only a still-nil lookup AFTER the cache miss means it is genuinely gone.
        .onChange(of: model.emailsLoaded) { _, _ in resolveOrDismiss() }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(p.bg2)
    }

    /// Resolve-then-dismiss for a nil `model.emails` lookup (FIX 1). First try to seed this
    /// window's email from the on-disk cache (`AppModel.resolveDetachedEmailFromCache`, which
    /// scans ALL folders for the account — so a non-inbox or moved-while-closed email that
    /// `bootstrapRealAccounts` never seeded into `emails` is still found and rendered). If it
    /// resolves, `email` recomputes non-nil next pass and we render. Only when the email is
    /// absent from BOTH `emails` and the cache, AND the model has finished its cold-launch seed
    /// (`emailsLoaded`), is it genuinely gone (expunged) → dismiss (SC-008). While the model is
    /// still loading (`!emailsLoaded`) and the cache lacks it, we WAIT rather than dismiss —
    /// the email may resolve once the seed completes. Deferred dismiss (INV-4 view layer + no
    /// synchronous dismiss inside a view-update pass).
    private func resolveOrDismiss() {
        // Already present, or just seeded from cache → render, never dismiss.
        if model.resolveDetachedEmailFromCache(emailId) { return }
        // Not in `emails` and not in the cache. Dismiss only if the model has finished loading
        // (truly gone); otherwise wait for the cold-launch seed to complete.
        guard model.emailsLoaded else { return }
        deferredDismiss()
    }

    /// Close THIS window via the view layer, on the NEXT runloop turn. `.onChange`/`.onAppear`
    /// fire during a SwiftUI update pass; calling `dismiss()` synchronously there is a
    /// "modifying state during view update" hazard (same deferral the RootView open-drain uses).
    private func deferredDismiss() {
        Task { @MainActor in dismiss() }
    }
}

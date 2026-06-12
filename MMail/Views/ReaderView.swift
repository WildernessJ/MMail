import SwiftUI
import AppKit

struct ReaderView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p

    var body: some View {
        Group {
            if let email = model.selectedEmail {
                ReaderContent(email: email, account: model.accountsById[email.account])
                    .id(email.id)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(p.bg2)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Icon(name: "mail", size: 48, weight: .light).foregroundStyle(p.fg3.opacity(0.5))
            Text("Select a message to read").font(.system(size: 13.5)).foregroundStyle(p.fg3)
            HStack(spacing: 8) {
                Kbd("J"); Kbd("K")
                Text("to navigate").font(.system(size: 11.5)).foregroundStyle(p.fg3)
            }
            .padding(.top, 8)
        }
    }
}

// MARK: - Reader content (per-email; resets state via .id)

struct ReaderContent: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p
    let email: Email
    let account: Account?
    /// When true (detached window), reader-toolbar/moreMenu actions target THIS view's own
    /// `email.id` instead of the live main-window selection (INV-10). Default false ⇒ the
    /// inline reader's call sites collapse to the original no-arg forms (byte-unchanged).
    var detached: Bool = false

    @State private var expanded = false
    @State private var contactOpen = false
    @State private var copied = false
    @State private var newLabelOpen = false
    @State private var newLabelName = ""
    @State private var htmlHeight: CGFloat = 0
    @State private var loadImages = false
    // Per-message, session-scoped "Show original" (T011, SC-006): mirrors `loadImages`.
    // Reset to false per message via the parent's `.id(email.id)` (ReaderView:12) — a
    // fresh ReaderContent per message. Feeds the dark-apply decision; never persisted.
    @State private var showOriginal = false
    @State private var snoozePickerOpen = false
    @State private var snoozeDate = Date()

    private var sender: Sender? { email.resolvedSender }
    private var thread: [ThreadItem] { email.thread ?? model.relatedThread(for: email) }
    private let stackMax = 4
    private var stackVisible: [ThreadItem] { expanded ? thread : Array(thread.prefix(stackMax)) }
    private var hiddenInStack: Int { max(0, thread.count - stackMax) }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().overlay(p.border)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    primaryCard
                    if !thread.isEmpty {
                        threadLabel
                        deck
                        if !expanded && hiddenInStack > 0 { stackMoreButton }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 40).padding(.top, 28).padding(.bottom, 96)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .alert("New label", isPresented: $newLabelOpen) {
            TextField("Label name", text: $newLabelName)
            Button("Cancel", role: .cancel) { newLabelName = "" }
            Button("Create") {
                if let id = model.addLabel(newLabelName) { model.applyLabel(email, id, add: true) }
                newLabelName = ""
            }
        } message: {
            Text("Create a label and apply it to this message.")
        }
        .sheet(isPresented: $snoozePickerOpen) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Snooze until").font(.system(size: 16, weight: .bold)).foregroundStyle(p.fg1)
                DatePicker("", selection: $snoozeDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical).labelsHidden()
                HStack {
                    Spacer()
                    Button("Cancel") { snoozePickerOpen = false }.buttonStyle(.plain).foregroundStyle(p.fg2)
                    Button {
                        let df = DateFormatter(); df.dateFormat = "MMM d, h:mm a"
                        model.snooze(email.id, until: snoozeDate, label: "until \(df.string(from: snoozeDate))")
                        snoozePickerOpen = false
                    } label: {
                        Text("Snooze").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(p.brandBlue).clipShape(Capsule())
                    }.buttonStyle(.plain)
                }
            }
            .padding(20).frame(width: 360).background(p.bg1)
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            if !model.readingPane {
                Button { model.closeFullReader() } label: {
                    HStack(spacing: 4) {
                        Icon(name: "chevronLeft", size: 13)
                        Text("Back").font(.system(size: 12.5, weight: .medium))
                    }
                    .foregroundStyle(p.fg2).padding(.horizontal, 8).frame(height: 30)
                    .background(p.bg3).clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Back to list (esc)")
            }
            if email.folder == "drafts" {
                Button { model.editDraft(email) } label: {
                    HStack(spacing: 6) {
                        Icon(name: "pencil", size: 15)
                        Text("Edit draft").font(.system(size: 12.5, weight: .semibold))
                    }
                    .foregroundStyle(.white).padding(.horizontal, 12).frame(height: 30)
                    .background(p.brandBlue).clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                PrimaryToolbarButton(icon: "check", label: "Done", kbd: "H") { detached ? model.markDone(email.id) : model.markDone() }
                PrimaryToolbarButton(icon: "replyAll", label: "Reply all", kbd: "A") { detached ? model.replyAll(email.id) : model.replyAll() }
            }
            Button { model.toggleStar(email.id) } label: {
                Icon(name: email.starred ? "star.fill" : "star", size: 15)
                    .foregroundStyle(email.starred ? Color(hex: "F4A52A") : p.fg2)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .help(email.starred ? "Unstar (S)" : "Star (S)")
            labelMenu
            Spacer()
            moreMenu
        }
        .padding(.horizontal, 24).padding(.vertical, 10)
    }

    private var labelMenu: some View {
        Menu {
            if model.labels.isEmpty {
                Text("No labels yet")
            } else {
                ForEach(model.labels) { l in
                    let on = email.labels.contains(l.id)
                    Button { model.applyLabel(email, l.id, add: !on) } label: {
                        Label(l.name, systemImage: on ? "checkmark" : "circle")
                    }
                }
            }
            Divider()
            Button { newLabelOpen = true } label: { Label("New label…", systemImage: "plus") }
        } label: {
            Icon(name: "tag", size: 15).foregroundStyle(p.fg2).frame(width: 30, height: 30)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Label")
    }

    private var moreMenu: some View {
        Menu {
            Button { detached ? model.reply(email.id) : model.reply() } label: { Label("Reply", systemImage: "arrowshape.turn.up.left") }
            Button { detached ? model.forward(email.id) : model.forward() } label: { Label("Forward", systemImage: "arrowshape.turn.up.right") }
            Divider()
            Button { detached ? model.archive(email.id) : model.archive() } label: { Label("Archive", systemImage: "archivebox") }
            Menu {
                ForEach(model.snoozePresets()) { preset in
                    Button(preset.label) { model.snooze(email.id, until: preset.date, label: "· \(preset.label)") }
                }
                Divider()
                Button("Pick date & time…") {
                    snoozeDate = Calendar.current.date(byAdding: .day, value: 1, to: Date())
                        .flatMap { Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: $0) } ?? Date()
                    snoozePickerOpen = true
                }
            } label: { Label("Snooze", systemImage: "clock") }
            Button { detached ? model.markSpam(email.id) : model.markSpam() } label: { Label("Mark as Spam", systemImage: "exclamationmark.triangle") }
            let folders = model.folderNames(for: email.account)
            if !folders.isEmpty {
                Menu {
                    ForEach(folders, id: \.self) { name in
                        Button(name) { model.moveToMailbox(email.id, mailbox: name) }
                    }
                } label: { Label("Move to…", systemImage: "tray.and.arrow.up") }
            }
            Divider()
            Button { model.printMessage(email) } label: { Label("Print…", systemImage: "printer") }
            Button { model.exportPDF(email) } label: { Label("Export as PDF…", systemImage: "doc") }
            if let addr = sender?.email, !addr.isEmpty {
                Button { model.toggleVIP(addr) } label: {
                    Label(model.isVIP(addr) ? "Remove VIP" : "Mark as VIP", systemImage: "crown")
                }
                Button(role: .destructive) { model.blockSender(addr) } label: {
                    Label("Block \(sender?.firstName ?? addr)", systemImage: "hand.raised")
                }
            }
            Divider()
            Button(role: .destructive) { detached ? model.delete(email.id) : model.delete() } label: { Label("Delete", systemImage: "trash") }
        } label: {
            HStack(spacing: 6) {
                Icon(name: "more", size: 16)
                Text("More").font(.system(size: 12.5, weight: .medium))
                Icon(name: "chevronDown", size: 12)
            }
            .foregroundStyle(p.fg2)
            .padding(.horizontal, 10).frame(height: 30)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: Primary card

    private var primaryCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(email.subject)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(p.fg1)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 18)

            metaRow.padding(.bottom, 22)
            Divider().overlay(p.border)

            if email.unsubscribe != nil {
                HStack(spacing: 8) {
                    Icon(name: "mail", size: 12).foregroundStyle(p.fg3)
                    Text("You're subscribed to this mailing list.").font(.system(size: 12)).foregroundStyle(p.fg3)
                    Spacer()
                    Button { model.unsubscribe(email) } label: {
                        Text("Unsubscribe").font(.system(size: 12, weight: .semibold)).foregroundStyle(p.brandBlue)
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(p.bg2)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(p.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.top, 16)
            }

            if let ev = email.calendarEvent {
                inviteCard(ev)
            }

            if email.body.isEmpty && !email.bodyLoaded {
                if model.bodyLoadFailed.contains(email.id) {
                    HStack(spacing: 10) {
                        Icon(name: "alert", size: 14).foregroundStyle(p.danger)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Couldn't load this message")
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(p.fg2)
                            Text("The mail server didn't respond. The connection has been reset.")
                                .font(.system(size: 12)).foregroundStyle(p.fg3)
                        }
                        Spacer()
                        Button { detached ? model.retryBodyLoad(forId: email.id) : model.retryBodyLoad() } label: {
                            Text("Retry").font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(p.brandBlue).clipShape(Capsule())
                        }.buttonStyle(.plain)
                    }
                    .padding(.top, 24)
                } else {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading message…").font(.system(size: 13.5)).foregroundStyle(p.fg3)
                    }
                    .padding(.top, 24)
                }
            } else if let html = email.bodyHTML, !html.isEmpty {
                let trusted = model.isImageTrusted(email.fromEmail)
                let showImages = loadImages || trusted
                if !showImages {
                    let trackers = Privacy.trackerCount(in: html)
                    HStack(spacing: 8) {
                        Icon(name: "shield", size: 12).foregroundStyle(p.brandBlue)
                        Text(trackers > 0
                             ? "Blocked \(trackers) tracker\(trackers == 1 ? "" : "s")"
                             : "Remote images are blocked for privacy.")
                            .font(.system(size: 12)).foregroundStyle(p.fg3)
                        Spacer()
                        Button { loadImages = true } label: {
                            Text("Load images").font(.system(size: 12, weight: .semibold)).foregroundStyle(p.brandBlue)
                        }.buttonStyle(.plain)
                        if let addr = sender?.email, !addr.isEmpty {
                            Button { model.trustImages(addr); loadImages = true } label: {
                                Text("Always").font(.system(size: 12, weight: .semibold)).foregroundStyle(p.fg2)
                            }.buttonStyle(.plain).help("Always load images from \(addr)")
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(p.bg2)
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(p.border, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(.top, 16)
                }
                // Read-only privacy posture for the realized image-load path. Keys
                // off the SAME `showImages` local and `model.imageProxyConfig != nil`
                // the render path uses below, so it can never disagree with what
                // `HTMLMessageView` actually rendered. Display-only — no fetch, no URL.
                let imageState = ReaderImageLoadState.classify(
                    hasRemoteImages: ReaderImageLoadState.hasRemoteImages(in: html),
                    showImages: showImages,
                    proxyActive: model.imageProxyConfig != nil)
                imageLoadIndicator(imageState)
                // Render-time-only CID→data: rewrite (T008). Tracker counting and
                // remote-image detection above run on the RAW `cid:` html (a cid:/data:
                // image is not a remote tracker); only the rewritten string — where any
                // referenced inline part becomes a self-contained `data:` URI — is fed to
                // the WebView, so inline images render even with remote blocking on.
                let rendered = ReaderHTML.inlineCIDImages(inHTML: html, parts: model.inlineParts(for: email.id))
                // Per-message "Show original" control (T012, SC-006). Shared with the
                // plain-text branch via `showOriginalStrip()` (one definition, two call
                // sites). Self-gates on `model.dark`, so it's a no-op in light mode.
                showOriginalStrip()
                HTMLMessageView(html: rendered, blockRemote: !showImages,
                                proxyConfig: model.imageProxyConfig,
                                applyDark: ReaderHTML.shouldApplyDark(dark: model.dark, showOriginal: showOriginal),
                                height: $htmlHeight)
                    .frame(height: max(htmlHeight, 80))
                    .padding(.top, 16)
            } else {
                // Plain-text-only body (NOT a WebView, so DarkReader can't reach it —
                // T013, SC-008). In dark mode with "Show original" off, render light text
                // on a dark surface consistent with the HTML dark look; otherwise keep the
                // shipped dark-on-white surface from `reader-render-fidelity`. Both colors
                // reuse the single sources of truth (`bodyTextColor` = the `#1A1A1A` the
                // HTML dark path uses as its background; `darkSurfaceTextColor` = the
                // `#e8e8e8` the HTML path emits as `darkSchemeTextColor`) — no scattered
                // literals. Surrounding reader chrome stays themed; the HTML branch is
                // untouched.
                let plainDark = ReaderHTML.shouldApplyDark(dark: model.dark, showOriginal: showOriginal)
                // Same per-message "Show original" control as the HTML branch (T012,
                // SC-008) so a darkened plain-text message has a revert path. Self-gated
                // on `model.dark`; placed above the body to mirror the HTML affordance.
                showOriginalStrip()
                Text(email.body)
                    .font(.system(size: 15))
                    .foregroundStyle(plainDark ? ReaderHTML.darkSurfaceTextColor : ReaderHTML.bodyTextColor)
                    .lineSpacing(5)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(plainDark ? ReaderHTML.darkSurfaceBackgroundColor : Color.white)
                    .padding(.top, 16)
            }

            if !email.attachments.isEmpty {
                attachmentsSection
            }

            replyStrip.padding(.top, 24)
        }
        .padding(EdgeInsets(top: 32, leading: 40, bottom: 28, trailing: 40))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(p.bg1)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(p.border, lineWidth: 1))
        .shadow(color: .black.opacity(p.isDark ? 0.4 : 0.08), radius: 12, y: 6)
        .zIndex(10)
    }

    /// Per-message "Show original" control (T012, SC-006/SC-008). ONE definition shared
    /// by the HTML and plain-text body branches so the affordance can't diverge. Self-gates
    /// on `model.dark` — in light mode the dark-apply predicate is already false, so the
    /// control would be a visual no-op and is omitted to avoid chrome clutter. Mirrors the
    /// privacy-strip affordance (the "Load images" button). Toggles `showOriginal`, which
    /// both branches feed into `shouldApplyDark(...)`.
    @ViewBuilder
    private func showOriginalStrip() -> some View {
        if model.dark {
            HStack(spacing: 8) {
                Icon(name: "sun", size: 12).foregroundStyle(p.brandBlue)
                Text(showOriginal ? "Showing the original (light) message."
                                  : "This message is rendered in dark mode.")
                    .font(.system(size: 12)).foregroundStyle(p.fg3)
                Spacer()
                Button { showOriginal.toggle() } label: {
                    Text(showOriginal ? "Show dark" : "Show original")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(p.brandBlue)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(p.bg2)
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(p.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.top, 16)
        }
    }

    /// Read-only per-message indicator for the realized image-load path. Renders
    /// nothing for `.blocked` (the block banner already conveys it) and
    /// `.noRemoteImages` (nothing to report — never claims proxied/direct). The
    /// `.loadedDirect` warning presentation is deliberately distinct from `.proxied`.
    /// MUST NOT render any asset URL, the `s=` HMAC param, or the signing secret —
    /// the proxy host (already user-configured, non-sensitive) is the most it names.
    @ViewBuilder
    private func imageLoadIndicator(_ state: ReaderImageLoadState) -> some View {
        switch state {
        case .proxied:
            HStack(spacing: 8) {
                Icon(name: "shield", size: 12).foregroundStyle(p.brandBlue)
                Text(proxiedLabel)
                    .font(.system(size: 12)).foregroundStyle(p.fg3)
                Spacer()
            }
            .padding(.top, 16)
        case .loadedDirect:
            HStack(spacing: 8) {
                Icon(name: "alert", size: 12).foregroundStyle(p.warning)
                Text("Images loaded directly from sender")
                    .font(.system(size: 12)).foregroundStyle(p.warning)
                Spacer()
            }
            .padding(.top, 16)
        case .blocked, .noRemoteImages:
            EmptyView()
        }
    }

    /// "Images loaded via privacy proxy", naming the proxy host when known. Reads
    /// only the host (non-sensitive, user-configured) — never the secret or `s=`.
    private var proxiedLabel: String {
        if let host = model.imageProxyConfig?.baseURL.host, !host.isEmpty {
            return "Images loaded via privacy proxy (\(host))"
        }
        return "Images loaded via privacy proxy"
    }

    private func inviteCard(_ ev: CalendarEvent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Icon(name: "clock", size: 12).foregroundStyle(p.brandBlue)
                Text("CALENDAR INVITE").font(.system(size: 10.5, weight: .bold)).tracking(0.6).foregroundStyle(p.fg3)
            }
            Text(ev.summary).font(.system(size: 15, weight: .semibold)).foregroundStyle(p.fg1)
            if let start = ev.start {
                Text(eventWhen(start, ev.end)).font(.system(size: 12.5)).foregroundStyle(p.fg2)
            }
            if let loc = ev.location {
                HStack(spacing: 6) { Icon(name: "home", size: 11).foregroundStyle(p.fg3); Text(loc).font(.system(size: 12.5)).foregroundStyle(p.fg3) }
            }
            Button { model.addToCalendar(ev) } label: {
                HStack(spacing: 6) {
                    Icon(name: "check", size: 12); Text("Add to Calendar").font(.system(size: 12.5, weight: .semibold))
                }
                .foregroundStyle(.white).padding(.horizontal, 12).frame(height: 28)
                .background(p.brandBlue).clipShape(Capsule())
            }
            .buttonStyle(.plain).padding(.top, 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(p.bg2)
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(p.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.top, 16)
    }

    private func eventWhen(_ start: Date, _ end: Date?) -> String {
        let df = DateFormatter(); df.dateFormat = "EEE, MMM d · h:mm a"
        var s = df.string(from: start)
        if let end {
            let ef = DateFormatter(); ef.dateFormat = "h:mm a"
            s += " – \(ef.string(from: end))"
        }
        return s
    }

    private var metaRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Avatar(sender: sender, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Button { contactOpen.toggle() } label: {
                    HStack(spacing: 5) {
                        Text(sender?.name ?? (email.to?.first ?? "You"))
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(p.fg1)
                        Icon(name: "chevronDown", size: 12).foregroundStyle(p.fg3)
                            .rotationEffect(.degrees(contactOpen ? 180 : 0))
                    }
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(contactOpen ? p.bg3 : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $contactOpen, arrowEdge: .bottom) { contactCard }

                Text(toLine).font(.system(size: 12)).foregroundStyle(p.fg3).lineLimit(1)
            }
            Spacer(minLength: 12)
            Text(email.day == "today" ? "Today, \(email.time)" : email.time)
                .font(.system(size: 12)).monospacedDigit().foregroundStyle(p.fg3)
        }
    }

    private var contactCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Avatar(sender: sender, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(sender?.name ?? "You").font(.system(size: 14, weight: .semibold)).foregroundStyle(p.fg1).lineLimit(1)
                    if let s = sender, s.org == .ext {
                        Text(s.org.rawValue).font(.system(size: 12)).foregroundStyle(p.fg3).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.bottom, 12)

            if let s = sender, !s.email.isEmpty {
                HStack(spacing: 8) {
                    Icon(name: "mail", size: 13).foregroundStyle(p.fg3)
                    Text(s.email).font(.system(size: 12.5, design: .monospaced)).foregroundStyle(p.fg1).lineLimit(1)
                    Spacer(minLength: 6)
                    Button { copyEmail(s.email) } label: {
                        HStack(spacing: 4) {
                            Icon(name: copied ? "check" : "copy", size: 12)
                            Text(copied ? "Copied" : "Copy").font(.system(size: 11.5, weight: .semibold))
                        }
                        .foregroundStyle(copied ? p.success : p.fg2)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(copied ? p.success100 : p.bg1)
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(copied ? p.success : p.border, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(p.border, lineWidth: 1))
            } else {
                Text("No email address on file")
                    .font(.system(size: 12)).foregroundStyle(p.fg3)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(p.border, lineWidth: 1))
            }

            HStack(spacing: 6) {
                contactAct("reply", "Reply") { contactOpen = false; detached ? model.reply(email.id) : model.reply() }
                contactAct("replyAll", "Reply all") { contactOpen = false; detached ? model.replyAll(email.id) : model.replyAll() }
            }
            .padding(.top, 10)
        }
        .padding(14)
        .frame(width: 300)
        .background(p.bg1)
    }

    private func contactAct(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Icon(name: icon, size: 13).foregroundStyle(p.fg3)
                Text(label).font(.system(size: 12)).foregroundStyle(p.fg1)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 7)
            .background(p.bg2)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(email.attachments.count) ATTACHMENT\(email.attachments.count == 1 ? "" : "S")")
                .font(.system(size: 11, weight: .bold)).tracking(0.6).foregroundStyle(p.fg4)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(email.attachments, id: \.self) { att in
                    attachmentChip(att)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 24)
    }

    private func attachmentChip(_ att: AttachmentMeta) -> some View {
        let downloading = model.isDownloading(email, att)
        return Button { model.openAttachment(email, att, mode: .quickLook) } label: {
            HStack(spacing: 8) {
                Icon(name: "attach", size: 13).foregroundStyle(p.fg3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(att.filename).font(.system(size: 12.5, weight: .medium)).foregroundStyle(p.fg1).lineLimit(1)
                    HStack(spacing: 6) {
                        Text(att.mimeType).font(.system(size: 10.5)).foregroundStyle(p.fg3).lineLimit(1)
                        if att.size > 0 {
                            Text("·").font(.system(size: 10.5)).foregroundStyle(p.fg4)
                            Text(ByteCountFormatter.string(fromByteCount: Int64(att.size), countStyle: .file))
                                .font(.system(size: 10.5)).foregroundStyle(p.fg3)
                        }
                    }
                }
                Spacer(minLength: 8)
                if downloading {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                } else {
                    Icon(name: "arrowRight", size: 12).foregroundStyle(p.fg3)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: 360, alignment: .leading)
            .background(p.bg2)
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(p.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Quick Look \(att.filename)")
        .contextMenu {
            Button("Quick Look") { model.openAttachment(email, att, mode: .quickLook) }
            Button("Open") { model.openAttachment(email, att, mode: .defaultApp) }
            let apps = AppModel.appsForAttachment(att.filename)
            if !apps.isEmpty {
                Menu("Open With") {
                    ForEach(apps, id: \.self) { app in
                        Button(FileManager.default.displayName(atPath: app.path)) {
                            model.openAttachment(email, att, mode: .app(app))
                        }
                    }
                }
            }
            Divider()
            Button("Save to Downloads") { model.openAttachment(email, att, mode: .saveToDownloads) }
            Button("Reveal in Finder") { model.openAttachment(email, att, mode: .reveal) }
        }
    }

    private var replyStrip: some View {
        Button { detached ? model.reply(email.id) : model.reply() } label: {
            HStack(spacing: 12) {
                Icon(name: "reply", size: 16).foregroundStyle(p.fg3)
                Text("Reply to \(sender?.firstName ?? "sender")…").font(.system(size: 13)).foregroundStyle(p.fg3)
                Spacer()
                Kbd("R")
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(p.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Thread stack

    private var threadLabel: some View {
        HStack {
            Text(expanded
                 ? "Thread · \(thread.count) earlier message\(thread.count == 1 ? "" : "s")"
                 : "\(thread.count) earlier in this thread")
                .font(.system(size: 11, weight: .bold)).tracking(0.6)
                .foregroundStyle(p.fg4)
            Spacer()
            Button { withAnimation(.easeOut(duration: 0.2)) { expanded.toggle() } } label: {
                HStack(spacing: 4) {
                    Text(expanded ? "Collapse" : "Fan out").font(.system(size: 11, weight: .semibold))
                    Icon(name: expanded ? "check" : "forward", size: 12)
                }
                .foregroundStyle(p.brandBlue)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8).padding(.top, 24).padding(.bottom, 10)
    }

    @ViewBuilder
    private var deck: some View {
        if expanded {
            VStack(spacing: 12) {
                ForEach(Array(stackVisible.enumerated()), id: \.offset) { _, t in
                    peekCard(t, collapsed: false)
                }
            }
        } else {
            ZStack(alignment: .top) {
                ForEach(Array(stackVisible.enumerated()), id: \.offset) { i, t in
                    peekCard(t, collapsed: true)
                        .offset(y: CGFloat(i) * 36)
                        .padding(.horizontal, CGFloat(i) * 8)
                        .zIndex(Double(stackVisible.count - i))
                }
            }
            .frame(height: 60 + CGFloat(max(0, stackVisible.count - 1)) * 36, alignment: .top)
        }
    }

    private func peekCard(_ t: ThreadItem, collapsed: Bool) -> some View {
        let isYou = t.from == "you"
        let s = isYou ? nil : SampleData.senders[t.from]
        return HStack(spacing: 12) {
            if isYou {
                GradientTile(colors: [Color(hex: "2D3DEC"), Color(hex: "7A5AE0")], text: "Y", size: 28, cornerRadius: 14, fontSize: 11)
            } else {
                Avatar(sender: s, size: 28)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(isYou ? "You" : (s?.name ?? t.from)).font(.system(size: 13, weight: .semibold)).foregroundStyle(p.fg1).lineLimit(1)
                Text(t.preview).font(.system(size: 12.5)).foregroundStyle(p.fg3).lineLimit(collapsed ? 1 : nil)
            }
            Spacer(minLength: 8)
            Text(t.time).font(.system(size: 11)).monospacedDigit().foregroundStyle(p.fg4)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: collapsed ? 60 : nil)
        .background(p.bg1)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(p.border, lineWidth: 1))
        .shadow(color: .black.opacity(p.isDark ? 0.3 : 0.06), radius: collapsed ? 10 : 6, y: 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if collapsed {
                withAnimation(.easeOut(duration: 0.2)) { expanded = true }
            } else if let id = t.emailId {
                // Inline reader: navigate the main selection to the tapped message.
                // Detached window: opening a thread card here would mutate the main
                // selection + folder (INV-3 violation), so instead open that message in
                // its OWN detached window — this window stays bound to its one email
                // (INV-3/INV-1).
                detached ? model.requestDetachedWindow(id) : model.openThreadMessage(id)
            }
        }
    }

    private var stackMoreButton: some View {
        Button { withAnimation(.easeOut(duration: 0.2)) { expanded = true } } label: {
            Text("+ \(hiddenInStack) more message\(hiddenInStack == 1 ? "" : "s") in thread")
                .font(.system(size: 12)).foregroundStyle(p.fg3)
                .frame(maxWidth: .infinity).padding(.vertical, 10)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(p.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        }
        .buttonStyle(.plain)
        .padding(.top, 12)
    }

    // MARK: Helpers

    private var toLine: String {
        AppModel.recipientLine(for: email, account: account)
    }

    private func copyEmail(_ addr: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(addr, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
    }
}

// MARK: - Primary toolbar button (filled, hover → blue)

private struct PrimaryToolbarButton: View {
    @Environment(\.palette) private var p
    let icon: String
    let label: String
    let kbd: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Icon(name: icon, size: 15)
                Text(label).font(.system(size: 12.5, weight: .semibold))
                Kbd(kbd, onAccent: hover)
            }
            .foregroundStyle(hover ? Color.white : p.fg1)
            .padding(.horizontal, 12).frame(height: 30)
            .background(hover ? p.brandBlue : p.bg3)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

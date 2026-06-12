import SwiftUI

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack {
            p.bg2.ignoresSafeArea()

            if model.onboarding {
                OnboardingView()
            } else {
                content
                overlays
            }

            if model.manualSetupOpen {
                ManualAccountSetupView()
            }
        }
        .toolbar { toolbarContent }
        .onAppear { model.installKeyMonitor(); model.startPolling(); model.bootstrapRealAccounts() }
        .onChange(of: model.searchFocusRequested) { _, req in
            if req {
                searchFocused = true
                model.searchFocusRequested = false
            }
        }
        .onChange(of: searchFocused) { _, focused in
            if focused { model.searchActive = true }
        }
        .onChange(of: model.currentAccount) { _, id in
            model.didSelectAccount(id)
        }
        .animation(.easeOut(duration: 0.2), value: model.sidebarVisible)
        .animation(.easeOut(duration: 0.2), value: model.readingPane)
        .animation(.easeOut(duration: 0.2), value: model.railSize)
        .animation(.easeOut(duration: 0.2), value: model.sidebarLabelsVisible)
    }

    // MARK: - Body content

    private var content: some View {
        HStack(spacing: 0) {
            AccountRailView()
            if model.sidebarVisible {
                SidebarView()
                    .transition(.move(edge: .leading).combined(with: .opacity))
                // Sidebar↔list drag handle: only between the folder sidebar and the
                // mail list, i.e. when the sidebar is shown AND we're not in the
                // home/outbox branches (which don't show a mail list).
                if model.folder != "home" && model.folder != "outbox" {
                    SidebarDragHandle()
                }
            }
            if model.folder == "home" {
                HomeView()
            } else if model.folder == "outbox" {
                OutboxView()
            } else if model.readingPane {
                EmailListView()
                ListDragHandle()
                ReaderView()
            } else if model.readerFullScreen {
                ReaderView()
            } else {
                EmailListView()
            }
        }
    }

    // MARK: - Overlays

    @ViewBuilder
    private var overlays: some View {
        if let toast = model.toast {
            ToastView(toast: toast)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 24)
        }

        if let draft = model.compose {
            ComposeView(draft: draft)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }

        if model.palette {
            CommandPaletteView()
        }
        if model.help {
            HelpSheetView()
        }
        if model.settings {
            SettingsView()
        }
        if model.addingAccount {
            AddAccountView()
        }
        if model.journalArchiveOpen {
            JournalArchiveView()
        }
        if model.advancedSearchOpen {
            AdvancedSearchView()
        }
        if model.peopleOpen {
            PeopleView()
        }
        if model.searchModalOpen {
            SearchResultsView()
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if !model.onboarding {
            ToolbarItem(placement: .principal) {
                searchField
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { model.setSidebar(!model.sidebarVisible) } label: { Icon(name: "sidebar", size: 15) }
                    .help("Toggle sidebar (⌘⇧S)")
                Button { model.setReadingPane(!model.readingPane) } label: { Icon(name: "panel", size: 15) }
                    .help("Toggle reading pane (⌘⇧R)")
                Button { model.palette = true } label: { Icon(name: "command", size: 15) }
                    .help("Command palette (⌘K)")
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Icon(name: "search", size: 13)
                .foregroundStyle(searchFocused ? p.fg1 : p.fg3)
            TextField("Search mail — sender, subject, body…", text: $model.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($searchFocused)
                .foregroundStyle(p.fg1)
                .onSubmit { model.submitSearch() }
                .onChange(of: model.searchQuery) { _, q in
                    if q.isEmpty { model.serverSearchResults = nil; model.searching = false }
                }
            if !model.searchActive {
                Kbd("/")
            }
            Button { model.openAdvancedSearch() } label: {
                Icon(name: "sliders", size: 13).foregroundStyle(model.serverSearchResults != nil ? p.brandBlue : p.fg3)
            }
            .buttonStyle(.plain)
            .help("Advanced search")
        }
        .padding(.horizontal, 12)
        .frame(width: 420, height: 26)
        .contentShape(Rectangle())
        .onTapGesture {
            model.searchActive = true
            searchFocused = true
        }
    }
}

/// Thin draggable divider between the folder sidebar and the mail list (sidebar-visible,
/// non-home/outbox views only). Resizes `model.sidebarWidth` live during the drag and
/// persists once on release. Mirrors `ListDragHandle` exactly, on `sidebarWidth` /
/// `clampSidebarWidth` / `setSidebarWidth`.
private struct SidebarDragHandle: View {
    @EnvironmentObject var model: AppModel
    @State private var dragStart: CGFloat?
    @State private var pushed = false
    @State private var dragging = false

    var body: some View {
        Rectangle()
            .fill(.clear)
            .contentShape(Rectangle())
            .frame(width: 6)
            .frame(maxHeight: .infinity)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        dragging = true
                        if dragStart == nil { dragStart = model.sidebarWidth }
                        guard let ds = dragStart else { return }
                        model.sidebarWidth = clampSidebarWidth(ds + v.translation.width)
                    }
                    .onEnded { _ in
                        if dragStart != nil { model.setSidebarWidth(model.sidebarWidth) }
                        dragStart = nil
                        dragging = false
                        // Reset the cursor on release: a drag that ends with the pointer
                        // off the handle gets no onHover(false) (it was suppressed mid-drag),
                        // so pop here. If still over the handle, the next onHover(true) re-pushes.
                        if pushed { NSCursor.pop(); pushed = false }
                    }
            )
            .onHover { inside in
                if inside && !pushed {
                    NSCursor.resizeLeftRight.push()
                    pushed = true
                } else if !inside && pushed && !dragging {
                    // Don't pop mid-drag: SwiftUI can fire hover-out as the pointer
                    // drifts off the 6pt handle while dragging — keep the resize cursor.
                    NSCursor.pop()
                    pushed = false
                }
            }
            .onDisappear {
                // Toggling the sidebar off while hovering removes this view with no
                // onHover(false), so pop here to avoid leaking the resize cursor.
                if pushed {
                    NSCursor.pop()
                    pushed = false
                }
            }
    }
}

/// Thin draggable divider between the mail list and the reader (reading-pane mode only).
/// Resizes `model.listWidth` live during the drag and persists once on release.
private struct ListDragHandle: View {
    @EnvironmentObject var model: AppModel
    @State private var dragStart: CGFloat?
    @State private var pushed = false
    @State private var dragging = false

    var body: some View {
        Rectangle()
            .fill(.clear)
            .contentShape(Rectangle())
            .frame(width: 6)
            .frame(maxHeight: .infinity)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        dragging = true
                        if dragStart == nil { dragStart = model.listWidth }
                        guard let ds = dragStart else { return }
                        model.listWidth = clampListWidth(ds + v.translation.width)
                    }
                    .onEnded { _ in
                        if dragStart != nil { model.setListWidth(model.listWidth) }
                        dragStart = nil
                        dragging = false
                        // Reset the cursor on release: a drag that ends with the pointer
                        // off the handle gets no onHover(false) (it was suppressed mid-drag),
                        // so pop here. If still over the handle, the next onHover(true) re-pushes.
                        if pushed { NSCursor.pop(); pushed = false }
                    }
            )
            .onHover { inside in
                if inside && !pushed {
                    NSCursor.resizeLeftRight.push()
                    pushed = true
                } else if !inside && pushed && !dragging {
                    // Don't pop mid-drag: SwiftUI can fire hover-out as the pointer
                    // drifts off the 6pt handle while dragging — keep the resize cursor.
                    NSCursor.pop()
                    pushed = false
                }
            }
            .onDisappear {
                if pushed {
                    NSCursor.pop()
                    pushed = false
                }
            }
    }
}

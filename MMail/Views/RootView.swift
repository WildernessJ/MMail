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
    }

    // MARK: - Body content

    private var content: some View {
        HStack(spacing: 0) {
            AccountRailView()
            if model.sidebarVisible {
                SidebarView()
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            if model.folder == "home" {
                HomeView()
            } else {
                EmailListView()
                if model.readingPane {
                    ReaderView()
                }
            }
        }
    }

    // MARK: - Overlays

    @ViewBuilder
    private var overlays: some View {
        // Floating focus counter (bottom center, on hover handled by always-on subtle here)
        if model.folder != "home" {
            FocusCounterView(pos: model.position, total: model.total)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 16)
                .allowsHitTesting(false)
        }

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

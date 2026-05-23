import SwiftUI

struct SearchResultsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p

    private var results: [Email] { model.serverSearchResults ?? [] }

    var body: some View {
        ZStack(alignment: .top) {
            OverlayBackdrop { model.dismissSearch() }
            sheet.padding(.top, 88)
        }
    }

    private var sheet: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .frame(width: 640)
        .frame(maxHeight: 620)
        .background(p.bg1)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(p.borderStrong, lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 48, y: 24)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Icon(name: "search", size: 16).foregroundStyle(p.fg2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Search").font(.system(size: 18, weight: .bold)).foregroundStyle(p.fg1)
                Text(subtitle).font(.system(size: 12.5)).foregroundStyle(p.fg3).lineLimit(1)
            }
            Spacer()
            Button { model.advancedSearchOpen = true; model.searchModalOpen = false } label: {
                HStack(spacing: 5) {
                    Icon(name: "sliders", size: 12)
                    Text("Filters").font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(p.fg2).padding(.horizontal, 10).frame(height: 28)
                .overlay(Capsule().stroke(p.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            Button { model.dismissSearch() } label: { Icon(name: "x", size: 16).foregroundStyle(p.fg2) }
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 24).padding(.vertical, 18)
        .overlay(Rectangle().fill(p.border).frame(height: 1), alignment: .bottom)
    }

    private var subtitle: String {
        if model.searching { return "Searching for \"\(model.searchQuery)\"…" }
        let n = results.count
        return "\(n) result\(n == 1 ? "" : "s") for \"\(model.searchQuery)\""
    }

    @ViewBuilder
    private var content: some View {
        if model.searching && results.isEmpty {
            VStack(spacing: 12) {
                ProgressView().controlSize(.large)
                Text("Searching all mail…").font(.system(size: 13.5)).foregroundStyle(p.fg3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).padding(40)
        } else if results.isEmpty {
            VStack(spacing: 8) {
                Icon(name: "search", size: 32, weight: .light).foregroundStyle(p.fg3.opacity(0.6))
                Text("No matches").font(.system(size: 15, weight: .semibold)).foregroundStyle(p.fg2)
                Text("Nothing matched \"\(model.searchQuery)\". Try different words or use Filters.")
                    .font(.system(size: 12.5)).foregroundStyle(p.fg3)
                    .multilineTextAlignment(.center).frame(maxWidth: 360)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).padding(40)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(results) { email in
                        row(email)
                        Rectangle().fill(p.border).frame(height: 1)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
            }
        }
    }

    private func row(_ email: Email) -> some View {
        let sender = email.resolvedSender
        return Button { model.openSearchResult(email) } label: {
            HStack(alignment: .top, spacing: 12) {
                Avatar(sender: sender, size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if model.currentAccount == "all", let c = model.accountsById[email.account]?.color {
                            Circle().fill(c).frame(width: 6, height: 6)
                        }
                        Text(sender.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(p.fg1).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(email.time).font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundStyle(p.fg3)
                    }
                    Text(email.subject).font(.system(size: 12.5)).foregroundStyle(p.fg2).lineLimit(1)
                    if !email.preview.isEmpty {
                        Text(email.preview).font(.system(size: 12)).foregroundStyle(p.fg3).lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

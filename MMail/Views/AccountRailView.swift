import SwiftUI

struct AccountRailView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p

    private var totalUnread: Int { model.unreadByAccount.values.reduce(0, +) }

    var body: some View {
        VStack(spacing: 8) {
            // Unified "All"
            railButton(active: model.currentAccount == "all",
                       badge: model.currentAccount != "all" ? totalUnread : 0,
                       tooltip: "All inboxes  ⌘0") {
                model.currentAccount = "all"
            } label: {
                allTile
            }

            Rectangle().fill(p.border).frame(width: 24, height: 1).padding(.vertical, 4)

            ForEach(Array(model.accounts.enumerated()), id: \.element.id) { i, a in
                railButton(active: model.currentAccount == a.id,
                           badge: model.currentAccount != a.id ? (model.unreadByAccount[a.id] ?? 0) : 0,
                           tooltip: "\(a.name)  ⌘\(i + 1)") {
                    model.currentAccount = a.id
                } label: {
                    GradientTile(colors: a.gradientColors, text: a.initials, size: 38)
                }
            }

            Spacer()

            Button { model.addingAccount = true } label: {
                Icon(name: "plus", size: 18)
                    .foregroundStyle(p.fg3)
                    .frame(width: 38, height: 38)
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(p.borderStrong, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    )
            }
            .buttonStyle(.plain)
            .help("Add account")
        }
        .padding(.vertical, 12)
        .frame(width: 56)
        .frame(maxHeight: .infinity)
        .background(p.bg2)
        .overlay(Rectangle().fill(p.border).frame(width: 1), alignment: .trailing)
    }

    private var allTile: some View {
        ZStack {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    sliceColor(0); sliceColor(1)
                }
                HStack(spacing: 0) {
                    sliceColor(2); sliceColor(3)
                }
            }
            Text("All")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 1, y: 1)
        }
        .frame(width: 38, height: 38)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(p.borderStrong, lineWidth: 1)
        )
    }

    private func sliceColor(_ i: Int) -> some View {
        let color = i < model.accounts.count ? model.accounts[i].color : p.bg3
        return Rectangle().fill(color).frame(width: 19, height: 19)
    }

    @ViewBuilder
    private func railButton<L: View>(active: Bool, badge: Int, tooltip: String,
                                     action: @escaping () -> Void,
                                     @ViewBuilder label: () -> L) -> some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                label()
                    .opacity(active ? 1 : 0.55)
                if badge > 0 {
                    Text(badge > 99 ? "99+" : "\(badge)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(p.brandBlue)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(p.bg2, lineWidth: 2))
                        .offset(x: 4, y: -4)
                }
            }
            .frame(width: 38, height: 38)
            .overlay(alignment: .leading) {
                if active {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(p.fg1)
                        .frame(width: 3, height: 22)
                        .offset(x: -9)
                }
            }
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }
}

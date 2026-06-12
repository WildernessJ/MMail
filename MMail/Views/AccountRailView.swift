import SwiftUI

struct AccountRailView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p

    private var totalUnread: Int { model.unreadByAccount.values.reduce(0, +) }

    private var tile: CGFloat { model.railSize.tileSize }
    private var showsNames: Bool { model.railSize.showsNames }

    var body: some View {
        VStack(spacing: 8) {
            // Unified "All"
            railButton(active: model.currentAccount == "all",
                       badge: model.currentAccount != "all" ? totalUnread : 0,
                       tooltip: "\(model.allInboxSpec.label)  ⌘0",
                       name: model.allInboxSpec.label) {
                model.currentAccount = "all"
            } label: {
                allTile
            }

            Rectangle().fill(p.border).frame(width: 24, height: 1).padding(.vertical, 4)

            ForEach(Array(model.accounts.enumerated()), id: \.element.id) { i, a in
                railButton(active: model.currentAccount == a.id,
                           badge: model.currentAccount != a.id ? (model.unreadByAccount[a.id] ?? 0) : 0,
                           tooltip: "\(a.name)  ⌘\(i + 1)",
                           name: a.name) {
                    model.currentAccount = a.id
                } label: {
                    GradientTile(colors: a.gradientColors, text: a.initials, size: tile, image: a.avatarImage)
                }
            }

            Spacer()

            Button { model.addingAccount = true } label: {
                addRow
            }
            .buttonStyle(.plain)
            .help("Add account")
        }
        .padding(.vertical, 12)
        .frame(width: model.railSize.width)
        .frame(maxHeight: .infinity)
        .background(p.bg2)
    }

    private var allTile: some View {
        GradientTile(colors: model.allInboxColorHex.map { [Color(hex: $0)] } ?? [p.magenta],
                     text: model.allInboxSpec.tileText, size: tile, image: model.allInboxImage)
    }

    private var addRow: some View {
        let plusTile = Icon(name: "plus", size: 18)
            .foregroundStyle(p.fg3)
            .frame(width: tile, height: tile)
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(p.borderStrong, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            )
        return Group {
            if showsNames {
                HStack(spacing: 10) {
                    plusTile
                    Text("Add account")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(p.fg3)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
            } else {
                plusTile
            }
        }
    }

    @ViewBuilder
    private func railButton<L: View>(active: Bool, badge: Int, tooltip: String, name: String,
                                     action: @escaping () -> Void,
                                     @ViewBuilder label: () -> L) -> some View {
        Button(action: action) {
            let tileContent = ZStack(alignment: .topTrailing) {
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
            .frame(width: tile, height: tile)
            .overlay(alignment: .leading) {
                if active {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(p.fg1)
                        .frame(width: 3, height: 22)
                        .offset(x: -9)
                }
            }

            Group {
                if showsNames {
                    HStack(spacing: 10) {
                        tileContent
                        Text(name)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(active ? p.fg1 : p.fg2)
                            .opacity(active ? 1 : 0.55)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                } else {
                    tileContent
                }
            }
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .help(tooltip)
    }
}

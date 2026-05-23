import SwiftUI

struct JournalArchiveView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p

    var body: some View {
        ZStack(alignment: .top) {
            OverlayBackdrop { model.journalArchiveOpen = false }
            sheet.padding(.top, 80)
        }
    }

    private var sheet: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Icon(name: "pencil", size: 16).foregroundStyle(p.magenta)
                Text("Saved journal").font(.system(size: 16, weight: .bold)).foregroundStyle(p.fg1)
                Text("\(model.journalRecent.count) entr\(model.journalRecent.count == 1 ? "y" : "ies")")
                    .font(.system(size: 11.5)).foregroundStyle(p.fg3)
                Spacer()
                Button { model.journalArchiveOpen = false } label: {
                    Icon(name: "x", size: 16).foregroundStyle(p.fg3).frame(width: 30, height: 30)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 18).padding(.vertical, 16)
            .overlay(Rectangle().fill(p.border).frame(height: 1), alignment: .bottom)

            ScrollView {
                VStack(spacing: 12) {
                    if model.journalRecent.isEmpty {
                        Text("No saved entries yet.")
                            .font(.system(size: 13)).foregroundStyle(p.fg3)
                            .padding(.vertical, 40)
                    } else {
                        ForEach(model.journalRecent) { entry in
                            JournalArchiveEntry(entry: entry)
                        }
                    }
                }
                .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 20)
            }
        }
        .frame(width: 560)
        .frame(maxHeight: 600)
        .background(p.bg1)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 48, y: 24)
    }
}

private struct JournalArchiveEntry: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p
    let entry: JournalEntry
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.date.uppercased())
                    .font(.system(size: 10.5, weight: .bold)).tracking(0.6).foregroundStyle(p.fg3)
                Spacer()
                if hover {
                    Button { model.removeJournalEntry(entry.id) } label: {
                        Icon(name: "trash", size: 13).foregroundStyle(p.danger).frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain).help("Delete entry")
                }
            }
            Text(entry.text)
                .font(.system(size: 13.5)).foregroundStyle(p.fg1).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(hover ? p.bg3 : p.bg2)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(p.border, lineWidth: 1))
        .overlay(Rectangle().fill(p.magenta).frame(width: 3), alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onHover { hover = $0 }
    }
}

import SwiftUI

struct PeopleView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p
    @State private var query = ""

    private var unreadFrom: Set<String> {
        let scope = model.currentAccount == "all" ? model.emails : model.emails.filter { $0.account == model.currentAccount }
        return Set(scope.filter { $0.unread && $0.folder == "inbox" }.map { $0.from })
    }

    private var contacts: [Sender] {
        let all = model.contacts()
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter { $0.name.lowercased().contains(q) || $0.email.lowercased().contains(q) }
    }

    var body: some View {
        ZStack(alignment: .top) {
            OverlayBackdrop { model.peopleOpen = false }
            sheet.padding(.top, 88)
        }
    }

    private var sheet: some View {
        VStack(spacing: 0) {
            header
            searchBar
            if contacts.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(contacts) { person in
                            row(person)
                            Rectangle().fill(p.border).frame(height: 1)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                }
            }
        }
        .frame(width: 560)
        .frame(maxHeight: 620)
        .background(p.bg1)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(p.borderStrong, lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 48, y: 24)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("People").font(.system(size: 18, weight: .bold)).foregroundStyle(p.fg1)
                Text("\(model.contacts().count) recent contacts from your inbox.")
                    .font(.system(size: 12.5)).foregroundStyle(p.fg3)
            }
            Spacer()
            Button { model.peopleOpen = false } label: { Icon(name: "x", size: 16).foregroundStyle(p.fg2) }
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 16)
        .overlay(Rectangle().fill(p.border).frame(height: 1), alignment: .bottom)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Icon(name: "search", size: 13).foregroundStyle(p.fg3)
            TextField("Filter by name or email", text: $query)
                .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(p.fg1)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(p.bg2)
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(p.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 28).padding(.vertical, 14)
    }

    private func row(_ person: Sender) -> some View {
        HStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                Avatar(sender: person, size: 40)
                if unreadFrom.contains(person.id) {
                    Circle().fill(p.brandBlue).frame(width: 11, height: 11)
                        .overlay(Circle().stroke(p.bg1, lineWidth: 2)).offset(x: 2, y: -2)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(p.fg1).lineLimit(1)
                Text(person.email).font(.system(size: 12, design: .monospaced)).foregroundStyle(p.fg3).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button {
                model.peopleOpen = false
                model.startCompose(to: person.email, titleLabel: "To \(person.name)")
            } label: {
                HStack(spacing: 6) {
                    Icon(name: "pencil", size: 12)
                    Text("Compose").font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(p.fg2).padding(.horizontal, 10).frame(height: 28)
                .overlay(Capsule().stroke(p.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Icon(name: "user", size: 32, weight: .light).foregroundStyle(p.fg3.opacity(0.6))
            Text(query.isEmpty ? "No contacts yet" : "No matches")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(p.fg2)
            Text(query.isEmpty ? "People you receive mail from will show up here."
                 : "Try a different name or email.")
                .font(.system(size: 12.5)).foregroundStyle(p.fg3).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(40)
    }
}

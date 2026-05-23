import SwiftUI

struct ComposeView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p
    let draft: ComposeDraft

    @State private var to: String
    @State private var subject: String
    @State private var messageBody: String
    @State private var fromId: String
    @FocusState private var focus: Field?

    enum Field { case to, subject, body }

    init(draft: ComposeDraft) {
        self.draft = draft
        _to = State(initialValue: draft.to)
        _subject = State(initialValue: draft.subject)
        _messageBody = State(initialValue: draft.body)
        _fromId = State(initialValue: draft.fromId)
    }

    private var fromAcct: Account {
        model.accounts.first { $0.id == fromId } ?? model.accounts[0]
    }

    private func send() {
        var d = draft
        d.to = to; d.subject = subject; d.body = messageBody; d.fromId = fromId
        model.sendDraft(d)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            fromField
            Divider().overlay(p.border)
            field(label: "To") {
                TextField("someone@example.com", text: $to)
                    .textFieldStyle(.plain).font(.system(size: 13.5))
                    .focused($focus, equals: .to)
            }
            Divider().overlay(p.border)
            field(label: "Subject") {
                TextField("", text: $subject)
                    .textFieldStyle(.plain).font(.system(size: 13.5))
                    .focused($focus, equals: .subject)
            }
            Divider().overlay(p.border)
            TextEditor(text: $messageBody)
                .focused($focus, equals: .body)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .padding(12)
                .frame(maxHeight: .infinity)
                .overlay(alignment: .topLeading) {
                    if messageBody.isEmpty {
                        Text("Write your message…")
                            .font(.system(size: 14)).foregroundStyle(p.fg4)
                            .padding(.horizontal, 17).padding(.vertical, 20)
                            .allowsHitTesting(false)
                    }
                }
            footer
        }
        .frame(width: 540, height: 460)
        .background(p.bg1)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(p.borderStrong, lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 40, y: 16)
        .onAppear { focus = to.isEmpty ? .to : .body }
        .foregroundStyle(p.fg1)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(draft.titleLabel).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(p.fg2)
            Spacer()
            Button { model.compose = nil } label: { Icon(name: "x", size: 14).foregroundStyle(p.fg2) }
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).frame(height: 42)
        .background(p.bg2)
        .overlay(Rectangle().fill(p.border).frame(height: 1), alignment: .bottom)
    }

    private var fromField: some View {
        HStack(spacing: 0) {
            Text("From").font(.system(size: 12)).foregroundStyle(p.fg3).frame(width: 56, alignment: .leading)
            Menu {
                ForEach(model.accounts) { a in
                    Button { fromId = a.id } label: {
                        Text("\(a.name) · \(a.email)")
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    GradientTile(colors: fromAcct.gradientColors, text: fromAcct.initials, size: 18, cornerRadius: 5, fontSize: 10)
                    Text(fromAcct.email).font(.system(size: 12.5, weight: .medium)).foregroundStyle(p.fg1).lineLimit(1)
                    Icon(name: "chevronDown", size: 12).foregroundStyle(p.fg3)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(p.bg3)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Spacer()
        }
        .padding(.horizontal, 14).frame(height: 40)
    }

    private func field<C: View>(label: String, @ViewBuilder content: () -> C) -> some View {
        HStack(spacing: 0) {
            Text(label).font(.system(size: 12)).foregroundStyle(p.fg3).frame(width: 56, alignment: .leading)
            content()
        }
        .padding(.horizontal, 14).frame(height: 40)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button(action: send) {
                HStack(spacing: 8) {
                    Icon(name: "send", size: 14)
                    Text("Send").font(.system(size: 13, weight: .semibold))
                    Kbd("⌘↵", onAccent: true)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14).frame(height: 32)
                .background(p.brandBlue)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: .command)

            footerIcon("attach", help: "Attach file")
            footerIcon("clock", help: "Schedule send")
            Spacer()
            Button { model.compose = nil } label: {
                Icon(name: "trash", size: 14).foregroundStyle(p.fg3).frame(width: 30, height: 30)
            }.buttonStyle(.plain).help("Discard")
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .overlay(Rectangle().fill(p.border).frame(height: 1), alignment: .top)
    }

    private func footerIcon(_ icon: String, help: String) -> some View {
        Button {} label: {
            Icon(name: icon, size: 14).foregroundStyle(p.fg3).frame(width: 30, height: 30)
        }.buttonStyle(.plain).help(help)
    }
}

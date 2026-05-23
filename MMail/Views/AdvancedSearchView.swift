import SwiftUI

struct AdvancedSearchView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p

    var body: some View {
        ZStack(alignment: .top) {
            OverlayBackdrop { model.advancedSearchOpen = false }
            sheet.padding(.top, 88)
        }
    }

    private var sheet: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    field("Contains", text: $model.advForm.text, placeholder: "Words anywhere in the message")
                    HStack(spacing: 12) {
                        field("From", text: $model.advForm.from, placeholder: "sender@example.com")
                        field("To", text: $model.advForm.to, placeholder: "recipient@example.com")
                    }
                    field("Subject", text: $model.advForm.subject, placeholder: "Words in the subject")
                    accountRow
                    dateRow
                    flagsRow
                }
                .padding(.horizontal, 28).padding(.vertical, 22)
            }
            footer
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
                Text("Advanced search").font(.system(size: 18, weight: .bold)).foregroundStyle(p.fg1)
                Text("Search the server with multiple filters.").font(.system(size: 12.5)).foregroundStyle(p.fg3)
            }
            Spacer()
            Button { model.advancedSearchOpen = false } label: { Icon(name: "x", size: 16).foregroundStyle(p.fg2) }
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 16)
        .overlay(Rectangle().fill(p.border).frame(height: 1), alignment: .bottom)
    }

    private var accountRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("ACCOUNT").font(.system(size: 11, weight: .medium)).foregroundStyle(p.fg3)
            Picker("", selection: $model.advForm.account) {
                Text("All accounts").tag("all")
                ForEach(model.accounts) { a in Text(a.name).tag(a.id) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    private var dateRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DATE RANGE").font(.system(size: 11, weight: .medium)).foregroundStyle(p.fg3)
            HStack(spacing: 10) {
                Toggle("After", isOn: $model.advForm.useAfter).toggleStyle(.checkbox)
                DatePicker("", selection: $model.advForm.after, displayedComponents: .date)
                    .labelsHidden().disabled(!model.advForm.useAfter)
                Spacer()
            }
            HStack(spacing: 10) {
                Toggle("Before", isOn: $model.advForm.useBefore).toggleStyle(.checkbox)
                DatePicker("", selection: $model.advForm.before, displayedComponents: .date)
                    .labelsHidden().disabled(!model.advForm.useBefore)
                Spacer()
            }
            .font(.system(size: 13)).foregroundStyle(p.fg2)
        }
    }

    private var flagsRow: some View {
        HStack(spacing: 20) {
            Toggle("Unread only", isOn: $model.advForm.unreadOnly).toggleStyle(.checkbox)
            Toggle("Starred only", isOn: $model.advForm.flaggedOnly).toggleStyle(.checkbox)
            Spacer()
        }
        .font(.system(size: 13)).foregroundStyle(p.fg2)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button { model.advForm = AdvancedSearchForm() } label: {
                Text("Clear").font(.system(size: 12.5, weight: .medium)).foregroundStyle(p.fg2)
            }
            .buttonStyle(.plain)
            Spacer()
            Button { model.advancedSearchOpen = false } label: {
                Text("Cancel").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(p.fg2)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .overlay(Capsule().stroke(p.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            Button { model.runAdvancedSearch() } label: {
                HStack(spacing: 6) {
                    Icon(name: "search", size: 12).foregroundStyle(.white)
                    Text("Search").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white)
                }
                .padding(.horizontal, 16).padding(.vertical, 7)
                .background(p.brandBlue).clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [])
        }
        .padding(.horizontal, 28).padding(.vertical, 14)
        .overlay(Rectangle().fill(p.border).frame(height: 1), alignment: .top)
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased()).font(.system(size: 11, weight: .medium)).foregroundStyle(p.fg3)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain).font(.system(size: 13.5)).foregroundStyle(p.fg1)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(p.bg2)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(p.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .autocorrectionDisabled()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

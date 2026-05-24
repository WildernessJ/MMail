import SwiftUI

struct OutboxView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p

    private var items: [ScheduledSend] { model.scheduled.sorted { $0.sendAt < $1.sendAt } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(p.border)
            if items.isEmpty && model.sending.isEmpty { empty } else { list }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(p.bg1)
    }

    private var header: some View {
        let total = items.count + model.sending.count
        return VStack(alignment: .leading, spacing: 4) {
            Text("Outbox").font(.system(size: 22, weight: .bold)).foregroundStyle(p.fg1)
            Text(total == 0 ? "Nothing queued" : "\(total) message\(total == 1 ? "" : "s") sending or scheduled")
                .font(.system(size: 12.5)).foregroundStyle(p.fg3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Icon(name: "outbox", size: 36, weight: .light).foregroundStyle(p.fg3.opacity(0.5))
            Text("No scheduled mail").font(.system(size: 18, weight: .bold)).foregroundStyle(p.fg2)
            Text("Messages you schedule to send later wait here. You can send them now or cancel.")
                .font(.system(size: 13)).foregroundStyle(p.fg3).multilineTextAlignment(.center).frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(40)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(model.sending) { item in
                    sendingRow(item)
                    Divider().overlay(p.border)
                }
                ForEach(items) { s in
                    row(s)
                    Divider().overlay(p.border)
                }
            }
        }
    }

    private func sendingRow(_ item: SendingItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.to).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(p.fg1).lineLimit(1)
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: Int64(item.sizeBytes), countStyle: .file))
                    .font(.system(size: 11)).monospacedDigit().foregroundStyle(p.fg3)
            }
            Text(item.subject).font(.system(size: 13)).foregroundStyle(p.fg2).lineLimit(1)
            if item.failed {
                HStack(spacing: 8) {
                    Icon(name: "alert", size: 12).foregroundStyle(p.danger)
                    Text(item.error ?? "Send failed").font(.system(size: 12)).foregroundStyle(p.danger).lineLimit(2)
                    Spacer()
                    Button { model.retrySend(item.id) } label: {
                        Text("Retry").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 12).frame(height: 26).background(p.brandBlue).clipShape(Capsule())
                    }.buttonStyle(.plain)
                    Button { model.dismissSending(item.id) } label: {
                        Text("Dismiss").font(.system(size: 12, weight: .semibold)).foregroundStyle(p.fg2)
                            .padding(.horizontal, 12).frame(height: 26).overlay(Capsule().stroke(p.border, lineWidth: 1))
                    }.buttonStyle(.plain)
                }
                .padding(.top, 2)
            } else {
                HStack(spacing: 8) {
                    ProgressView(value: item.progress).progressViewStyle(.linear).tint(p.brandBlue)
                    Text(item.progress > 0 ? "\(Int(item.progress * 100))%" : "Sending…")
                        .font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundStyle(p.brandBlue)
                        .frame(width: 64, alignment: .trailing)
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ s: ScheduledSend) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(s.to.isEmpty ? "(no recipient)" : s.to).font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(p.fg1).lineLimit(1)
                Spacer()
                HStack(spacing: 4) {
                    Icon(name: "clock", size: 11).foregroundStyle(p.brandBlue)
                    Text(sendAtLabel(s.sendAt)).font(.system(size: 11.5, weight: .medium))
                        .monospacedDigit().foregroundStyle(p.brandBlue)
                }
            }
            Text(s.subject.isEmpty ? "(no subject)" : s.subject).font(.system(size: 13)).foregroundStyle(p.fg2).lineLimit(1)
            if !s.body.isEmpty {
                Text(s.body).font(.system(size: 12.5)).foregroundStyle(p.fg3).lineLimit(2)
            }
            HStack(spacing: 8) {
                Button { model.sendScheduledNow(s.id) } label: {
                    HStack(spacing: 5) { Icon(name: "send", size: 12); Text("Send now").font(.system(size: 12, weight: .semibold)) }
                        .foregroundStyle(.white).padding(.horizontal, 12).frame(height: 28)
                        .background(p.brandBlue).clipShape(Capsule())
                }.buttonStyle(.plain)
                Button { model.cancelScheduled(s.id) } label: {
                    Text("Cancel").font(.system(size: 12, weight: .semibold)).foregroundStyle(p.fg2)
                        .padding(.horizontal, 12).frame(height: 28)
                        .overlay(Capsule().stroke(p.border, lineWidth: 1))
                }.buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sendAtLabel(_ date: Date) -> String {
        let f = DateFormatter()
        if Calendar.current.isDateInToday(date) { f.dateFormat = "'Today' h:mm a" }
        else if Calendar.current.isDateInTomorrow(date) { f.dateFormat = "'Tomorrow' h:mm a" }
        else { f.dateFormat = "MMM d, h:mm a" }
        return f.string(from: date)
    }
}

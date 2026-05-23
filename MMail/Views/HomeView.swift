import SwiftUI

struct HomeView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p
    @State private var draftTodo = ""

    private let months = ["January","February","March","April","May","June","July","August","September","October","November","December"]
    private let dows = ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"]

    private struct DateParts { let dow: String; let num: Int; let month: String; let year: Int; let full: String }
    private var parts: DateParts {
        let d = Date(); let c = Calendar.current
        let dowFull = dows[c.component(.weekday, from: d) - 1]
        let m = months[c.component(.month, from: d) - 1]
        let num = c.component(.day, from: d)
        let y = c.component(.year, from: d)
        return DateParts(dow: String(dowFull.prefix(3)), num: num, month: m, year: y, full: "\(dowFull), \(m) \(num)")
    }
    private var hello: String {
        let h = Calendar.current.component(.hour, from: Date())
        if h < 5 { return "Still up" }
        if h < 12 { return "Good morning" }
        if h < 18 { return "Good afternoon" }
        return "Good evening"
    }

    private var homeEmails: [Email] {
        model.currentAccount == "all" ? model.emails : model.emails.filter { $0.account == model.currentAccount }
    }
    private var people: [Sender] {
        // Derive the most recent distinct human senders from the real inbox.
        var seen = Set<String>()
        var result: [Sender] = []
        for e in homeEmails where e.folder == "inbox" {
            let s = e.resolvedSender
            guard !s.email.isEmpty, s.id != "you", s.org != .bot else { continue }
            if seen.insert(s.email).inserted {
                result.append(s)
                if result.count == 6 { break }
            }
        }
        return result.isEmpty ? SampleData.homePeople.compactMap { SampleData.senders[$0] } : result
    }
    private var unreadFrom: Set<String> {
        Set(homeEmails.filter { $0.unread && $0.folder == "inbox" }.map { $0.from })
    }

    private let cols = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                (Text(hello).foregroundStyle(p.fg1) + Text(".").foregroundStyle(p.brandBlue)
                 + Text(" ").foregroundStyle(p.fg1) + Text(parts.full).foregroundStyle(p.fg3))
                    .font(.system(size: 28, weight: .bold))
                    .padding(.bottom, 4)
                Text("A glance at your day before you dive into mail.")
                    .font(.system(size: 14)).foregroundStyle(p.fg3)
                    .padding(.bottom, 28)

                LazyVGrid(columns: cols, alignment: .leading, spacing: 16) {
                    dateCard
                    weatherCard
                    peopleCard
                }
                HStack(alignment: .top, spacing: 16) {
                    journalCard
                    todoCard
                }
                .padding(.top, 16)
            }
            .frame(maxWidth: 1100, alignment: .leading)
            .padding(.horizontal, 40).padding(.top, 32).padding(.bottom, 56)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(p.bg2)
    }

    // MARK: Cards

    private func cardHead(icon: String, title: String, trailing: String? = nil) -> some View {
        HStack(spacing: 8) {
            Icon(name: icon, size: 14).foregroundStyle(p.fg3)
            Text(title.uppercased()).font(.system(size: 10.5, weight: .bold)).tracking(0.8).foregroundStyle(p.fg3)
            Spacer()
            if let trailing { Text(trailing).font(.system(size: 11)).foregroundStyle(p.fg3) }
        }
        .padding(.bottom, 14)
    }

    private func card<C: View>(square: Bool = false, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 180)
            .aspectRatio(square ? 1 : nil, contentMode: .fill)
            .background(p.bg1)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(p.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var dateCard: some View {
        card(square: true) {
            cardHead(icon: "clock", title: "Date")
            Text(parts.dow).font(.system(size: 20, weight: .bold)).foregroundStyle(p.danger)
            Text("\(parts.num)").font(.system(size: 96, weight: .heavy)).foregroundStyle(p.fg1)
                .minimumScaleFactor(0.5).lineLimit(1)
            Text("\(parts.month) \(parts.year)").font(.system(size: 12.5)).foregroundStyle(p.fg3).padding(.top, 8)
            Spacer(minLength: 0)
        }
    }

    private var weatherCard: some View {
        let w = SampleData.weather
        return card(square: true) {
            cardHead(icon: "sun", title: "Weather", trailing: w.location.split(separator: ",").first.map(String.init))
            WeatherGlyph(size: 56)
            Text("\(w.temp)°F").font(.system(size: 60, weight: .heavy)).foregroundStyle(p.fg1)
                .minimumScaleFactor(0.5).lineLimit(1).padding(.top, 4)
            Text(w.condition).font(.system(size: 12.5)).foregroundStyle(p.fg3).padding(.top, 4)
            Spacer(minLength: 8)
            VStack(spacing: 4) {
                HStack { Text("Feels like").foregroundStyle(p.fg2); Spacer(); Text("\(w.feels)°F").foregroundStyle(p.fg1).fontWeight(.medium) }
                HStack { Text("Today").foregroundStyle(p.fg2); Spacer(); Text("H \(w.hi)° / L \(w.lo)°").foregroundStyle(p.fg1).fontWeight(.medium) }
            }
            .font(.system(size: 12)).monospacedDigit()
            .padding(.top, 12)
            .overlay(Rectangle().fill(p.border).frame(height: 1), alignment: .top)
        }
    }

    private var peopleCard: some View {
        card(square: true) {
            cardHead(icon: "user", title: "People", trailing: "View all →")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                ForEach(people) { person in
                    Button { model.startCompose(to: person.email, titleLabel: "To \(person.name)") } label: {
                        VStack(spacing: 8) {
                            ZStack(alignment: .topTrailing) {
                                Avatar(sender: person, size: 56)
                                if unreadFrom.contains(person.id) {
                                    Circle().fill(p.brandBlue).frame(width: 12, height: 12)
                                        .overlay(Circle().stroke(p.bg1, lineWidth: 2))
                                        .offset(x: 2, y: -2)
                                }
                            }
                            Text(person.firstName).font(.system(size: 12)).foregroundStyle(p.fg1).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxHeight: .infinity)
            Spacer(minLength: 0)
        }
    }

    private var journalCard: some View {
        card {
            cardHead(icon: "pencil", title: "Journal", trailing: "Open archive")
            HStack(spacing: 6) {
                Circle().fill(p.magenta).frame(width: 6, height: 6)
                Text("\(parts.dow.uppercased()) · \(parts.month.uppercased()) \(parts.num), \(parts.year)")
                    .font(.system(size: 11.5, weight: .medium)).foregroundStyle(p.fg3)
            }
            .padding(.bottom, 8)
            ZStack(alignment: .topLeading) {
                if model.journal.isEmpty {
                    Text("What's on your mind, \(parts.dow)?").font(.system(size: 14)).foregroundStyle(p.fg4)
                        .padding(.top, 0)
                }
                TextEditor(text: Binding(get: { model.journal }, set: { model.journal = $0; model.persistJournal() }))
                    .font(.system(size: 14)).scrollContentBackground(.hidden).background(Color.clear)
                    .frame(minHeight: 100)
            }
            HStack(spacing: 8) {
                Icon(name: "check", size: 12).foregroundStyle(p.fg3)
                Text("Autosaved \(model.journal.isEmpty ? "" : "just now")").font(.system(size: 11.5)).foregroundStyle(p.fg3)
                Spacer()
                Text("\(wordCount) words").font(.system(size: 11.5)).monospacedDigit().foregroundStyle(p.fg3)
            }
            .padding(.top, 12)
            .overlay(Rectangle().fill(p.border).frame(height: 1), alignment: .top)
            .padding(.top, 12)

            Button { model.journalArchiveOpen = true } label: {
                HStack(spacing: 8) {
                    Icon(name: "file", size: 13).foregroundStyle(p.fg3)
                    Text("Saved journal").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(p.fg1)
                    Text("\(model.journalRecent.count)")
                        .font(.system(size: 11, weight: .bold)).monospacedDigit()
                        .foregroundStyle(p.magenta)
                        .padding(.horizontal, 6).frame(minWidth: 18, minHeight: 18)
                        .background(p.magenta100)
                        .clipShape(Capsule())
                    Icon(name: "chevronRight", size: 12).foregroundStyle(p.fg3)
                }
                .padding(.init(top: 8, leading: 12, bottom: 8, trailing: 10))
                .background(p.bg2)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(p.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 14)
        }
    }

    private var wordCount: Int {
        model.journal.split(whereSeparator: { $0 == " " || $0 == "\n" }).filter { !$0.isEmpty }.count
    }

    private var todoCard: some View {
        card {
            cardHead(icon: "check", title: "To do", trailing: "\(model.todos.filter { !$0.done }.count) open")
            HStack(spacing: 8) {
                Icon(name: "pencil", size: 13).foregroundStyle(p.fg3)
                TextField("Add a to-do…", text: $draftTodo)
                    .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(p.fg1)
                    .onSubmit { model.addTodo(draftTodo); draftTodo = "" }
                if !draftTodo.isEmpty { Text("↵").font(.system(size: 10)).foregroundStyle(p.fg4) }
            }
            .padding(8)
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(p.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .padding(.bottom, 8)

            if model.todos.isEmpty {
                Text("Nothing on the list. Add one above.").font(.system(size: 13)).foregroundStyle(p.fg3).padding(.vertical, 12)
            } else {
                VStack(spacing: 1) {
                    ForEach(model.todos) { todo in TodoRow(todo: todo) }
                }
            }
        }
    }
}

struct TodoRow: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p
    let todo: Todo
    @State private var hovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button { model.toggleTodo(todo.id) } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(todo.done ? p.brandBlue : Color.clear)
                        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(todo.done ? p.brandBlue : p.borderStrong, lineWidth: 1.5))
                        .frame(width: 16, height: 16)
                    if todo.done { Icon(name: "check", size: 11, weight: .bold).foregroundStyle(.white) }
                }
            }.buttonStyle(.plain).padding(.top, 2)
            Text(todo.text)
                .font(.system(size: 13.5))
                .foregroundStyle(todo.done ? p.fg4 : p.fg1)
                .strikethrough(todo.done, color: p.fg4)
            Spacer(minLength: 8)
            if let src = todo.source, let s = SampleData.senders[src] {
                Avatar(sender: s, size: 16).help("From \(s.name)")
            }
            if hovered {
                Button { model.removeTodo(todo.id) } label: {
                    Icon(name: "x", size: 12).foregroundStyle(p.fg3).frame(width: 22, height: 22)
                }.buttonStyle(.plain).help("Remove")
            }
        }
        .padding(.horizontal, 4).padding(.vertical, 7)
        .background(hovered ? p.bg3 : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onHover { hovered = $0 }
    }
}

struct WeatherGlyph: View {
    var size: CGFloat = 48
    var body: some View {
        Canvas { ctx, sz in
            let s = sz.width / 48
            let sun = CGPoint(x: 18 * s, y: 18 * s)
            ctx.fill(Path(ellipseIn: CGRect(x: sun.x - 8 * s, y: sun.y - 8 * s, width: 16 * s, height: 16 * s)),
                     with: .color(Color(hex: "F4A52A")))
            for deg in stride(from: 0, to: 360, by: 45) {
                let r = Double(deg) * .pi / 180
                let p1 = CGPoint(x: sun.x + 12 * s * cos(r), y: sun.y + 12 * s * sin(r))
                let p2 = CGPoint(x: sun.x + 16 * s * cos(r), y: sun.y + 16 * s * sin(r))
                var ray = Path(); ray.move(to: p1); ray.addLine(to: p2)
                ctx.stroke(ray, with: .color(Color(hex: "F4A52A")), style: StrokeStyle(lineWidth: 2 * s, lineCap: .round))
            }
            var cloud = Path()
            cloud.move(to: CGPoint(x: 16 * s, y: 32 * s))
            cloud.addQuadCurve(to: CGPoint(x: 22 * s, y: 26 * s), control: CGPoint(x: 16 * s, y: 26 * s))
            cloud.addQuadCurve(to: CGPoint(x: 37.5 * s, y: 28 * s), control: CGPoint(x: 30 * s, y: 18 * s))
            cloud.addQuadCurve(to: CGPoint(x: 37 * s, y: 38 * s), control: CGPoint(x: 42.5 * s, y: 33 * s))
            cloud.addLine(to: CGPoint(x: 22 * s, y: 38 * s))
            cloud.addQuadCurve(to: CGPoint(x: 16 * s, y: 32 * s), control: CGPoint(x: 16 * s, y: 38 * s))
            ctx.fill(cloud, with: .color(.white))
            ctx.stroke(cloud, with: .color(Color(hex: "0E0F1A").opacity(0.18)), lineWidth: 1 * s)
        }
        .frame(width: size, height: size)
    }
}

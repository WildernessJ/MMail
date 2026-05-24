import Foundation

// Sample mailbox — designer at a tech company. Ported from the design's data.js.
enum SampleData {

    static let senders: [String: Sender] = {
        let raw: [(String, String, String, String, Org)] = [
            ("sarah", "Sarah Chen", "sarah@cobalt.studio", "E5484D", .team),
            ("marcus", "Marcus Liu", "marcus@cobalt.studio", "1FB36B", .team),
            ("maya", "Maya Rodriguez", "maya@cobalt.studio", "7A5AE0", .team),
            ("theo", "Theo Andersen", "theo@cobalt.studio", "F4A52A", .team),
            ("anya", "Anya Petrov", "anya@cobalt.studio", "2D3DEC", .team),
            ("daniel", "Daniel Park", "daniel@northstar.xyz", "0EA5E9", .ext),
            ("priya", "Priya Sharma", "priya@northstar.xyz", "D946EF", .ext),
            ("jordan", "Jordan Reeves", "jordan@waveform.dev", "06B6D4", .ext),
            ("linear", "Linear", "notifications@linear.app", "5E6AD2", .bot),
            ("figma", "Figma", "notifications@figma.com", "F24E1E", .bot),
            ("slack", "Slack", "noreply@slack.com", "4A154B", .bot),
            ("github", "GitHub", "noreply@github.com", "0E0F1A", .bot),
            ("notion", "Notion", "team@notion.so", "0E0F1A", .bot),
            ("vercel", "Vercel", "noreply@vercel.com", "0E0F1A", .bot),
            ("loom", "Loom", "notifications@loom.com", "625DF5", .bot),
            ("stripe", "Stripe", "receipts@stripe.com", "635BFF", .bot),
            ("calendly", "Calendly", "no-reply@calendly.com", "0073EB", .bot),
            ("apple", "Apple Developer", "developer@apple.com", "0E0F1A", .bot),
            ("dropbox", "Dropbox Paper", "no-reply@dropbox.com", "0061FF", .bot),
            ("mom", "Mom", "mom@me.com", "E5484D", .ext),
            ("spotify", "Spotify", "no-reply@spotify.com", "1ED760", .bot),
            ("airbnb", "Airbnb", "automated@airbnb.com", "FF5A5F", .bot),
            ("substack", "Substack", "digest@substack.com", "FF6719", .bot),
            ("rei", "REI Co-op", "rewards@rei.com", "155843", .bot),
            ("lumen", "Elena Voss", "elena@lumencoffee.co", "B25A2A", .ext),
            ("squarespace", "Squarespace", "no-reply@squarespace.com", "0E0F1A", .bot),
            ("rafael", "Rafael Mendes", "rafael@studio-norte.com", "0EA5E9", .ext)
        ]
        var m: [String: Sender] = [:]
        for r in raw {
            m[r.0] = Sender(id: r.0, name: r.1, email: r.2, colorHex: r.3, org: r.4)
        }
        return m
    }()

    static let accounts: [Account] = [
        Account(id: "work", name: "Cobalt Studio", email: "you@cobalt.studio",
                initials: "C", gradient: ["2D3DEC", "1E2DB0"], colorHex: "2D3DEC",
                provider: "Google Workspace"),
        Account(id: "personal", name: "Personal", email: "you@gmail.com",
                initials: "Y", gradient: ["E5484D", "C9156A"], colorHex: "E5484D",
                provider: "Gmail"),
        Account(id: "freelance", name: "Side projects", email: "studio@yourname.com",
                initials: "S", gradient: ["7A5AE0", "5B3DD0"], colorHex: "7A5AE0",
                provider: "Fastmail")
    ]

    static let labels: [MailLabel] = [
        MailLabel(id: "team", name: "Team", colorHex: "1FB36B"),
        MailLabel(id: "design", name: "Design tools", colorHex: "E91E78"),
        MailLabel(id: "eng", name: "Eng", colorHex: "5E6AD2"),
        MailLabel(id: "recruit", name: "Recruiting", colorHex: "F4A52A"),
        MailLabel(id: "receipt", name: "Receipts", colorHex: "6B7088")
    ]

    static let folders: [Folder] = [
        Folder(id: "home", name: "Home", shortcut: "g h"),
        Folder(id: "inbox", name: "Inbox", shortcut: "g i"),
        Folder(id: "starred", name: "Starred", shortcut: "g s"),
        Folder(id: "snoozed", name: "Snoozed", shortcut: "g z"),
        Folder(id: "done", name: "Done", shortcut: "g e"),
        Folder(id: "archive", name: "Archive", shortcut: nil),
        Folder(id: "sent", name: "Sent", shortcut: "g t"),
        Folder(id: "outbox", name: "Outbox", shortcut: nil),
        Folder(id: "drafts", name: "Drafts", shortcut: "g d"),
        Folder(id: "spam", name: "Spam", shortcut: nil),
        Folder(id: "trash", name: "Trash", shortcut: nil)
    ]

    static let homePeople = ["sarah", "marcus", "maya", "theo", "daniel", "lumen"]

    static let weather = WeatherInfo(temp: 22, feels: 22, hi: 24, lo: 18,
                                     condition: "Partly sunny", location: "San Francisco, CA")

    static let replyTemplates: [ReplyTemplate] = [
        ReplyTemplate(id: "tpl-thanks", name: "Thanks", shortcut: "1",
                      body: "Thanks for sending this over — really appreciate it.\n\nWill take a closer look and get back to you shortly."),
        ReplyTemplate(id: "tpl-got-it", name: "Got it, will follow up", shortcut: "2",
                      body: "Got it — thanks for the note.\n\nGive me a day or two to think it through and I'll come back with a proper reply."),
        ReplyTemplate(id: "tpl-looks-good", name: "Looks great, ship it", shortcut: "3",
                      body: "This looks great. No notes from my end — happy to ship as-is.\n\nLet me know once it's live."),
        ReplyTemplate(id: "tpl-need-more", name: "Need more info", shortcut: "4",
                      body: "A few quick questions before I can answer properly:\n\n1.\n2.\n3.\n\nOnce I have those I should be able to turn this around quickly."),
        ReplyTemplate(id: "tpl-cant-make-it", name: "Can't make it", shortcut: "5",
                      body: "Thanks for the invite — unfortunately I won't be able to make this one.\n\nHappy to catch up over the notes afterward if useful."),
        ReplyTemplate(id: "tpl-intro", name: "Warm intro", shortcut: "6",
                      body: "Wanted to put the two of you in touch — I think there's a useful conversation to be had here.\n\nI'll let you take it from here.")
    ]

    static let emails: [Email] = [
        Email(id: "e01", account: "work", from: "sarah", to: ["you@cobalt.studio"],
              subject: "Re: Onboarding redesign — final review tomorrow?",
              preview: "Looks great so far. Two quick notes on the empty state and the welcome step before we lock —",
              body: """
              Hey,

              Looks great so far. Two quick notes before we lock this in tomorrow:

              1. The empty state on step 2 still feels heavy. Can we drop the illustration and let the copy carry it?
              2. The welcome step copy is a touch too long — try cutting the second sentence entirely.

              Otherwise I think we're good. Let's use the 11am slot if it still works for you.

              S.
              """,
              time: "2:14 PM", day: "today", unread: true, starred: true,
              labels: ["team"], folder: "inbox",
              thread: [
                ThreadItem(from: "you", time: "Yesterday 6:02 PM", preview: "Latest pass attached — would love a quick look before tomorrow."),
                ThreadItem(from: "sarah", time: "Yesterday 8:41 PM", preview: "On it tomorrow morning, will send notes by lunch.")
              ]),
        Email(id: "e02", account: "work", from: "linear",
              subject: "Sprint 47 closed · 23 issues shipped, 4 carried over",
              preview: "23 issues completed this cycle. Top contributors: Marcus (8), you (6), Maya (5). 4 issues carried into Sprint 48.",
              body: """
              Sprint 47 has closed.

              23 issues completed · 4 carried over · 12 days

              Top contributors
              • Marcus Liu — 8 issues
              • You — 6 issues
              • Maya Rodriguez — 5 issues
              • Theo Andersen — 4 issues

              Carried into Sprint 48
              • DES-412 Reading pane spacing audit
              • DES-418 Dark mode token review
              • DES-421 Empty states pass
              • DES-425 Compose attachment UX

              View sprint report →
              """,
              time: "1:08 PM", day: "today", unread: true,
              labels: ["eng"], folder: "inbox"),
        Email(id: "e03", account: "work", from: "figma",
              subject: "Daniel commented on Pricing v3.2",
              preview: "\"Love the swap to a single-column layout here. One nit — the per-seat row needs more breathing room above the divider.\"",
              body: """
              Daniel Park left 3 new comments on Pricing v3.2.

              "Love the swap to a single-column layout here. One nit — the per-seat row needs more breathing room above the divider."

              "Why is the annual toggle to the right of the price now? Felt more natural on the left in v3.1."

              "+1 to shipping this as is, we can tune the toggle position in a follow-up."

              Open in Figma →
              """,
              time: "12:46 PM", day: "today", unread: true,
              labels: ["design"], folder: "inbox"),
        Email(id: "e04", account: "work", from: "marcus",
              subject: "Spec questions: Reading pane spacing",
              preview: "Three things I want to confirm before I commit the tokens — what should the gap between subject and first message be at the new airy density?",
              body: """
              Hey — quick clarifications before I commit the new spacing tokens:

              1. Gap between subject row and first message body — 24 or 32?
              2. Reply composer height when collapsed — fixed 48 or 56?
              3. Attachment row — do we keep the icon left-aligned or center it with the filename?

              Happy to default to whatever you pick. Just want to lock it before I ship the PR.

              M.
              """,
              time: "11:30 AM", day: "today", unread: true,
              labels: ["team", "eng"], folder: "inbox"),
        Email(id: "e05", account: "work", from: "slack",
              subject: "5 new mentions in #design-crit",
              preview: "Maya, Theo and 2 others mentioned you. Latest: \"@you the radius on the focus ring looks great in the reader but it's a little chunky on the chips\"",
              body: """
              You have 5 unread mentions across 2 channels.

              #design-crit (4)
              • @maya — "the radius on the focus ring looks great in the reader…"
              • @theo — "+1 — also the chip ring feels heavy, maybe drop to 1.5px"
              • @sarah — "agreed, lighter ring on chips"
              • @maya — "shall we sync after standup tomorrow?"

              #design-system (1)
              • @daniel — "is the new motion token doc ready to share with eng yet?"

              Open Slack →
              """,
              time: "10:55 AM", day: "today",
              labels: ["team"], folder: "inbox"),
        Email(id: "e06", account: "work", from: "github",
              subject: "[design-system] PR #284 ready for review · Add motion tokens",
              preview: "Marcus Liu opened PR #284 in cobalt/design-system. Adds duration-fast/base/slow and ease-out/ease-in tokens, plus updated docs.",
              body: """
              Marcus Liu requested your review on PR #284.

              cobalt/design-system · Add motion tokens

              +248 −12 across 14 files
              • Added --duration-fast / -base / -slow
              • Added --ease-out / --ease-in
              • Updated MotionProvider and 6 components
              • New tokens documented in /docs/motion.md

              Review on GitHub →
              """,
              time: "10:12 AM", day: "today",
              labels: ["eng", "design"], folder: "inbox"),
        Email(id: "e07", account: "work", from: "anya",
              subject: "Quick chat about the Staff Design opening?",
              preview: "I know you said no recruiters this quarter — totally respect it. But Northstar reached out specifically and I think it's worth 15 minutes.",
              body: """
              Hey,

              I know you said no recruiters this quarter — totally respect it. But Northstar reached out specifically and I think it's worth 15 minutes if you can spare it.

              They're looking for a Staff Design lead for a new platform team. The compensation band is meaningfully higher than your current, and the work sounds genuinely interesting (zero-to-one prosumer thing in the design-tools adjacent space).

              No pressure at all. If a no is a no, just say the word and I'll close the loop.

              Anya
              """,
              time: "9:48 AM", day: "today", starred: true,
              labels: ["recruit"], folder: "inbox"),
        Email(id: "e08", account: "work", from: "maya",
              subject: "Critique notes from Friday",
              preview: "Wrote up the notes from the Friday crit before I forget them. Mostly small stuff — let me know if any of it should turn into tickets.",
              body: """
              Hi,

              Wrote up the crit notes before I forget them. Mostly small — let me know what should turn into tickets.

              • Reading pane: subject feels heavy at 24px — try 22 with -0.01em
              • List rows: the unread indicator is too saturated, drop it to the 600 step
              • Avatars: pixel snap is off on retina, half-pixel border showing
              • Sidebar: hover lift on collapsed items is overdoing it, try just a background tint
              • Search: the placeholder copy could be friendlier ("Search mail" → something more specific)

              M.
              """,
              time: "9:21 AM", day: "today", hasAttachment: true,
              labels: ["team", "design"], folder: "inbox"),
        Email(id: "e09", account: "work", from: "notion",
              subject: "Q2 Design Roadmap was edited by 3 people",
              preview: "Sarah, Theo and Maya edited the page in the last 24 hours. 7 new comments. 2 new sub-pages: \"Reader v2 specs\" and \"Onboarding flow audit\".",
              body: """
              Q2 Design Roadmap was edited by Sarah Chen, Theo Andersen, and Maya Rodriguez in the last 24 hours.

              7 new comments · 2 new sub-pages

              New sub-pages
              • Reader v2 specs (Theo)
              • Onboarding flow audit (Sarah)

              Open in Notion →
              """,
              time: "Yesterday", day: "yesterday",
              labels: ["team"], folder: "inbox"),
        Email(id: "e10", account: "work", from: "jordan",
              subject: "Portfolio review — would you be up for it?",
              preview: "I'm putting together a portfolio review night for the early-career designers at our coworking space and would love to have you on the panel.",
              body: """
              Hey,

              I'm putting together a portfolio review night for the early-career designers at our coworking space and would love to have you on the panel — 3 reviewers, 4 portfolios, ~90 minutes total.

              Date is flexible. Closest Thursday that works for you would be ideal.

              It'd mean a lot to the folks coming in. Let me know!

              Jordan
              """,
              time: "Yesterday", day: "yesterday", folder: "inbox"),
        Email(id: "e11", account: "work", from: "vercel",
              subject: "Preview deployed · feat/onboarding-v4",
              preview: "Preview is ready at onboarding-v4-cobalt.vercel.app. Build took 38s, 0 errors. Lighthouse: 98 perf, 100 a11y.",
              body: """
              Preview deployed for feat/onboarding-v4.

              cobalt/web · Vercel

              onboarding-v4-cobalt.vercel.app

              Build · 38s · 0 errors
              Lighthouse · Perf 98 · A11y 100 · BP 100 · SEO 100

              Open preview →
              """,
              time: "Yesterday", day: "yesterday",
              labels: ["eng"], folder: "inbox"),
        Email(id: "e12", account: "work", from: "calendly",
              subject: "New booking · 1:1 with Theo Andersen, Wed 3:00 PM",
              preview: "Theo Andersen booked your 1:1 slot for Wednesday at 3:00 PM. Topic: \"Reader v2 specs — spacing + motion.\"",
              body: """
              New booking confirmed.

              Theo Andersen · Wednesday 3:00–3:30 PM PT

              Topic: Reader v2 specs — spacing + motion

              Calendar invite has been sent. Reschedule or cancel via Calendly.
              """,
              time: "Yesterday", day: "yesterday", folder: "inbox"),
        Email(id: "e13", account: "work", from: "stripe",
              subject: "Receipt · Figma Organization · $540.00",
              preview: "Receipt for $540.00 charged to Visa •• 4242. Figma Organization plan, annual, 3 seats.",
              body: """
              Receipt for your payment.

              Figma Organization · annual · 3 seats
              $540.00 USD charged to Visa •• 4242

              Invoice #IN-2026-04412
              """,
              time: "Mon", day: "earlier", hasAttachment: true,
              labels: ["receipt"], folder: "inbox"),
        Email(id: "e14", account: "work", from: "loom",
              subject: "Your video has 12 new views",
              preview: "\"Onboarding v4 walkthrough\" picked up 12 new views in the last 24 hours. 3 viewers reacted, 1 left a comment.",
              body: """
              "Onboarding v4 walkthrough" picked up 12 new views in the last 24 hours.

              3 reactions · 1 new comment

              Latest comment from Daniel Park: "this is exactly what I needed to see, thanks for recording it"

              Open video →
              """,
              time: "Mon", day: "earlier", folder: "inbox"),
        Email(id: "e15", account: "work", from: "dropbox",
              subject: "Design Principles v2 — draft for your eyes only",
              preview: "Theo shared \"Design Principles v2\" with you. He wants a read-through before it goes to the rest of the team on Thursday.",
              body: """
              Theo Andersen shared a Paper doc with you.

              Design Principles v2 — draft

              "Wanted you to see this before I send it out Thursday. Mostly a tightening pass on the existing five, plus one new one about restraint that I think you'll like."

              Open in Dropbox Paper →
              """,
              time: "Mon", day: "earlier",
              labels: ["team"], folder: "inbox"),
        // Personal account
        Email(id: "p01", account: "personal", from: "mom",
              subject: "Thanksgiving plans — what time should we say?",
              preview: "Dad and I are flexible. If you're driving up Wednesday night the guest room is yours. Otherwise Thursday morning is fine.",
              body: """
              Hi sweetie,

              Dad and I are flexible. If you're driving up Wednesday night the guest room is yours. Otherwise Thursday morning is fine.

              Let me know either way so I can plan the turkey timing. Also do you want me to invite Aunt Karen or is that going to be too much this year?

              Love,
              Mom
              """,
              time: "4:02 PM", day: "today", unread: true, starred: true, folder: "inbox"),
        Email(id: "p02", account: "personal", from: "spotify",
              subject: "Your 2026 Wrapped is here",
              preview: "Your year in music is ready. You listened to 47,832 minutes — that's 18% more than last year.",
              body: """
              Your 2026 Wrapped is ready.

              47,832 minutes listened
              · 18% more than 2025
              · Top genre: ambient
              · Top artist: Jon Hopkins
              · Top song: Singing Bowl (Ascension)

              Open Wrapped →
              """,
              time: "11:24 AM", day: "today", unread: true, folder: "inbox"),
        Email(id: "p03", account: "personal", from: "airbnb",
              subject: "Your Tokyo booking is confirmed · Apr 14–22",
              preview: "Your stay at \"Quiet machiya in Yanaka\" is confirmed. Check-in Apr 14 from 3:00 PM. The host sent a welcome note with arrival instructions.",
              body: """
              Your Tokyo booking is confirmed.

              Quiet machiya in Yanaka · Apr 14 – 22, 2026 · 8 nights
              Total: $1,840 USD

              Note from your host Hiroshi:
              "Welcome! The front gate code is in the arrival email. Recycling day is Wednesday. The cat next door is friendly but please do not feed her."

              View itinerary →
              """,
              time: "Yesterday", day: "yesterday", starred: true, folder: "inbox"),
        Email(id: "p04", account: "personal", from: "substack",
              subject: "3 new posts from your subscriptions",
              preview: "Robin Sloan published \"On waiting for the kettle\". Anne Helen Petersen published \"The weekly digest\". Maria Popova published \"Brain Pickings.\"",
              body: """
              3 new posts in your subscriptions today.

              Robin Sloan — On waiting for the kettle (8 min)
              Anne Helen Petersen — The weekly digest (15 min)
              Maria Popova — The chord of the universe (12 min)

              Open Substack →
              """,
              time: "Yesterday", day: "yesterday", folder: "inbox"),
        Email(id: "p05", account: "personal", from: "rei",
              subject: "Members-only spring sale — 20% off",
              preview: "Co-op members get 20% off one full-price item through Sunday. Use code MEMBER20 at checkout.",
              body: "Co-op members get 20% off one full-price item through Sunday. Use code MEMBER20 at checkout.",
              time: "Mon", day: "earlier",
              labels: ["receipt"], folder: "inbox"),
        // Freelance / side projects
        Email(id: "f01", account: "freelance", from: "lumen",
              subject: "Re: Brand refresh deck — a few notes",
              preview: "Loved the second direction. The logo lockup feels much more \"us\" than v1. A few small notes inline before we sign off.",
              body: """
              Hi,

              Loved the second direction. The logo lockup feels much more "us" than v1. A few small notes before we sign off:

              • The warm cream feels a touch too yellow on screen — can we cool it 3-5%?
              • The display weight on the wordmark is great. The italic alt feels less confident, can we drop it?
              • Business cards look 10/10, no changes needed.

              Otherwise we are good to go. Sending the deposit for the next phase today.

              Thanks!
              Elena
              """,
              time: "3:18 PM", day: "today", unread: true, starred: true, hasAttachment: true,
              labels: ["design"], folder: "inbox"),
        Email(id: "f02", account: "freelance", from: "squarespace",
              subject: "Invoice INV-204 paid · $4,500.00",
              preview: "Payment received from Lumen Coffee Co. for invoice INV-204. Funds will be deposited within 2 business days.",
              body: """
              Payment received.

              From: Lumen Coffee Co.
              Invoice: INV-204
              Amount: $4,500.00 USD

              Funds will arrive in your account within 2 business days.
              """,
              time: "Yesterday", day: "yesterday",
              labels: ["receipt"], folder: "inbox"),
        Email(id: "f03", account: "freelance", from: "rafael",
              subject: "Quick question about availability in Q3",
              preview: "Hey — we are putting together scope for a small marketing site refresh in July/Aug. Curious if you have any bandwidth.",
              body: """
              Hey,

              We are putting together scope for a small marketing site refresh in July or August. Just a few pages, nothing crazy. Probably 4–6 weeks of design.

              Curious if you have any bandwidth that window? Happy to send the brief once I hear back.

              Rafael
              """,
              time: "Mon", day: "earlier", folder: "inbox"),
        // Done
        Email(id: "d01", account: "work", from: "priya",
              subject: "Re: Cobalt × Northstar — kickoff notes",
              preview: "Thanks for the notes! All clear on our end. We'll send the asset pack on Monday.",
              body: "Thanks for the notes! All clear on our end. We'll send the asset pack on Monday.",
              time: "Mon", day: "earlier", folder: "done"),
        Email(id: "d02", account: "work", from: "apple",
              subject: "Your Apple Developer Program enrollment will renew",
              preview: "Your Apple Developer Program membership will automatically renew on June 14, 2026.",
              body: "Your Apple Developer Program membership will automatically renew on June 14, 2026.",
              time: "Sun", day: "earlier",
              labels: ["receipt"], folder: "done"),
        // Snoozed
        Email(id: "s01", account: "work", from: "anya",
              subject: "Re: Re: Quick chat about the Staff Design opening?",
              preview: "No worries at all — circling back next month. Snoozed until Jun 23.",
              body: "No worries at all. I'll circle back next month with anything new.",
              time: "Jun 23", day: "snoozed",
              labels: ["recruit"], folder: "snoozed", snoozeUntil: "Tomorrow morning"),
        // Sent
        Email(id: "t01", account: "work", from: "you",
              to: ["Sarah Chen"],
              subject: "Final pass for onboarding — for tomorrow's review",
              preview: "Hey Sarah — latest pass attached. Two open questions inside, would love your read before tomorrow.",
              body: "Hey Sarah — latest pass attached. Two open questions inside, would love your read before tomorrow.",
              time: "Yesterday", day: "yesterday", hasAttachment: true,
              labels: ["team"], folder: "sent"),
        Email(id: "t02", account: "work", from: "you",
              to: ["Marcus Liu"],
              subject: "Re: Spec questions: Reading pane spacing",
              preview: "Going with 32 / 56 / center. Let's ship it.",
              body: "32 between subject and body, 56 for collapsed composer, center the attachment row. Let's ship.",
              time: "Yesterday", day: "yesterday",
              labels: ["team"], folder: "sent")
    ]
}

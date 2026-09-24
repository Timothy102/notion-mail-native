import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Demo-mode data: a realistic inbox built by running every fixture through `MIME.build` and
/// `MIME.parse`, so demo mode exercises the same ingest path as real Gmail mail.
public enum Fixtures {
    public static let me = EmailAddress(name: "Tim Cvetko", email: "cvetko.tim@gmail.com")
    /// Demo accounts for the switcher: `me` first. Every one shows the same fixture mail.
    public static let accounts = [
        Account(email: me.email, name: me.name!),
        Account(email: "tim@helio.dev", name: "Tim Cvetko"),
        Account(email: "team@helio.dev", name: "Helio Team"),
    ]

    public static func seed(_ store: Store, now: Date = .now) throws {
        try store.save(account: Account(email: me.email, name: me.name!))
        try store.save(labels: labels)
        try store.save(sendAs: [
            SendAs(email: me.email, displayName: "Tim Cvetko",
                   signature: Signature.defaultHTML,
                   isDefault: true, isPrimary: true),
            SendAs(email: "tim@helio.dev", displayName: "Tim Cvetko (Helio)",
                   signature: "Tim Cvetko<br>Founder, Helio<br><a href=\"https://helio.dev\">helio.dev</a>",
                   isDefault: false, isPrimary: false),
        ])
        let d = Dates(now: now)
        var messages: [Message] = []
        var attachments: [Attachment] = []
        var drafts: [Draft] = []
        for (t, spec) in threads(d).enumerated() {
            let threadId = String(format: "19%014x", 0x5a1f00 + t * 7919)
            var previous: [String] = []
            for (i, m) in spec.messages.enumerated() {
                let id = String(format: "19%014x", 0x9b3e00 + t * 7919 + i * 131)
                var out = OutgoingMessage(
                    from: m.from, to: m.to, cc: m.cc,
                    subject: i == 0 ? spec.subject : MIME.prefixed(spec.subject.hasPrefix("Invitation") ? "Updated:" : "Re:", spec.subject),
                    text: m.text, html: m.html, inReplyTo: previous.last, references: previous,
                    attachments: m.attachments, date: m.date
                )
                out.messageId = "<\(id)@mail.gmail.com>"
                previous.append(out.messageId)
                let isLast = i == spec.messages.count - 1
                var labels: [String]
                if m.draft {
                    labels = ["DRAFT"]
                } else {
                    labels = spec.labels
                    if m.from.email == me.email { labels.removeAll { $0 == "INBOX" }; labels.append("SENT") }
                    if spec.unread && m.from.email != me.email && (isLast || i >= spec.messages.count - spec.unreadCount) { labels.append("UNREAD") }
                    if spec.starred && isLast { labels.append("STARRED") }
                }
                let root = MIME.parse(MIME.build(out))
                let (message, parts) = Message.make(id: id, threadId: threadId, labelIds: labels,
                                                    internalDate: Int64(m.date.timeIntervalSince1970 * 1000), snippet: nil, root: root)
                messages.append(message)
                attachments += parts
                if m.draft { drafts.append(Draft(id: "r-\(id)", messageId: id, threadId: threadId, updatedAt: m.date)) }
            }
        }
        try store.upsert(messages: messages, attachments: attachments)
        for draft in drafts { try store.save(draft: draft) }
    }

    public static let labels: [MailLabel] = [
        MailLabel(id: "Label_1", name: "Work", color: "blue"),
        MailLabel(id: "Label_2", name: "Finance", color: "green"),
        MailLabel(id: "Label_3", name: "Travel", color: "orange"),
        MailLabel(id: "Label_4", name: "Receipts", color: "yellow"),
        MailLabel(id: "Label_5", name: "Hiring", color: "purple"),
        MailLabel(id: "Label_6", name: "Investors", color: "red"),
        MailLabel(id: "Label_7", name: "Family", color: "pink"),
        MailLabel(id: "Label_8", name: "Newsletters", color: "gray"),
        MailLabel(id: "Label_9", name: "GitHub", color: "brown"),
    ] + ["INBOX", "SENT", "DRAFT", "SPAM", "TRASH", "STARRED", "UNREAD", "IMPORTANT"].map {
        MailLabel(id: $0, name: $0.capitalized, isSystem: true)
    }

    // MARK: - People

    private static func a(_ name: String, _ email: String) -> EmailAddress { EmailAddress(name: name, email: email) }
    private static let priya = a("Priya Raman", "priya@helio.dev")
    private static let marco = a("Marco Bellini", "marco@helio.dev")
    private static let zoe = a("Zoë Müller", "zoe@helio.dev")
    private static let jose = a("José García", "jose.garcia@fieldtrip.studio")
    private static let ana = a("Ana Kovač", "ana.kovac@gmail.com")
    private static let mom = a("Mama", "mojca.cvetko@siol.net")
    private static let yamada = a("山田 太郎", "t.yamada@kaizen-partners.jp")
    private static let marcus = a("Marcus Hale", "marcus@northstar.vc")
    private static let hannah = a("Hannah Lindqvist", "hannah@acmerobotics.io")
    private static let lukasz = a("Łukasz Nowak", "lukasz.nowak@proton.me")
    private static let sofia = a("Sofia Rossi", "sofia@helio.dev")
    private static let dan = a("Dan Okafor", "dan@helio.dev")
    private static let calendar = a("Google Calendar", "calendar-notification@google.com")
    private static let github = a("GitHub", "notifications@github.com")
    private static let dependabot = a("dependabot[bot]", "notifications@github.com")
    private static let stripe = a("Figma", "invoice+statements@figma.com")
    private static let notion = a("Notion", "notify@mail.notion.so")
    private static let aws = a("AWS Notifications", "no-reply@sns.amazonaws.com")
    private static let dalmatia = a("Dalmatia Air", "booking@dalmatia-air.example")
    private static let tap = a("TAP Air Portugal", "no-reply@flytap.com")
    private static let stack = a("The Sunday Stack", "hello@sundaystack.news")
    private static let moats = a("Margins & Moats", "letters@marginsandmoats.com")
    private static let arc = a("Arcadia Supply Co.", "hello@arcadia-supply.com")
    private static let metabase = a("Metabase", "reports@helio.metabaseapp.com")
    private static let northwind = a("Northwind Studio", "billing@northwind.studio")
    private static let swiftEvolution = a("Holly Borla via Swift Forums", "forums@swift.org")
    private static let bolt = a("Bolt", "receipts@bolt.eu")
    private static let google = a("Google", "no-reply@accounts.google.com")
    private static let landlord = a("Irena Zupan", "irena.zupan@gmail.com")
    private static let dentist = a("Zobna ordinacija Bežigrad", "narocanje@zobna-bezigrad.si")
    private static let hr = a("People Team", "people@helio.dev")
    private static let dhl = a("DHL Express", "noreply@dhl.com")
    private static let swiftIsland = a("Swift Island", "tickets@swiftisland.nl")
    private static let podcast = a("Rachel Kim", "rachel@shipitpod.fm")
    private static let accountant = a("Petra Novak", "petra@novak-racunovodstvo.si")
    private static let stripeVerify = a("Stripe", "verify@stripe.com")
    private static let triglav = a("Zavarovalnica Triglav", "e-dokumenti@triglav.si")

    // MARK: - Threads

    private struct M {
        var from: EmailAddress
        var to: [EmailAddress]
        var cc: [EmailAddress] = []
        var date: Date
        var text: String
        var html: String? = nil
        var attachments: [OutgoingAttachment] = []
        var draft = false
    }

    private struct T {
        var subject: String
        var labels: [String]
        var unread = false
        var unreadCount = 1
        var starred = false
        var messages: [M]
    }

    private struct Dates {
        let now: Date
        let cal = Calendar.current
        func minutesAgo(_ m: Int) -> Date { now.addingTimeInterval(-Double(m) * 60) }
        func day(_ daysAgo: Int, _ h: Int, _ m: Int = 0) -> Date {
            let start = cal.startOfDay(for: cal.date(byAdding: .day, value: -daysAgo, to: now)!)
            return cal.date(byAdding: .minute, value: h * 60 + m, to: start)!
        }
        /// Today, but never in the future: times after "3 minutes ago" squeeze into the last 3 minutes, in order,
        /// so a thread reads the same whatever time the demo (or a test) runs.
        func today(_ h: Int, _ m: Int = 0) -> Date {
            let date = day(0, h, m), cutoff = minutesAgo(3)
            guard date > cutoff else { return date }
            return cutoff.addingTimeInterval(Double(h * 60 + m) / 1440 * 170)
        }
        func nextWeekday(_ weekday: Int, _ h: Int) -> Date {
            let next = cal.nextDate(after: now, matching: DateComponents(hour: h, weekday: weekday), matchingPolicy: .nextTime)!
            return next
        }
    }

    private static func threads(_ d: Dates) -> [T] {
        let designReview = d.nextWeekday(5, 14)
        let swiftIslandDay = d.day(-26, 9)
        return [
            // MARK: Today
            T(subject: "Booking confirmed: Ljubljana → Split · DA 482", labels: ["INBOX"], unread: true, messages: [
                M(from: dalmatia, to: [me], date: d.today(7, 40),
                  text: "Booking reference 7HKQ2P. Ljubljana (LJU) → Split (SPU), DA 482, Fri 07:15. Seat 3C. Check-in opens 24h before departure.",
                  html: Self.airlineHTML(),
                  attachments: [OutgoingAttachment(filename: "boarding-qr.png", mimeType: "image/png",
                                                   data: gradientPNG(hue: 0.58, width: 180, height: 180), contentId: "qr-7HKQ2P@dalmatia-air")]),
            ]),
            T(subject: "Your Stripe verification code", labels: ["INBOX"], unread: true, messages: [
                M(from: stripeVerify, to: [me], date: d.now.addingTimeInterval(-5),
                  text: "Your verification code is 143819. It expires in 10 minutes. If you didn't try to sign in to Stripe, you can ignore this email."),
            ]),
            T(subject: "Your travel insurance ID card", labels: ["INBOX", "Label_3"], messages: [
                M(from: triglav, to: [me], date: d.today(8, 5),
                  text: "Dear Tim Cvetko, your travel insurance ID card is attached. Keep it on your phone: it's all you need at a doctor abroad.",
                  attachments: [OutgoingAttachment(filename: "IDCard_359W2K.pdf", mimeType: "application/pdf", data: idCardPDF())]),
            ]),
            T(subject: "Q4 roadmap: decisions needed before Friday", labels: ["INBOX", "Label_1"], unread: true, unreadCount: 2, messages: [
                M(from: priya, to: [me, marco, zoe], date: d.today(8, 12), text: """
                    Hi all,

                    Ahead of Friday's planning session I've pulled together the three decisions we still need to make for Q4:

                    1. Do we ship offline search in the 1.0, or hold it for 1.1?
                    2. Who owns the calendar integration after Sofia moves to platform?
                    3. Are we comfortable cutting the Windows beta to protect the macOS launch date?

                    The doc is in Notion under Product → Q4. Please leave comments inline so we can keep this thread short.

                    Thanks,
                    Priya
                    """),
                M(from: marco, to: [priya], cc: [me, zoe], date: d.today(8, 47), text: """
                    On (1): I'd ship it. The FTS index is already built during sync, so it's mostly UI work — maybe four days including tests.

                    On (3): agree with cutting Windows. Nobody on the beta list has asked about it in two months.

                    Marco
                    """),
                M(from: me, to: [priya, marco], cc: [zoe], date: d.today(9, 20), text: """
                    +1 to shipping offline search. It's the thing people notice first when switching from Gmail.

                    For (2) I can take calendar until we hire. Let's revisit in November.
                    """),
                M(from: zoe, to: [priya, marco, me], date: d.today(10, 5), text: """
                    Design-wise search is ready — the results view reuses the inbox row, so there's nothing new to review. I'll post the highlighted-match states in Figma this afternoon.

                    Small ask: can we keep the Windows beta list? I'd like to email them when we have a date.
                    """),
                M(from: priya, to: [zoe, marco, me], date: d.today(10, 38), text: """
                    Great — sounds like we have consensus on 1 and 3. Tim takes calendar for now.

                    Zoë, yes, let's keep the list. I'll write the email.
                    """),
                M(from: dan, to: [priya, zoe, marco, me], date: d.today(11, 2), text: """
                    Late to this, sorry. One risk on offline search: the index for large mailboxes (100k+ messages) is ~400 MB. We should cap the backfill window or make it a setting before we promise it in the release notes.
                    """),
            ]),
            T(subject: "Invitation: Design review @ \(Self.eventTitleDate(designReview)) (Tim Cvetko)", labels: ["INBOX", "Label_1"], unread: true, messages: [
                M(from: calendar, to: [me], date: d.today(9, 41), text: """
                    Zoë Müller has invited you to a meeting.

                    Design review
                    \(Self.eventTitleDate(designReview))
                    Location: Room Tivoli / Google Meet
                    Organizer: zoe@helio.dev

                    Agenda: sidebar v4, search results states, compose panel polish.

                    Going? Yes · Maybe · No
                    """,
                  html: Self.inviteHTML(title: "Design review", when: Self.eventTitleDate(designReview), organizer: "Zoë Müller"),
                  attachments: [Self.ics(summary: "Design review", start: designReview, minutes: 60, organizer: zoe, location: "Room Tivoli / Google Meet")]),
            ]),
            T(subject: "[helio/mail] Fix FTS5 tokenizer stripping diacritics in sender names (#412)", labels: ["INBOX", "Label_9"], unread: true, messages: [
                M(from: a("Marco Bellini", "notifications@github.com"), to: [a("helio/mail", "mail@noreply.github.com")], cc: [me], date: d.today(9, 58), text: """
                    @marco-b commented on this pull request.

                    > t.tokenizer = .unicode61(diacritics: .remove)

                    This fixes "Zoe" matching "Zoë", but it also means "resume" matches "résumé" in subjects. I think that's what people expect from search, so approving.

                    —
                    Reply to this email directly, view it on GitHub, or unsubscribe.
                    You are receiving this because you were mentioned.
                    """),
            ]),
            T(subject: "Your receipt from Figma #2231-5541", labels: ["INBOX", "Label_4"], messages: [
                M(from: stripe, to: [me], date: d.today(7, 3), text: "Receipt #2231-5541. Amount paid €54.00. Figma Professional — 2 editors, monthly. Paid with Visa •••• 4242.",
                  html: Self.receiptHTML(company: "Figma", number: "2231-5541", amount: "€54.00", item: "Figma Professional — 2 editors", period: "Monthly")),
            ]),
            T(subject: "Dinner Friday? 🍝", labels: ["INBOX", "Label_7"], starred: true, messages: [
                M(from: ana, to: [me], date: d.day(1, 19, 40), text: """
                    Hey! Luka and I are finally back from Split. Want to come over Friday? I'm making the tagliatelle from that place in Trieste.

                    Bring nothing. Or wine. Wine is good.
                    """),
                M(from: me, to: [ana], date: d.day(1, 21, 5), text: "Yes!! Count me in. What time? I'll bring the Movia you liked."),
                M(from: ana, to: [me], date: d.today(7, 50), text: "7:30 works. Door code is 2408 — see you Friday 🙌"),
            ]),
            T(subject: "Contract draft for the Tokyo partnership / 契約書ドラフト", labels: ["INBOX", "Label_1"], unread: true, messages: [
                M(from: yamada, to: [me], cc: [priya], date: d.today(6, 20), text: """
                    Dear Tim-san,

                    Thank you for the productive call last week. Please find attached the first draft of the partnership agreement, in English and Japanese.

                    We have marked the sections on data residency (§4) and support hours (§7) for your review. Our legal team would appreciate comments by the end of next week.

                    よろしくお願いいたします。

                    Taro Yamada
                    Kaizen Partners, Tokyo
                    """,
                  attachments: [Self.file("Partnership_Agreement_Draft_v1.pdf", "application/pdf", kb: 412),
                                Self.file("契約書_ドラフト_v1.pdf", "application/pdf", kb: 398)]),
            ]),
            T(subject: "The Sunday Stack #214: Local-first is having a moment", labels: ["INBOX", "Label_8"], unread: true, messages: [
                M(from: stack, to: [me], date: d.today(6, 0), text: """
                    This week: why local-first apps are back, a teardown of three email clients' sync engines, and the SQLite extension everyone is quietly shipping.
                    """, html: Self.newsletterHTML()),
            ]),

            // MARK: Yesterday
            T(subject: "Seed extension — term sheet comments", labels: ["INBOX", "Label_6"], starred: true, messages: [
                M(from: marcus, to: [me], date: d.day(1, 9, 15), text: """
                    Tim,

                    Attached is v3 of the term sheet with our comments. Two open items from our side:

                    • Pro-rata: we'd like to keep it for the next priced round.
                    • Board: fine with an observer seat instead of a full seat.

                    Everything else matches what we discussed. Happy to jump on a call Thursday.

                    Best,
                    Marcus
                    """, attachments: [Self.file("Helio_Term_Sheet_v3.pdf", "application/pdf", kb: 186)]),
                M(from: me, to: [marcus], date: d.day(1, 11, 30), text: """
                    Thanks Marcus — both items work for us. I'll send it to our lawyers today and come back by Wednesday.

                    Thursday at 4pm CET works for a call.
                    """),
                M(from: marcus, to: [me], date: d.day(1, 12, 2), text: "Perfect. Sent an invite for Thursday 4pm."),
            ]),
            T(subject: "Your flight to Lisbon is confirmed ✈️ — TP 1231", labels: ["INBOX", "Label_3"], messages: [
                M(from: tap, to: [me], date: d.day(1, 16, 22), text: "Booking reference QX7L2M. Ljubljana (LJU) → Lisbon (LIS), TP 1231, departs 07:05. Seat 14A. 1 checked bag.",
                  html: Self.flightHTML()),
            ]),
            T(subject: "Offsite venue options", labels: ["INBOX", "Label_1"], unread: true, messages: [
                M(from: jose, to: [me, priya], date: d.day(3, 10, 0), text: """
                    Hola! As promised, three venues for the October offsite:

                    1. Hiša Franko area guesthouse — 14 rooms, great food, 2h drive.
                    2. Lake Bohinj lodge — 18 rooms, meeting room with a view, 1h drive.
                    3. Piran old town apartments — split across two buildings, 1.5h drive.

                    Pricing is in the sheet. My vote is Bohinj.
                    """),
                M(from: priya, to: [jose, me], date: d.day(2, 9, 12), text: "Bohinj for me too. Can we check they have decent wifi? Last year was rough."),
                M(from: jose, to: [priya, me], date: d.day(2, 14, 40), text: "Asked — fibre, 300 Mbit, and they'll add an extra access point in the meeting room."),
                M(from: jose, to: [priya, me], date: d.day(1, 10, 3), text: "They're holding the dates until Thursday. Tim, can you confirm the budget so I can sign?"),
            ]),
            T(subject: "3 pages were updated in Product Wiki", labels: ["INBOX"], messages: [
                M(from: notion, to: [me], date: d.day(1, 8, 0), text: "Priya Raman edited Q4 Roadmap. Zoë Müller edited Search — result states. Marco Bellini created Offline search: tech plan.",
                  html: Self.notionDigestHTML()),
            ]),
            T(subject: "AWS Notification — Billing alert: estimated charges exceed $250", labels: ["INBOX", "Label_2"], messages: [
                M(from: aws, to: [me], date: d.day(1, 3, 14), text: """
                    You are receiving this email because your estimated charges are greater than the limit you set for the alarm "monthly-250" in AWS account 4410-2291-8830.

                    Alarm Details:
                    - Name: monthly-250
                    - State Change: OK -> ALARM
                    - Reason: Threshold Crossed: 1 datapoint [263.41 (22/09/26 03:00:00)] was greater than the threshold (250.0).
                    - Timestamp: Tuesday 22 September, 2026 03:14:09 UTC

                    View this alarm in the AWS Management Console.
                    """),
            ]),
            T(subject: "Zoë Müller commented on Mail — Sidebar v4", labels: ["INBOX", "Label_1"], messages: [
                M(from: a("Zoë Müller (via Figma)", "comments-noreply@figma.com"), to: [me], date: d.day(1, 15, 51), text: """
                    Zoë Müller replied to your comment in Mail — Sidebar v4:

                    "Agree the counts feel heavy. Tried textSecondary at 12 medium — much calmer. Updated frame 'Sidebar / default'."

                    Reply · View in Figma
                    """),
            ]),

            // MARK: Last 7 days
            T(subject: "Following up on our conversation about the platform migration timeline, staffing, budget approval and the open questions from legal", labels: ["INBOX", "Label_1"], unread: true, messages: [
                M(from: hannah, to: [me], date: d.day(3, 17, 30), text: """
                    Hi Tim,

                    Thanks again for the time on Monday. Summarizing where we landed so nothing gets lost:

                    Timeline — we'd start the migration in the second week of October and run both systems in parallel for 30 days.
                    Staffing — we'll dedicate two engineers; you mentioned one from your side for the first two weeks.
                    Budget — approved up to the amount in the proposal, pending the legal review.
                    Legal — our counsel had questions about data processing locations. I've forwarded them separately.

                    Let me know if I missed anything.

                    Hannah
                    """),
            ]),
            T(subject: "Candidate: Łukasz Nowak — onsite feedback", labels: ["INBOX", "Label_5"], messages: [
                M(from: sofia, to: [me, marco, dan], date: d.day(4, 16, 0), text: "Please drop your feedback for Łukasz here by tomorrow noon. Scorecards are in Ashby too."),
                M(from: marco, to: [sofia], cc: [me, dan], date: d.day(4, 17, 20), text: "Strong yes. Best systems-design session I've seen this year — he found the sync race on his own."),
                M(from: dan, to: [sofia], cc: [me, marco], date: d.day(4, 18, 5), text: "Yes. Slightly worried about SwiftUI depth, but he learns fast and asked great questions."),
                M(from: me, to: [sofia], cc: [marco, dan], date: d.day(3, 9, 10), text: "Yes from me. Let's move quickly — he mentioned another offer."),
                M(from: sofia, to: [me, marco, dan], date: d.day(3, 11, 45), text: "Offer is out 🎉 He'll reply by Friday."),
            ]),
            T(subject: "🔥 48 hours only: 40% off annual plans", labels: ["INBOX", "Label_8"], messages: [
                M(from: arc, to: [me], date: d.day(4, 12, 0), text: "Our biggest sale of the year. 40% off all annual plans, ends Sunday at midnight.",
                  html: Self.promoHTML()),
            ]),
            T(subject: "Photos from the weekend 📸", labels: ["INBOX", "Label_7"], messages: [
                M(from: ana, to: [me, a("Luka Kovač", "luka.kovac@gmail.com")], date: d.day(5, 20, 14), text: "Some of the best ones from Velika planina. The cows were very photogenic.",
                  attachments: [Self.photo("IMG_4021.png", hue: 0.33), Self.photo("IMG_4033.png", hue: 0.58), Self.photo("IMG_4047.png", hue: 0.08)]),
            ]),
            T(subject: "[helio/mail] Bump GRDB.swift from 7.8.0 to 7.9.0", labels: ["INBOX", "Label_9"], messages: [
                M(from: dependabot, to: [a("helio/mail", "mail@noreply.github.com")], date: d.day(5, 6, 30), text: """
                    Bumps GRDB.swift from 7.8.0 to 7.9.0.

                    Release notes
                    - New: ValueObservation scheduling improvements
                    - Fixed: FTS5 synchronization with renamed columns

                    Dependabot will resolve any conflicts with this PR as long as you don't alter it yourself.
                    """),
            ]),
            T(subject: "Invoice INV-2026-0917 from Northwind Studio", labels: ["INBOX", "Label_2"], unread: true, messages: [
                M(from: northwind, to: [me], date: d.day(6, 10, 10), text: """
                    Hi Tim,

                    Please find attached invoice INV-2026-0917 for brand illustration work in August (€3,400.00), due in 30 days.

                    Bank details are on the invoice. Thank you!

                    Northwind Studio
                    """, attachments: [Self.file("INV-2026-0917.pdf", "application/pdf", kb: 94)]),
            ]),
            T(subject: "[Pitch] SE-0471: Improved custom SerialExecutor isolation checking", labels: ["INBOX", "Label_8"], messages: [
                M(from: swiftEvolution, to: [a("Swift Forums", "forums@swift.org")], date: d.day(6, 22, 48), text: """
                    Hello Swift community,

                    The review of SE-0471 "Improved Custom SerialExecutor isolation checking for Concurrency Runtime" begins now and runs through October 6.

                    Reviews are an important part of the Swift evolution process. All review feedback should be either on this forum thread or, if you would like to keep your feedback private, directly to the review manager via the forum messaging feature.

                    What goes into a review?
                    - What is your evaluation of the proposal?
                    - Is the problem being addressed significant enough to warrant a change to Swift?
                    - Does this proposal fit well with the feel and direction of Swift?

                    Thank you,
                    Holly Borla
                    Review Manager
                    """),
            ]),
            T(subject: "Intro — Tim <> Hannah (Acme Robotics)", labels: [], messages: [
                M(from: marcus, to: [me, hannah], date: d.day(6, 9, 0), text: "Tim, meet Hannah — she runs platform at Acme Robotics and is looking at exactly the problem Helio solves. Hannah, meet Tim. I'll let you two take it from here!"),
                M(from: me, to: [hannah], cc: [marcus], date: d.day(6, 10, 30), text: "Thanks Marcus (to bcc). Hannah — great to meet you. Would Monday at 3pm CET work for a first call?"),
            ]),
            T(subject: "Weekly metrics — week 38", labels: ["INBOX", "Label_1"], messages: [
                M(from: metabase, to: [me], date: d.day(2, 7, 0), text: "Weekly active users 4,812 (+6.2%). Threads triaged 118k. Median search latency 38 ms.",
                  html: Self.metricsHTML()),
            ]),

            // MARK: Last 30 days
            T(subject: "Apartment lease renewal — Trubarjeva 12", labels: ["INBOX", "Label_2"], starred: true, messages: [
                M(from: landlord, to: [me], date: d.day(9, 11, 0), text: """
                    Pozdravljeni Tim,

                    the current lease ends on 31 October. I'm happy to renew for another year at the same rent. The renewal contract is attached — please sign and send back when convenient.

                    Lep pozdrav,
                    Irena Zupan
                    """, attachments: [Self.file("Najemna_pogodba_2026.pdf", "application/pdf", kb: 240)]),
                M(from: me, to: [landlord], date: d.day(8, 18, 20), text: "Hvala Irena! Signed copy attached. Enjoy the rest of the week."),
            ]),
            T(subject: "Opomnik: pregled v torek ob 8:30", labels: ["INBOX"], messages: [
                M(from: dentist, to: [me], date: d.day(10, 13, 0), text: "Spoštovani, spominjamo vas na pregled v torek ob 8:30. Če termin ne ustreza, nas pokličite na 01 234 56 78. Lep pozdrav, Zobna ordinacija Bežigrad"),
            ]),
            T(subject: "Your Tuesday evening trip with Bolt", labels: ["INBOX", "Label_4"], messages: [
                M(from: bolt, to: [me], date: d.day(11, 22, 41), text: "Thanks for riding with Bolt. Total €8.40. Prešernov trg → Trubarjeva 12, 3.1 km, 11 min.",
                  html: Self.receiptHTML(company: "Bolt", number: "BT-88120", amount: "€8.40", item: "Ride · Prešernov trg → Trubarjeva 12", period: "Tue 22:30")),
            ]),
            T(subject: "Swift Island 2026 — your ticket 🎟️", labels: ["INBOX", "Label_3"], messages: [
                M(from: swiftIsland, to: [me], date: d.day(13, 14, 0), text: """
                    Hi Tim, you're all set for Swift Island 2026 on Texel!

                    Your ticket is attached, along with a calendar file for the three days. Ferry times and the workshop schedule will follow two weeks before the event.
                    """, attachments: [Self.file("SwiftIsland2026-Ticket.pdf", "application/pdf", kb: 128),
                                       Self.ics(summary: "Swift Island 2026", start: swiftIslandDay, minutes: 3 * 24 * 60, organizer: swiftIsland, location: "Texel, Netherlands")]),
            ]),
            T(subject: "Security alert: new sign-in on Mac", labels: ["INBOX"], messages: [
                M(from: google, to: [me], date: d.day(14, 8, 12), text: "A new sign-in on Mac. cvetko.tim@gmail.com. We noticed a new sign-in to your Google Account on a Mac device. If this was you, you don't need to do anything. If not, we'll help you secure your account.",
                  html: Self.securityHTML()),
            ]),
            T(subject: "Welcome to the team, Sofia!", labels: ["INBOX", "Label_1"], messages: [
                M(from: hr, to: [a("Everyone", "everyone@helio.dev")], date: d.day(15, 9, 0), text: "Please welcome Sofia Rossi, who joins us as Head of People. Sofia was previously at Bending Spoons and lives in Milan."),
                M(from: priya, to: [a("Everyone", "everyone@helio.dev")], date: d.day(15, 9, 20), text: "Welcome Sofia!! 🎉 So happy you're here."),
                M(from: zoe, to: [a("Everyone", "everyone@helio.dev")], date: d.day(15, 10, 2), text: "Benvenuta! Coffee this week?"),
                M(from: sofia, to: [a("Everyone", "everyone@helio.dev")], date: d.day(15, 12, 30), text: "Thank you all — what a welcome. I'll be setting up 1:1s with everyone over the next two weeks."),
            ]),
            T(subject: "Board deck — v2 for review", labels: ["INBOX", "Label_6"], messages: [
                M(from: priya, to: [me], date: d.day(16, 18, 0), text: "v2 attached. Changed the metrics slide to cohort retention and cut the competitor slide. Can you review the narrative on slides 3–5?",
                  attachments: [Self.file("Helio_Board_Q3_v2.pptx", "application/vnd.openxmlformats-officedocument.presentationml.presentation", kb: 2_310)]),
                M(from: me, to: [priya], date: d.day(16, 21, 40), text: "Reviewed — left comments. Slide 4's chart needs the y-axis labelled; otherwise it's great."),
                M(from: priya, to: [me], date: d.day(15, 8, 5), text: "Fixed, thanks. Sending to the board tonight."),
            ]),
            T(subject: "Why vertical SaaS keeps winning", labels: ["INBOX", "Label_8"], messages: [
                M(from: moats, to: [me], date: d.day(17, 7, 0), text: """
                    Every few years someone declares horizontal software dead. It never is — but the best businesses of the last decade kept being boringly vertical.

                    This week: three case studies, a framework for spotting vertical wedges, and why the next wave looks like services with software margins.
                    """),
            ]),
            T(subject: "Podcast guest spot 🎙️", labels: ["INBOX"], unread: true, messages: [
                M(from: podcast, to: [me], date: d.day(19, 16, 12), text: """
                    Hi Tim,

                    I host Ship It, a podcast about small teams building ambitious products. We'd love to have you on to talk about rebuilding email for keyboard-first people.

                    We record remotely, about 45 minutes. Any Tuesday or Wednesday in October works on our side.

                    Rachel
                    """),
            ]),
            T(subject: "Delivered: Keychron Q1 Max", labels: ["INBOX", "Label_4"], messages: [
                M(from: dhl, to: [me], date: d.day(20, 13, 30), text: "Your shipment 1Z 999 AA1 01 2345 6784 was delivered at 13:24 and left at the front door."),
            ]),
            T(subject: "Recept za štruklje 🥟", labels: ["INBOX", "Label_7"], messages: [
                M(from: mom, to: [me], date: d.day(22, 19, 0), text: """
                    Tim,

                    tukaj je recept, ki si ga želel:

                    – 500 g moke, 1 jajce, ščep soli, mlačna voda
                    – nadev: 500 g skute, 2 jajci, 2 žlici kisle smetane, drobtine

                    Testo naj počiva vsaj pol ure. Kuhaj 20 minut v slanem kropu.

                    Objem,
                    mama
                    """),
            ]),
            T(subject: "Proposal: shared on-call rotation", labels: [], messages: [
                M(from: me, to: [marco, dan], date: d.day(1, 22, 10), text: """
                    Draft —

                    I'd like to move to a weekly rotation with a secondary. Primary gets Friday afternoon off after their week.
                    """, draft: true),
            ]),
            T(subject: "Re: Podcast intro questions", labels: ["INBOX"], messages: [
                M(from: podcast, to: [me], date: d.day(12, 11, 0), text: "Here are the intro questions for the episode — no prep needed, just a heads-up on where we'll start."),
                M(from: me, to: [podcast], date: d.today(7, 30), text: "Thanks Rachel! A couple of thoughts on question 3 —", draft: true),
            ]),

            // MARK: Earlier this year
            T(subject: "Tax documents 2025 are ready", labels: ["INBOX", "Label_2"], messages: [
                M(from: accountant, to: [me], date: d.day(120, 10, 0), text: "Pozdravljeni, the annual tax documents for 2025 are ready for your signature. I've uploaded them to the shared folder. Rok za oddajo je 31. maj.",
                  attachments: [Self.file("Dohodnina_2025.pdf", "application/pdf", kb: 310)]),
            ]),
            T(subject: "Kickoff: Mail rebuild", labels: ["INBOX", "Label_1"], messages: [
                M(from: me, to: [priya, marco, zoe, dan], date: d.day(150, 9, 0), text: """
                    Team — we're rebuilding the mail client natively. Goals, in order: it has to feel instant, it has to be keyboard-first, and it has to look calm.

                    First milestone: sign in, sync, and render the inbox. Let's aim for four weeks.
                    """),
                M(from: zoe, to: [me, priya, marco, dan], date: d.day(150, 9, 40), text: "Love it. I'll start with the design tokens so we have a spec before anyone writes a view."),
            ]),
            T(subject: "Your Q1 report is ready", labels: ["INBOX", "Label_6"], messages: [
                M(from: marcus, to: [me], date: d.day(170, 15, 0), text: "Congrats on a strong quarter. Our portfolio report is attached — Helio's section is on page 6."),
            ]),
            T(subject: "Apartment viewing — Trubarjeva 12", labels: ["Label_2"], messages: [
                M(from: landlord, to: [me], date: d.day(200, 12, 0), text: "The apartment is available for viewing on Saturday at 11. Let me know if that works."),
                M(from: me, to: [landlord], date: d.day(200, 14, 30), text: "Saturday at 11 works — see you then."),
            ]),

            // MARK: Last year
            T(subject: "Happy holidays from the Helio team 🎄", labels: ["INBOX"], messages: [
                M(from: hr, to: [a("Everyone", "everyone@helio.dev")], date: d.day(275, 16, 0), text: "The office is closed from 24 December to 2 January. Thank you for an incredible year — rest well!"),
            ]),
            T(subject: "Your 2025 year in review", labels: ["INBOX", "Label_8"], messages: [
                M(from: a("Strava", "no-reply@strava.com"), to: [me], date: d.day(290, 9, 0), text: "1,284 km run. 42 activities with friends. Your longest run: 32.4 km along the Sava."),
            ]),
            T(subject: "Lisbon trip — ideas?", labels: ["Label_3"], messages: [
                M(from: me, to: [ana], date: d.day(320, 20, 0), text: "Planning a few days in Lisbon in the spring. Any places I shouldn't miss?"),
                M(from: ana, to: [me], date: d.day(319, 8, 10), text: "Time Out Market is touristy but fun. Go to Cervejaria Ramiro for seafood, and walk up to Miradouro da Senhora do Monte at sunset."),
            ]),

            // MARK: Trash
            T(subject: "Last chance: webinar on inbox zero", labels: ["TRASH"], messages: [
                M(from: arc, to: [me], date: d.day(8, 12, 0), text: "Join our live webinar tomorrow at 5pm CET."),
            ]),
        ] + extraInbox(d) + quotedThreads(d)
    }

    /// Back-and-forth where every reply quotes the whole previous message, so the last one nests three
    /// levels deep: once as Gmail HTML (`gmail_quote`), once as plain text (`>` lines).
    private static func quotedThreads(_ d: Dates) -> [T] {
        func quoting(_ messages: [M], html: Bool) -> [M] {
            var out: [M] = []
            for var m in messages {
                let typed = m.text
                if html { m.html = "<div dir=\"ltr\">" + Quote.html(fromText: typed) + "</div>" }
                if let prev = out.last {
                    let attribution = Quote.attribution(date: prev.date, sender: prev.from)
                    m.text = typed + "\n\n" + Quote.replyText(attribution: attribution, body: prev.text)
                    if html { m.html! += "<br>" + Quote.replyHTML(attribution: attribution, bodyHTML: prev.html!) }
                }
                out.append(m)
            }
            return out
        }
        return [
            T(subject: "Brand refresh: timeline and next steps", labels: ["INBOX", "Label_1"], messages: quoting([
                M(from: jose, to: [me], date: d.day(5, 9, 14), text: "Hi Tim,\n\nGreat call yesterday. Proposed timeline: moodboards on the 3rd, two logo routes on the 10th, final files by the 24th.\n\nDoes that work on your side?\n\nJosé"),
                M(from: me, to: [jose], date: d.day(5, 11, 2), text: "Hi José,\n\nWorks for us. Could we see the moodboards a couple of days earlier? Our investor update goes out on the 2nd.\n\nTim"),
                M(from: jose, to: [me], date: d.day(5, 15, 40), text: "We can do the 1st if we skip the second photo route. Want me to go ahead?"),
                M(from: me, to: [jose], date: d.day(4, 8, 55), text: "Yes, go ahead and skip it. Thanks!"),
            ], html: true)),
            T(subject: "Talk proposal for Swift Ljubljana", labels: ["INBOX"], messages: quoting([
                M(from: lukasz, to: [me], date: d.day(9, 18, 20), text: "Hey Tim,\n\nWould you give a 25-minute talk at the November meetup? Something about building a native mail client would be perfect.\n\nŁukasz"),
                M(from: me, to: [lukasz], date: d.day(9, 21, 5), text: "Happy to! Working title: \"SQLite, SwiftUI and 40,000 emails\". Is there a projector with USB-C?"),
                M(from: lukasz, to: [me], date: d.day(8, 9, 30), text: "Love the title. Yes, USB-C and HDMI. Can you send a two-line abstract by Friday?"),
                M(from: me, to: [lukasz], date: d.day(8, 12, 45), text: "Abstract: how a local-first mail client stays fast with a full-text index, and what SwiftUI still makes hard. Live demo included."),
            ], html: false)),
        ]
    }

    /// Shorter one- or two-message threads that round out a believable inbox.
    private static func extraInbox(_ d: Dates) -> [T] {
        let one: [(EmailAddress, String, String, Int, Int, [String], Bool)] = [
            (a("Linear", "notifications@linear.app"), "HEL-482 Search results: highlight matched terms was assigned to you", "Priya Raman assigned HEL-482 to you. Priority: High. Cycle 14.", 0, 11, ["INBOX", "Label_1"], true),
            (a("Vercel", "notifications@vercel.com"), "Deployment failed for helio-web (main)", "Build failed: Type error in app/pricing/page.tsx:42 — Property 'annual' does not exist on type 'Plan'.", 2, 16, ["INBOX", "Label_9"], false),
            (a("Revolut Business", "no-reply@revolut.com"), "Card payment of €1,249.00 to Apple Store", "A payment of €1,249.00 was made with your card ending 8812 at Apple Store Ljubljana.", 3, 12, ["INBOX", "Label_2"], false),
            (a("Calendly", "notifications@calendly.com"), "New event: Rachel Kim — Podcast prep (30 min)", "Rachel Kim scheduled Podcast prep on Wednesday at 10:00 CET.", 4, 9, ["INBOX"], true),
            (a("Hacker Newsletter", "kale@hackernewsletter.com"), "Hacker Newsletter #712", "The best of Hacker News this week: SQLite as an application file format, the cost of a URL, and more.", 5, 7, ["INBOX", "Label_8"], false),
            (dan, "Postmortem: sync stalled for 40 minutes on Tuesday", "Root cause: a history id older than 7 days returned 404 and we retried instead of falling back to a full sync. Fix is merged.", 7, 15, ["INBOX", "Label_1"], false),
            (a("Airbnb", "automated@airbnb.com"), "Reservation confirmed — Bohinj lodge, Oct 14–17", "Your reservation is confirmed. Check-in after 15:00. Host: Matej.", 8, 11, ["INBOX", "Label_3"], false),
            (a("1Password", "hello@1password.com"), "Your Watchtower report", "2 weak passwords, 1 reused password and 0 compromised websites.", 18, 8, ["INBOX"], false),
            (a("Slovenske železnice", "info@slo-zeleznice.si"), "Vozovnica: Ljubljana → Koper, sobota 9:40", "Hvala za nakup. Številka vozovnice: 88213-449.", 24, 18, ["INBOX", "Label_3"], false),
            (zoe, "Icon set v2 — feedback welcome", "Redrew the sidebar icons at 16pt on a 1.25 stroke. Figma link inside; comments by Thursday please.", 26, 10, ["INBOX", "Label_1"], false),
            (a("Apple Developer", "developer@insideapple.apple.com"), "Your app has completed review", "Helio Mail 1.0 (42) for macOS has completed review and is ready for distribution.", 60, 14, ["INBOX"], false),
            (a("Figma", "no-reply@figma.com"), "Config 2026 recap: everything we announced", "Catch up on the keynote, new features, and the sessions you missed.", 95, 17, ["INBOX", "Label_8"], false),
            (a("Hetzner", "billing@hetzner.com"), "Invoice R0021934411", "Your invoice for September is available in the Hetzner Console. Amount: €38.62.", 34, 6, ["INBOX", "Label_4"], false),
            (sofia, "Performance review cycle starts Monday", "Self-reviews are due in two weeks. The template is in Notion.", 40, 9, ["INBOX", "Label_5"], false),
            (a("Google Workspace", "workspace-noreply@google.com"), "Your storage is almost full", "You've used 28.4 GB of 30 GB. Free up space or upgrade to keep receiving email.", 330, 10, ["INBOX"], false),
        ]
        return one.map { from, subject, text, days, hour, labels, unread in
            T(subject: subject, labels: labels, unread: unread, messages: [M(from: from, to: [me], date: days == 0 ? d.today(hour, 17) : d.day(days, hour, 17), text: text)])
        }
    }

    // MARK: - Attachments

    /// A one-page PDF shaped like an insurance card, so Quick Look has something real to show.
    static func idCardPDF() -> Data {
        let out = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 324, height: 204)
        guard let consumer = CGDataConsumer(data: out as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return Data() }
        ctx.beginPDFPage(nil)
        ctx.setFillColor(red: 0.07, green: 0.3, blue: 0.55, alpha: 1)
        ctx.fill(box)
        ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 0.9)
        ctx.fill(CGRect(x: 20, y: 150, width: 120, height: 16))
        for (i, width) in [180, 140, 160].enumerated() {
            ctx.fill(CGRect(x: 20, y: 90 - i * 22, width: width, height: 9))
        }
        ctx.endPDFPage()
        ctx.closePDF()
        return out as Data
    }

    /// Favicons for a few fixture brands, so demo rows show real-looking avatars without the network.
    public static let brandLogos: [String: String] = [
        "figma.com": "iVBORw0KGgoAAAANSUhEUgAAAIAAAACACAMAAAD04JH5AAAA2FBMVEUAAAD/Nzf/cjeHT/8ky3EAtv8ivmoAq+8Uc0AACxAAn9/vMzN/Su8AiL8ALkACDQcAW39MLZDvazPfZDDfMDCQHx+QQR8IBRAAk892Rd8AFyAAUHAgsWMARWAAcp8dpVwXf0cbmFUSZjgQBARADg7PLS2/VilgKxVgFRVwMhggBweAORtQERFAHQ6/KiqAHBwiFEAAfq8zHmARCiAqGVBEKIAFGQ4JMxwLQCMQWTEOTCpQJBIgDwdvGBifIiKfSCLPXSxtQM8AZo87I28AOVBUMZ9lPL8AIzB2djcmAAACzUlEQVR4nO2XW3vSQBRFYzBAUORSoci1QFu1tKW1pVy02lqt//8fGQpVvjBn44c7Z7zMfs3DWjOZk9nxPBcXFxcXFxcXl78o/f3KwbMnsfixlA+r7xPCD9fgJoF5dgYf+PxrI94sECm8ZvMrZrwk4PtVLv+jxBcF/E9Mvrh+IMDcgzcyHwj4b1n8o5fbCZT7JIEh4CMBf0ASQBsABUhbcIz4UMA/oQiAEdgkwBmE0+0FbigCwjf4VwTKFAHIxwL+vyFg/RUcbC9wSBGwPob72wtwylkfHgLE36Hw/4DLCG4B2gBaNb3eToBYTG1XMvul1H4tj4qp0IvM+DKtkP7M0dCoYMQPWHU0luPK6eaf05vqSUJ4b/esdPs8FcuPp2GrXcsEQSb/+UVC+NEafEUgLEbwx+RaCfDvjPhHgcYK/kHhC5tfMuMXAuF5sJYil/9V4s8Fwto6n2wgrv9BwLB+ssE7mR8JFM38IKBNw8UrJFCX+EGOJTAC/JTXFgUC1jSiDUjJGxAEeQ7/EvFTLSBAOgVgBKLkkUCDInAPBTJIoE0REL7ByyB+UKMIQD4W4AyidYHfeAWcObyFAvAQnlME8BgKN9EinDE8gwINJPCNIrALD0EI+KzbyPplBLfAq4vHkHYde3dIwBNPAbGe40om3EfUUmi7lNqv5VExFXrR4mkx/mOSwO/ZxciosHxab68oZIohnz/PZel+489pLrGfU88rjLOd9NNYkoIZ8L01uKrA1IjXE8ia8WoCexJfSUBcv5LATOarCFw1LQv0AF9FAG2AhsAE8TUEwAjoCHRtCwjfYD0ByP8vBOArSCsIdJBAV0EAjmFWQWCMBCYKAgVwCJoKfHgZ9VQE5C1oXqkIeFNJYKbDFwdBYwSWMZbSPT2+cQ8U1z/PLNaL0lNdflRNeysK6V5Bmz/PJNuNJjLdyY6t4F1cXFxcXFxcXJLJd700Sc+3yH7uAAAAAElFTkSuQmCC",
        "notion.so": "iVBORw0KGgoAAAANSUhEUgAAAIAAAACACAMAAAD04JH5AAAAZlBMVEX///8AAADS0tJQUFCampo/Pz9kZGSsrKyoqKj19fXd3d3x8fHZ2dnr6+ulpaXPz8+ysrIxMTHk5OS/v79paWlYWFi5ubl0dHQiIiKMjIyGhobIyMh8fHxGRkYWFhYsLCwODg44ODi+YdwDAAAD/0lEQVR4nO2abcOqIAyGM03T1HzNTLP6/3/y2FOaDEyGuD4c748J7AJsG7jNZtWqVatWrdKnQ+JX0T4M92lAZjPwticnvBT2tTGGOkeLmXxN06qz/GZ8U7PVZtJNvONrmrv7V5tAl3nTTKOwnJzmd50TNevOboZRVqGCefesOF3TLsrQSbfta1n2b+TVRQPE0ibvOzu7WM6p8hLOTNVPI0XaP321GedZbe2jyk8OUwOVXZ8MB2ALVzZqVxbrXI79GD6mW9/rIlpZnMxurFIB4DrP9kthv3WTO8YBGI4OgqRBD/fZfeTLM6KiGy5HAxjxzFfgpbQfr8ICGIaWeHLoHWuNBlBypV/GbCSCA3ADai9C0MbPtI3ZbQA12Wi2xwIYN4k/0CHxtq29sCyyfNfAEVgVWADD4HIbN/D8qk0Q2mhtX9Ghy0IDGOcySt8LmsuHqjHd8QCa9Z8CxH1gogGIc7u4WHsnbUNq8Hao2XIA98fLXpQeW3tTQ88HaB55JmGP020GQP5nb+tNZ2JfZKoDKOb32gAwGdUiAHKBfEEATcfMFeAXAG2m8EksqQASNlP45OPaAdrEZJs6Hvi1Bp0/+YwmAL/NTDJ7kHmx/VPYWfcWwMMrdFMF88y2Bk5UC8Be8JjZhFOR94sD0j8tAFfB4zM3SLgcgOgxn+g6ywEcvO0p4m7OYLRcEOBP3C3a7dcA0BQ9gMFmZj8AePwagD32/gLAGKarPwEYXqsRAYCT8uAYTwRQlGyzT9wjArBB489FHBlAxbY7kQPA7IAewGUb2uQAnalOKTkA9An0AAHbtCAH2Fhs2yM5wAZcVdID+GzjmhwAnoV8cgDQp6EHAMexkhxgk7Ptk4gaAHjkBzkA9Mg3cgBxlkYJEIj6UQJAj0wPAD0yPYDP96MF4G6nyAH4rkoAokohSQDugkwJIIOjyANAj6wGICpikQUAHlkNQPQSyAJAj6wGILgJHAEQfFlnPbIawIavHhs7nufWETxhPbIiQDIF4A4RY7Zmjlk/RQC4kyzAsQQ+F2zE8K5YFYC7kB4AcHAG/JLY/xfPsIpMHgAGlgEA9FM1X2nj3P52hv/IgAAIRgFi0y5qK3ROle8Fo2U+4gcIAOBVST9avVUvAHDFAGwe+gEMFICrHcDHAQzqETVVdDVIgEGaCR2uvNy+puoTquV793Un0hVl7xKnvVUXtjlWcoTg77rwX6VeOiSen0bIkqoYAeB1nR7Ht71nyZj1tLdTrD5GFnzznn++4Kfe7xJliPOErXhXXukRTdcTAgkPnUo6X+0SW+b9FJfsyyruqqtmVh8Jj73iCWZ1ORWnlRQJDT50TVAKochNs53gKxFJNE9w1apVq1at+rX+AZWnOuBOYxBWAAAAAElFTkSuQmCC",
        "stripe.com": "iVBORw0KGgoAAAANSUhEUgAAAIAAAACACAMAAAD04JH5AAAAJ1BMVEVHcExONu5UOv5TOftTOv7///9MLv34+P9fSf49Ev7W0/+tpf+Fd/5IiRS5AAAABHRSTlMAOdeWTzzdLAAAAchJREFUeJzt21GagyAMBGCpGFF7//Mugeq23a61Epg+TC4wfyD0oX7puq2c6y++QV1657q/1Sh9Mzzn9+3Sc/WP7Tfsfq2Lw+bfCzD5dwJQfhSA5u+30iQ6XL73DnsA6QhQE5grziH0BvQOoDegdwC9AX2J2HzvCSCAAAIIIICAqgCJNaEAMk3iw3WZxyDNATF8kpg9j8MwtAVIalyzY7LGtwSk8LA2vlUTgA7bi+w2gFvfy4vs6gA99ClN+j/hFQF65vmVDdu4NQNo3z4sqfG96AoASbU2fqzMAE+v7LDABLCF7952HcDDtJ2pIoDkV3Y6vPwEtPETx24FkFAUbQEoa54AAggggAACCCCAAAIIIIAAAggggAACcoEB4wwDjOO8XK/6RysAkMKDj+n78TUAKdvrhzvx79KtAfnQ8zfLo2UGGGdtPH3QOBxuBUjZ4fCh2wLWYfvg0K0AedBlej/oFQD50OXcoRcC1sY/HTYLwPrTdv7CSwD50A/8tNkCtgu//bTZ1/5Hq1D8ygoB4s2G7RygQRFAAAEEEEAAAfglF/iaD3zRCb7qBV92w6/7wRce8Suf+KVX+NovfvEZv/r9BcvvHWr9/we+9RME8MgsBQAAAABJRU5ErkJggg==",
        "google.com": "iVBORw0KGgoAAAANSUhEUgAAAIAAAACACAMAAAD04JH5AAAAt1BMVEVHcEz9/v7w8PHz8/T29/f29vf19fb8+/vr7O38/f329/f19fX29vf6+vr+/v755uX////x8vI5iBT///85qldGiPX7wBQ8rFpJivTrUELrTUDsUUTrSz7rT0I+hPTu8vIvqFBMjPWUtvj8vgbN3fz5y8fuZFXT69lVtGrrQzTzmpG84MVzwYaUzqPxfXD2rqn83IN+qff+7L38zkZpnfb2nCY9npTMuyqWtD4zgPRCkc5/tdRHcEwgFdBcAAAAPXRSTlMA8C0eiU6g/g3jdcBiO9H9qdH///////////////////////////////////////////////////////8AWkw1vQAAB9FJREFUeJztW+l2okgYHVkscOeoEAWExKiIolk6nXTP+7/XVAFGKL5aQJIfc3LTSTrniPf67VUU//zzg2YwVGU4HOop8H8U1fhG7qE+6HX7I7PTQVMM1OmYo363N9CH36BCGWiTUWcKojOaaAPlK9nVHpO8IKKnfhG9PjEF7LkGc6J/Ab1mIhn2DMjstctu9Gqw5xp67UWk0pMyPY1OS8GgDkZN6AlGgxYk6JOm9AQ3h6OqmbfwT6emdpMRhv3b6An6w+b8gxs/fgZz0JDe6NbOPQa0RhmptmD+C/oNAkFpnHwQRrV71LAV919h1lSgt8yPFdSqCO3zYy/UUDCU8H+w2ZzPcYrzebMJJBRIFwRh/KFNfNput+7C87y95/ku/uN03oiyti8ZB6L828SEekng+376Gwvxlu423vCvnEhlo8HtPkHs7j1MvCDwLwJyEfu9e+aaoStTkXrs69E49vYZ94X/KiDX4J/HHA0Sg9KQffn4vPUW7oItIJOwPY+Zb9ERBqLBTEB0PmE/u0IBGCd2PJoiJzADYBy7hL7Azxawd2OmEbp8/gFL+uaErQ8IWEIClt7+xEwIbj0yWBUAe991KQGAAXIBaSSwFIx4TtAYF8WuX+HnC8AKGF5AGpuf0QJQnJtf0gNZGDB9YDIzgVGCgvhifnkDcPg55Qg2ACrwywpgR0BqAkYcGl3w5eelNP9Sip9pAngI2rgLiJ8ISPn2ad7V4mdEgQGmwHjLMADOdW97OuFx4LTFXcgrlCERP2NMVqEVKDrBAYBZ4s14HKQYjzcn0iOXsvzTDtSXB9Arzy7A7xMSVKyZCM8o231mAF78fwJYq4BFcLz1K/z+cnECawyu1rL8UDlUgJeheAnwM8s8Om+5+V9EdTqDcnDzGYGf5l/67EZHjCDJDzRFIASvJejK7/FnLunVZEfGAy/2iTShYvJ5Z1kGEWgfQJPg03r95vpF/n1r/JXpEBjFg1fbtt9c7ypgH7e1YMeLBGEIoJc1FmCvt97FCB6cfs1ABYFe/WjoNRVAjJApWEqUOHmgcksE+kBgX/C2JQsR3+cnQF2UByNgFHlZFxQs/HYdgDEpCajWYfR0FWDjbFgu4lb5p6MivwqMAnYRWEGrETCllijALILWJQX2G8MAzw9iPEO7B6WpZFDNwhdKgP0EC/gzn6+yLxh/yPcjcGGn2JKB3fgnWsALLGB1n+OugPndPEP2GxZQrIWaWMArzP8p4O6urCD/kQpYPQAJXFqgAGXgtZ4Amn6ea8gEgEFQFAAMA5SANSMEcgF3FQOkCuY8AV2+ACoCagmYfzohF/BLJAAohLUE3FUsUDTAfA4KmPAFUCGwZiRBKqDKXzIAwwICATUsQPNTISgjAApCaQFV/osMvgsEQSidBRL84jQEChEt4JUh4E9TAUggoFKKGdMIU8C8IACshMVSXL01iirNiJEGLAFzkYBSM9Jv6IZQC5yXBcDNqDgUKsJ5YP1xhH3wCOF5XsIKElC6iQMsjVEpCtcfTnSATQAgeF6VBNxDAsoLZKv6gmsUru115DhhIi3g8b5sAbAMWEV+qBAUguDdmTlODRM8lA0AxiC1PgaWhsjOVka2/eGkmB0lbgwR0B4AYxCVF4cKsDLKffD+MXNySJrgofz54RBA1PIYmMtTH6zfo09+J9rJ8Ae/KA/AQ3GZHwqC4DU1/5XfcWScgKgIwCEAvYzeIoH2yJ7W7x9OCSGjGBT5yymAx/VfkAcqtw0M4J1f3iOHwkyogE5B7AHoElTZJoN26ZIZLQDHAd8Lj1QA4ioEesCi+UEf7I6QAl4u0P4n0xBos+pOpQFtkx2q/LPZLNnBfkC7f2l6lgE6wGYxtFEYQCZwwugASAh2iRP+Lo0B+B/DANC9M2CXZjoFTECMEEZJWUOwOyRRiK3z+2/ZAGAVpPdnMqhAQ8JxGEISnFnoHJPkcNhhHA6H5BiFhL6oYJWlAPSmUwu8iw3fMzzCCogZZk6UYXZhzyRc3bC6B3MGwQd7FNAEQQSFQaaBRGQalmUQBausCIEOmFqMgwTwmb1dCCuo8Bbw91KEwXdErHvosAlwIAIKePSZghWLn2kAlgmmh4oXBPQ4PogbwC7IMQD78AalQEifKvjL4OceqwLG84oCGXosIEwY/B3u7XP43iXpCiEU7w34BQcIgAVChiAJxbRX/tmB1bZNwUka5gkG3JikJYQRo10xa5CEE0hnCqUkcMwvPMFBABeDFLujMAxC3CQ4o2t1DqmCe5DvcMSFn0cf8eglD/UBG8dFCcnRgV1BPnzCHdw7cqdLDcFB6iDrvkUV5K/omBz482Ige9rbADZMSkBk/jgeIydlxmPiEZPvRGsGJH+2VZU5TxsEu08EgfgCJHWS7WID6RO18vex+vXO9rZ4pjcTSt+oFKK1U80Zv0QBoqE1eqgARsA5PcVGr7WjtU0f+NCtVtyArMYPGShtBALq3vDokdGT3BZi00uXP5YR+jdJCGTPEnOMMOCdkhV8/PGgjWd9DE2i0EL0QbMHGwAo3TqPWeX05i3BV5WgjVANDQiNtBuebQEx1PqyZkBmv3V6AlXXLHE0oMDS9K964M9QdK3P6f0oCPqarnzpc5eGquhda1xRgbkDq6t/07OnhqHqvW7fstITjWPL6nd7ump843OvP/jBD/5P+A/yWoK0uPJ8MwAAAABJRU5ErkJggg==",
    ]


    private static func file(_ name: String, _ type: String, kb: Int) -> OutgoingAttachment {
        var data = Data("%PDF-1.4\n% demo fixture\n".utf8)
        data.append(Data(repeating: 0x20, count: max(0, kb * 1024 - data.count)))
        return OutgoingAttachment(filename: name, mimeType: type, data: data)
    }

    /// Stand-ins for the fixtures' "remote" images: demo mode has no network.
    static let remoteImages: [String: Data] = [
        "https://cdn.sundaystack.news/header-214.png": gradientPNG(hue: 0.12, width: 600, height: 150),
        "https://arcadia-supply.com/img/products-grid.jpg": gradientPNG(hue: 0.05, width: 496, height: 280),
        "https://img.dalmatia-air.example/mail/logo.png": gradientPNG(hue: 0.6, width: 160, height: 40),
        "https://img.dalmatia-air.example/mail/hero-split.jpg": gradientPNG(hue: 0.52, width: 650, height: 240),
        "https://img.dalmatia-air.example/mail/seat.png": gradientPNG(hue: 0.08, width: 300, height: 160),
        "https://img.dalmatia-air.example/mail/bags.png": gradientPNG(hue: 0.9, width: 300, height: 160),
        "https://t.dalmatia-air.example/open.gif?u=7HKQ2P": gradientPNG(hue: 0, width: 1, height: 1),
    ]

    /// Demo mode: `remoteImages` URLs become data URIs; any other remote URL is left alone.
    public static func offlineImages(_ html: String) -> String {
        remoteImages.reduce(html) { out, image in
            out.replacingOccurrences(of: image.key, with: "data:image/png;base64," + image.value.base64EncodedString())
        }
    }

    private static func photo(_ name: String, hue: CGFloat) -> OutgoingAttachment {
        OutgoingAttachment(filename: name, mimeType: "image/png", data: gradientPNG(hue: hue))
    }

    /// A small soft gradient, so image attachments render as real images.
    static func gradientPNG(hue: CGFloat, width: Int = 480, height: Int = 320) -> Data {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return Data() }
        func rgb(_ h: CGFloat, _ s: CGFloat, _ v: CGFloat) -> CGColor {
            let i = Int(h * 6) % 6, f = h * 6 - floor(h * 6)
            let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
            let (r, g, b): (CGFloat, CGFloat, CGFloat) = [(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)][i]
            return CGColor(colorSpace: space, components: [r, g, b, 1])!
        }
        let gradient = CGGradient(colorsSpace: space, colors: [rgb(hue, 0.35, 0.95), rgb((hue + 0.08).truncatingRemainder(dividingBy: 1), 0.55, 0.7)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
        let out = NSMutableData()
        guard let image = ctx.makeImage(), let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return Data() }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        return out as Data
    }

    private static func ics(summary: String, start: Date, minutes: Int, organizer: EmailAddress, location: String) -> OutgoingAttachment {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let text = """
            BEGIN:VCALENDAR\r
            PRODID:-//Google Inc//Google Calendar 70.9054//EN\r
            VERSION:2.0\r
            METHOD:REQUEST\r
            BEGIN:VEVENT\r
            DTSTART:\(f.string(from: start))\r
            DTEND:\(f.string(from: start.addingTimeInterval(Double(minutes) * 60)))\r
            DTSTAMP:\(f.string(from: .now))\r
            ORGANIZER;CN=\(organizer.displayName):mailto:\(organizer.email)\r
            UID:\(abs(summary.hashValue))@google.com\r
            ATTENDEE;CUTYPE=INDIVIDUAL;ROLE=REQ-PARTICIPANT;PARTSTAT=NEEDS-ACTION;CN=\(me.name!):mailto:\(me.email)\r
            SUMMARY:\(summary)\r
            LOCATION:\(location)\r
            STATUS:CONFIRMED\r
            END:VEVENT\r
            END:VCALENDAR\r

            """
        return OutgoingAttachment(filename: "invite.ics", mimeType: "text/calendar", data: Data(text.utf8))
    }

    private static func eventTitleDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE MMM d, h a"
        let end = date.addingTimeInterval(3600)
        let e = DateFormatter()
        e.locale = f.locale
        e.dateFormat = "h a"
        return "\(f.string(from: date)) – \(e.string(from: end)) (CEST)"
    }

    // MARK: - HTML bodies

    private static func inviteHTML(title: String, when: String, organizer: String) -> String {
        """
        <div style="font-family:Roboto,Arial,sans-serif;max-width:560px;border:1px solid #dadce0;border-radius:8px;padding:24px">
          <div style="font-size:22px;color:#3c4043;margin-bottom:12px">\(title)</div>
          <table style="font-size:14px;color:#3c4043;border-collapse:collapse">
            <tr><td style="color:#70757a;padding:4px 16px 4px 0">When</td><td>\(when)</td></tr>
            <tr><td style="color:#70757a;padding:4px 16px 4px 0">Organizer</td><td>\(organizer)</td></tr>
            <tr><td style="color:#70757a;padding:4px 16px 4px 0">Joining</td><td><a href="https://meet.google.com/abc-defg-hij" style="color:#1a73e8">meet.google.com/abc-defg-hij</a></td></tr>
          </table>
          <p style="margin-top:20px"><a style="background:#1a73e8;color:#fff;padding:8px 16px;border-radius:4px;text-decoration:none" href="#">Yes</a>&nbsp;<a style="border:1px solid #dadce0;color:#3c4043;padding:8px 16px;border-radius:4px;text-decoration:none" href="#">Maybe</a>&nbsp;<a style="border:1px solid #dadce0;color:#3c4043;padding:8px 16px;border-radius:4px;text-decoration:none" href="#">No</a></p>
        </div>
        """
    }

    private static func receiptHTML(company: String, number: String, amount: String, item: String, period: String) -> String {
        """
        <table width="100%" cellpadding="0" cellspacing="0" style="background:#f6f9fc;padding:32px 0;font-family:-apple-system,Helvetica,Arial,sans-serif">
          <tr><td align="center">
            <table width="520" cellpadding="0" cellspacing="0" style="background:#ffffff;border-radius:8px;padding:32px">
              <tr><td style="font-size:14px;color:#8898aa">Receipt from \(company)</td></tr>
              <tr><td style="font-size:32px;color:#32325d;padding:8px 0 4px">\(amount)</td></tr>
              <tr><td style="font-size:14px;color:#8898aa;padding-bottom:24px">Paid · Receipt #\(number)</td></tr>
              <tr><td style="border-top:1px solid #e6ebf1;padding-top:16px;font-size:14px;color:#525f7f">
                <table width="100%"><tr><td>\(item)</td><td align="right">\(amount)</td></tr>
                <tr><td style="color:#8898aa">\(period)</td><td></td></tr></table>
              </td></tr>
              <tr><td style="padding-top:24px"><img src="https://q.stripe.com/pixel.gif?r=\(number)" width="1" height="1" alt=""></td></tr>
            </table>
          </td></tr>
        </table>
        """
    }

    private static func newsletterHTML() -> String {
        """
        <div style="max-width:600px;margin:0 auto;font-family:Georgia,serif;color:#222;line-height:1.6">
          <img src="https://cdn.sundaystack.news/header-214.png" width="600" alt="The Sunday Stack" style="display:block;width:100%">
          <h1 style="font-size:28px;margin:24px 0 8px">Local-first is having a moment</h1>
          <p style="color:#666;font-size:14px;margin:0 0 24px">Issue #214 · 7 min read</p>
          <p>For a decade the default architecture was simple: the server owns the data, the client renders it. That's changing. SQLite in the browser, CRDTs that finally work, and sync engines you can buy off the shelf have made "local-first" a real option for small teams.</p>
          <h2 style="font-size:20px;margin-top:32px">1. Three email clients, three sync engines</h2>
          <p>We tore down how three popular clients keep your inbox in sync. One polls, one streams, and one does something clever with history ids that we hadn't seen before.</p>
          <blockquote style="border-left:3px solid #ddd;margin:16px 0;padding:4px 16px;color:#555">"The fastest request is the one you never make." — every performance engineer, eventually</blockquote>
          <h2 style="font-size:20px;margin-top:32px">2. The extension everyone is quietly shipping</h2>
          <p>FTS5 has been in SQLite since 2015. It's still the best full-text search most apps will ever need.</p>
          <p style="text-align:center;margin:32px 0"><a href="https://sundaystack.news/214" style="background:#111;color:#fff;padding:12px 24px;border-radius:6px;text-decoration:none;font-family:Helvetica,Arial,sans-serif">Read the full issue</a></p>
          <p style="font-size:12px;color:#999;text-align:center">You're receiving this because you subscribed at sundaystack.news. <a href="#" style="color:#999">Unsubscribe</a></p>
        </div>
        """
    }

    private static func promoHTML() -> String {
        """
        <table width="100%" cellpadding="0" cellspacing="0" style="background:#fff3e6">
          <tr><td align="center" style="padding:40px 16px;font-family:Helvetica,Arial,sans-serif">
            <table width="560" cellpadding="0" cellspacing="0" style="background:#ffffff;border-radius:16px;overflow:hidden">
              <tr><td style="background:linear-gradient(135deg,#ff7a18,#ff3d6e);padding:48px 32px;color:#fff;text-align:center">
                <div style="font-size:14px;letter-spacing:2px;text-transform:uppercase">48 hours only</div>
                <div style="font-size:56px;font-weight:800;line-height:1.1;margin:8px 0">40% OFF</div>
                <div style="font-size:18px">every annual plan</div>
              </td></tr>
              <tr><td style="padding:32px;color:#333;font-size:16px;line-height:1.5">
                <p>Stock up on the tools your team already loves. The discount applies automatically at checkout — no code needed.</p>
                <table width="100%" cellpadding="8" style="margin:16px 0;border-collapse:collapse">
                  <tr style="background:#fafafa"><td>Starter</td><td align="right"><s style="color:#999">€120</s> <b>€72</b>/yr</td></tr>
                  <tr><td>Team</td><td align="right"><s style="color:#999">€480</s> <b>€288</b>/yr</td></tr>
                  <tr style="background:#fafafa"><td>Business</td><td align="right"><s style="color:#999">€960</s> <b>€576</b>/yr</td></tr>
                </table>
                <p style="text-align:center"><a href="https://arcadia-supply.com/sale" style="display:inline-block;background:#ff3d6e;color:#fff;padding:14px 32px;border-radius:999px;text-decoration:none;font-weight:700">Shop the sale</a></p>
                <img src="https://arcadia-supply.com/img/products-grid.jpg" width="496" alt="Products" style="width:100%;border-radius:8px">
              </td></tr>
            </table>
            <p style="font-size:11px;color:#aa8866;margin-top:16px">Arcadia Supply Co. · Kongresni trg 1, Ljubljana · <a href="#" style="color:#aa8866">Unsubscribe</a></p>
          </td></tr>
        </table>
        """
    }

    /// A 650px fixed-width airline template: remote images, a cid: boarding QR, a tracking pixel and a long URL.
    private static func airlineHTML() -> String {
        let img = "https://img.dalmatia-air.example/mail"
        return """
        <table width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="#eef2f6"><tr><td align="center" style="padding:24px 0">
        <table width="650" cellpadding="0" cellspacing="0" border="0" bgcolor="#ffffff" style="width:650px;font-family:Arial,Helvetica,sans-serif;color:#1c2b39">
          <tr><td style="padding:20px 32px;background:#0b3d6e"><img src="\(img)/logo.png" width="160" height="40" alt="Dalmatia Air" style="display:block"></td></tr>
          <tr><td><img src="\(img)/hero-split.jpg" width="650" height="240" alt="Split riva at sunrise" style="display:block;width:650px"></td></tr>
          <tr><td style="padding:28px 32px 8px;font-size:24px;font-weight:bold">Your booking is confirmed</td></tr>
          <tr><td style="padding:0 32px 20px;font-size:15px;line-height:22px;color:#4a5b6b">Hi Tim, thanks for flying with us. Booking reference <b style="color:#1c2b39;letter-spacing:1px">7HKQ2P</b>.</td></tr>
          <tr><td style="padding:0 32px">
            <table width="586" cellpadding="0" cellspacing="0" border="0" style="border:1px solid #d7e0e8;border-radius:6px">
              <tr>
                <td width="190" style="padding:18px"><div style="font-size:34px;font-weight:bold">LJU</div><div style="font-size:13px;color:#6b7c8c">Ljubljana · Fri 07:15</div></td>
                <td width="206" align="center" style="font-size:13px;color:#6b7c8c">DA 482 · 1h 05m<br>Economy Classic</td>
                <td width="190" align="right" style="padding:18px"><div style="font-size:34px;font-weight:bold">SPU</div><div style="font-size:13px;color:#6b7c8c">Split · Fri 08:20</div></td>
              </tr>
              <tr><td colspan="3" style="border-top:1px dashed #d7e0e8;padding:18px">
                <table cellpadding="0" cellspacing="0" border="0"><tr>
                  <td width="120"><img src="cid:qr-7HKQ2P@dalmatia-air" width="110" height="110" alt="Boarding pass QR"></td>
                  <td style="padding-left:18px;font-size:14px;line-height:22px">Passenger <b>Tim Cvetko</b><br>Seat <b>3C</b> · Group 2 · Gate closes 06:55<br>1 × 23 kg checked bag</td>
                </tr></table>
              </td></tr>
            </table>
          </td></tr>
          <tr><td style="padding:24px 32px 8px">
            <table width="586" cellpadding="0" cellspacing="0" border="0"><tr>
              <td width="283" valign="top"><img src="\(img)/seat.png" width="283" height="150" alt="Choose your seat" style="display:block"><p style="font-size:14px;font-weight:bold;margin:10px 0 2px">Pick a window seat</p><p style="font-size:13px;color:#6b7c8c;margin:0">From €7 per flight</p></td>
              <td width="20"></td>
              <td width="283" valign="top"><img src="\(img)/bags.png" width="283" height="150" alt="Add baggage" style="display:block"><p style="font-size:14px;font-weight:bold;margin:10px 0 2px">Travelling with more?</p><p style="font-size:13px;color:#6b7c8c;margin:0">Add a bag online and save 30%</p></td>
            </tr></table>
          </td></tr>
          <tr><td align="center" style="padding:24px 32px"><a href="https://www.dalmatia-air.example/manage?ref=7HKQ2P" style="display:inline-block;background:#e4572e;color:#ffffff;font-weight:bold;font-size:15px;padding:12px 28px;border-radius:4px;text-decoration:none">Manage booking</a></td></tr>
          <tr><td style="padding:16px 32px 28px;font-size:11px;line-height:17px;color:#8a99a8;border-top:1px solid #e3e9ef">Check in online: https://www.dalmatia-air.example/check-in/booking/7HKQ2P/passenger/1/segment/DA482-LJU-SPU?utm_source=transactional&amp;utm_medium=email&amp;utm_campaign=booking_confirmation<br>Dalmatia Air d.d. · Obala kneza Branimira 1, Split · <a href="https://www.dalmatia-air.example/privacy" style="color:#8a99a8">Privacy</a></td></tr>
        </table>
        <img src="https://t.dalmatia-air.example/open.gif?u=7HKQ2P" width="1" height="1" alt="">
        </td></tr></table>
        """
    }

    private static func flightHTML() -> String {
        """
        <div style="font-family:Helvetica,Arial,sans-serif;max-width:600px;margin:0 auto;color:#1d1d1b">
          <div style="background:#00a94f;color:#fff;padding:24px;font-size:22px;font-weight:bold">Your booking is confirmed</div>
          <div style="padding:24px;border:1px solid #e5e5e5;border-top:none">
            <p style="margin:0 0 16px">Booking reference <b style="font-size:18px;letter-spacing:1px">QX7L2M</b></p>
            <table width="100%" style="border-collapse:collapse;font-size:14px">
              <tr><td style="font-size:32px;font-weight:bold">LJU</td><td align="center" style="color:#888">TP 1231 · 2h 55m</td><td align="right" style="font-size:32px;font-weight:bold">LIS</td></tr>
              <tr><td>Ljubljana 07:05</td><td></td><td align="right">Lisbon 09:00</td></tr>
            </table>
            <p style="margin-top:24px;color:#555">Seat 14A · 1 checked bag (23 kg) · Economy Classic</p>
            <p><a href="#" style="color:#00a94f">Manage booking</a> · <a href="#" style="color:#00a94f">Check in online</a></p>
          </div>
        </div>
        """
    }

    private static func notionDigestHTML() -> String {
        """
        <div style="font-family:ui-sans-serif,-apple-system,Helvetica,sans-serif;max-width:520px;color:#37352f;font-size:14px">
          <p style="font-size:16px;font-weight:600">3 updates in Product Wiki</p>
          <p><b>Priya Raman</b> edited <a href="#" style="color:#37352f">Q4 Roadmap</a><br><span style="color:#9b9a97">Added "Decisions needed" section</span></p>
          <p><b>Zoë Müller</b> edited <a href="#" style="color:#37352f">Search — result states</a><br><span style="color:#9b9a97">Updated highlight color</span></p>
          <p><b>Marco Bellini</b> created <a href="#" style="color:#37352f">Offline search: tech plan</a></p>
          <p style="color:#9b9a97;font-size:12px;margin-top:24px">Notion Labs, Inc. · <a href="#" style="color:#9b9a97">Notification settings</a></p>
        </div>
        """
    }

    private static func metricsHTML() -> String {
        """
        <div style="font-family:Lato,Helvetica,Arial,sans-serif;max-width:560px;color:#4c5773">
          <h2 style="font-size:18px;color:#2e353b">Weekly metrics — week 38</h2>
          <table width="100%" cellpadding="8" style="border-collapse:collapse;font-size:14px">
            <tr style="border-bottom:1px solid #eee"><th align="left">Metric</th><th align="right">This week</th><th align="right">Δ</th></tr>
            <tr style="border-bottom:1px solid #eee"><td>Weekly active users</td><td align="right">4,812</td><td align="right" style="color:#84bb4c">+6.2%</td></tr>
            <tr style="border-bottom:1px solid #eee"><td>Threads triaged</td><td align="right">118,240</td><td align="right" style="color:#84bb4c">+3.9%</td></tr>
            <tr style="border-bottom:1px solid #eee"><td>Median search latency</td><td align="right">38 ms</td><td align="right" style="color:#84bb4c">−12 ms</td></tr>
            <tr><td>Crash-free sessions</td><td align="right">99.82%</td><td align="right" style="color:#ed6e6e">−0.05%</td></tr>
          </table>
        </div>
        """
    }

    private static func securityHTML() -> String {
        """
        <div style="font-family:Roboto,Arial,sans-serif;max-width:520px;margin:0 auto;border:1px solid #dadce0;border-radius:8px;padding:40px 24px;text-align:center;color:#202124">
          <div style="font-size:24px">A new sign-in on Mac</div>
          <div style="font-size:14px;color:#5f6368;margin:8px 0 24px">cvetko.tim@gmail.com</div>
          <p style="font-size:14px;text-align:left">We noticed a new sign-in to your Google Account on a Mac device. If this was you, you don't need to do anything. If not, we'll help you secure your account.</p>
          <p><a href="https://myaccount.google.com/notifications" style="display:inline-block;background:#1a73e8;color:#fff;padding:10px 24px;border-radius:4px;text-decoration:none">Check activity</a></p>
        </div>
        """
    }
}

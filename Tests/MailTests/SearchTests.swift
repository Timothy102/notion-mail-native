import Foundation
@testable import MailCore
import XCTest

final class SearchTests: XCTestCase {
    private var utc: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    func testParsesOperatorsPhrasesAndNegation() {
        let q = SearchQuery(#"from:priya subject:"q4 roadmap" has:attachment is:unread -is:starred label:work -label:newsletters -"weekly digest" -spam budget"#)
        XCTAssertEqual(q.include, [.init("priya", field: .from), .init("q4 roadmap", field: .subject, isPhrase: true), .init("budget")])
        XCTAssertEqual(q.exclude, [.init("weekly digest", isPhrase: true), .init("spam")])
        XCTAssertEqual(q.hasAttachment, true)
        XCTAssertEqual(q.isUnread, true)
        XCTAssertEqual(q.isStarred, false)
        XCTAssertEqual(q.labels, ["work"])
        XCTAssertEqual(q.excludedLabels, ["newsletters"])
        XCTAssertFalse(q.needsGmail)
        XCTAssertEqual(q.highlightTerms, ["q4", "roadmap", "budget"])
    }

    func testParsesDates() {
        let now = Date(timeIntervalSince1970: 1_790_000_000) // 2026-09-21
        let q = SearchQuery("after:2026/03/01 before:2026-3-15", now: now, calendar: utc)
        XCTAssertEqual(q.after, utc.date(from: DateComponents(year: 2026, month: 3, day: 1)))
        XCTAssertEqual(q.before, utc.date(from: DateComponents(year: 2026, month: 3, day: 15)))
        XCTAssertEqual(SearchQuery("newer_than:7d", now: now, calendar: utc).after, now.addingTimeInterval(-7 * 86_400))
        XCTAssertEqual(SearchQuery("before:03/15/2026", calendar: utc).before, utc.date(from: DateComponents(year: 2026, month: 3, day: 15)))
        XCTAssertTrue(SearchQuery("before:someday").needsGmail)
    }

    func testUnknownOperatorsFallBackToGmail() {
        XCTAssertTrue(SearchQuery("larger:10M invoice").needsGmail)
        XCTAssertTrue(SearchQuery("from:a OR from:b").needsGmail)
        XCTAssertEqual(SearchQuery("filename:pdf").unsupported, ["filename:pdf"])
        XCTAssertFalse(SearchQuery("http://example.com re:thing").needsGmail, "colons after non-letters are text")
        XCTAssertTrue(SearchQuery("   ").isEmpty)
    }

    func testFTSExpressionQuotesAndPrefixes() {
        let q = SearchQuery(#"from:ana@acme.com say "hi ""there" x"#)
        XCTAssertEqual(Store.ftsExpression(q.include), #"{from} : "ana@acme.com"* AND "say"* AND "hi " AND "there" AND "x"*"#)
        XCTAssertNil(Store.ftsExpression([.init("@@")]))
    }

    private func seeded() throws -> Store {
        let store = try Store()
        try Fixtures.seed(store)
        return store
    }

    private func subjects(_ store: Store, _ q: String, order: SearchOrder = .date) throws -> [String] {
        try store.db.read { try Store.search($0, SearchQuery(q), order: order).map(\.thread.subject) }
    }

    func testOperatorsFilterLocally() throws {
        let store = try seeded()
        XCTAssertEqual(try subjects(store, "offsite").first, "Offsite venue options")
        XCTAssertTrue(try subjects(store, "from:jose").contains("Offsite venue options"))
        XCTAssertTrue(try subjects(store, "from:garcia").contains("Offsite venue options"), "from: matches name words")
        XCTAssertFalse(try subjects(store, "from:jose").contains("Q4 roadmap: decisions needed before Friday"))
        XCTAssertTrue(try subjects(store, "bohinj").contains("Offsite venue options"))
        XCTAssertFalse(try subjects(store, "bohinj -wifi").contains("Offsite venue options"), "negation drops the whole thread")
        XCTAssertEqual(try subjects(store, #""lake bohinj""#), ["Offsite venue options"])
        XCTAssertEqual(try subjects(store, #""bohinj lake""#), [], "phrases keep word order")

        try store.db.read { db in
            let unread = try Store.search(db, SearchQuery("is:unread"))
            XCTAssertFalse(unread.isEmpty)
            XCTAssertTrue(unread.allSatisfy(\.thread.isUnread))
            XCTAssertTrue(try Store.search(db, SearchQuery("has:attachment")).allSatisfy(\.thread.hasAttachments))
            XCTAssertTrue(try Store.search(db, SearchQuery("is:starred")).allSatisfy(\.thread.isStarred))
            let work = try Store.search(db, SearchQuery("label:work"))
            XCTAssertFalse(work.isEmpty)
            XCTAssertTrue(work.allSatisfy { $0.thread.labelIds.contains("Label_1") })
            XCTAssertTrue(try Store.search(db, SearchQuery("label:work -label:work")).isEmpty)
            XCTAssertEqual(try Store.search(db, SearchQuery("in:sent")).count, try Store.threads(db, in: .sent).count)
        }
    }

    func testSpamAndTrashNeedExplicitScope() throws {
        let store = try seeded()
        XCTAssertEqual(try subjects(store, "webinar"), [])
        XCTAssertEqual(try subjects(store, "webinar in:trash"), ["Last chance: webinar on inbox zero"])
        XCTAssertEqual(try subjects(store, "webinar in:anywhere"), ["Last chance: webinar on inbox zero"])
    }

    func testDateOperators() throws {
        let store = try seeded()
        try store.db.read { db in
            let cutoff = Date.now.addingTimeInterval(-30 * 86_400)
            let old = try Store.search(db, SearchQuery("before:\(Self.day(cutoff))"))
            XCTAssertFalse(old.isEmpty)
            let recent = try Store.search(db, SearchQuery("newer_than:2d"))
            XCTAssertFalse(recent.isEmpty)
            XCTAssertTrue(recent.contains { $0.thread.subject == "Q4 roadmap: decisions needed before Friday" })
            XCTAssertTrue(Set(old.map(\.id)).isDisjoint(with: recent.map(\.id)))
        }
    }

    func testRankingPrefersSubjectHitsAndExcerptsBodyHits() throws {
        let store = try seeded()
        try store.db.read { db in
            let byRank = try Store.search(db, SearchQuery("search"), order: .relevance)
            XCTAssertGreaterThan(byRank.count, 1)
            XCTAssertTrue(byRank[0].thread.subject.localizedCaseInsensitiveContains("search"), "a subject hit ranks first: \(byRank[0].thread.subject)")
            let byDate = try Store.search(db, SearchQuery("search"))
            XCTAssertEqual(byDate.map(\.thread.lastDate), byDate.map(\.thread.lastDate).sorted(by: >))

            let body = try XCTUnwrap(Store.search(db, SearchQuery("fibre")).first)
            XCTAssertEqual(body.thread.subject, "Offsite venue options")
            XCTAssertTrue(body.excerpt?.contains("fibre") == true, body.excerpt ?? "nil")
            XCTAssertNil(try Store.search(db, SearchQuery("offsite venue")).first?.excerpt, "subject-only hit keeps the thread snippet")
        }
    }

    func testContacts() throws {
        let store = try seeded()
        try store.db.read { db in
            XCTAssertEqual(try Store.contacts(db, matching: "pri").first?.email, "priya@helio.dev")
            XCTAssertEqual(try Store.contacts(db, matching: "zoe").first?.name, "Zoë Müller", "diacritics fold")
            XCTAssertEqual(try Store.contacts(db, matching: "garc").first?.email, "jose.garcia@fieldtrip.studio")
            XCTAssertTrue(try Store.contacts(db, matching: "tim").allSatisfy { $0.email != Fixtures.me.email })
        }
    }

    func testHighlightMarksWholeWordsByPrefix() {
        let text = "Zoë commented on Offsite venues"
        let marked = SearchText.marks(in: text, terms: ["zoe", "venue", "on"]).map { String(text[$0]) }
        XCTAssertEqual(marked, ["Zoë", "on", "venues"])
        XCTAssertTrue(SearchText.marks(in: text, terms: []).isEmpty)
    }

    func testFuzzyScore() {
        XCTAssertNotNil(SearchText.fuzzyScore("gs", "Go to Sent"))
        XCTAssertNil(SearchText.fuzzyScore("gs", "Go to Investors"), "mid-word letters only continue a match")
        XCTAssertNotNil(SearchText.fuzzyScore("sidebar", "Toggle sidebar"))
        XCTAssertNotNil(SearchText.fuzzyScore("tog side", "Toggle sidebar"))
        XCTAssertNil(SearchText.fuzzyScore("xq", "Archive"))
        let archive = SearchText.fuzzyScore("arc", "Archive")!
        let search = SearchText.fuzzyScore("arc", "Search")!
        XCTAssertGreaterThan(archive, search, "prefix beats mid-word")
        XCTAssertGreaterThan(SearchText.fuzzyScore("sent", "Go to Sent")!, SearchText.fuzzyScore("sent", "Set theme · Dark") ?? .min)
        XCTAssertEqual(SearchText.fuzzyScore("", "anything"), 0)
    }

    private static func day(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy/MM/dd"
        return f.string(from: date)
    }
}

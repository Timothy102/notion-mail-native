import Foundation
@testable import MailCore
import XCTest

final class IntegrationTests: XCTestCase {
    func testICSParsesFoldedEscapedTZIDEvent() throws {
        let ics = """
            BEGIN:VCALENDAR\r
            METHOD:REQUEST\r
            BEGIN:VTIMEZONE\r
            TZID:Europe/Ljubljana\r
            END:VTIMEZONE\r
            BEGIN:VEVENT\r
            UID:abc@google.com\r
            DTSTART;TZID=Europe/Ljubljana:20260924T140000\r
            DURATION:PT1H30M\r
            SUMMARY:Design review\\, round 2\r
            LOCATION:Room Tivoli \\;\r
             Google Meet\r
            ORGANIZER;CN="Müller, Zoë":mailto:zoe@helio.dev\r
            ATTENDEE;CN=Tim;PARTSTAT=NEEDS-ACTION:mailto:tim@helio.dev\r
            END:VEVENT\r
            END:VCALENDAR\r
            """
        let event = try XCTUnwrap(ICS.events(ics).first)
        XCTAssertEqual(event.title, "Design review, round 2")
        XCTAssertEqual(event.location, "Room Tivoli ;Google Meet")
        XCTAssertEqual(event.organizer, EmailAddress(name: "Müller, Zoë", email: "zoe@helio.dev"))
        XCTAssertEqual(event.attendees.map(\.email), ["tim@helio.dev"])
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Ljubljana")!
        XCTAssertEqual(cal.dateComponents([.hour, .minute], from: event.start), DateComponents(hour: 14, minute: 0))
        XCTAssertEqual(event.end.timeIntervalSince(event.start), 5400)
        XCTAssertFalse(event.isAllDay)
        XCTAssertEqual(ICS.method(Data(ics.utf8)), "REQUEST")
    }

    func testICSAllDayAndUTC() throws {
        let events = ICS.events("BEGIN:VEVENT\nDTSTART;VALUE=DATE:20261019\nDTEND;VALUE=DATE:20261022\nSUMMARY:Swift Island\nEND:VEVENT\nBEGIN:VEVENT\nDTSTART:20260924T120000Z\nSUMMARY:Call\nEND:VEVENT\n")
        XCTAssertEqual(events.count, 2)
        XCTAssertTrue(events[0].isAllDay)
        XCTAssertEqual(events[0].end.timeIntervalSince(events[0].start), 3 * 86_400, accuracy: 3600)
        XCTAssertEqual(events[1].start, ISO8601DateFormatter().date(from: "2026-09-24T12:00:00Z"))
        XCTAssertNil(events[1].location)
    }

    func testFixtureInviteParses() throws {
        let store = try Store()
        try Fixtures.seed(store)
        let data = try XCTUnwrap(try store.db.read { try Attachment.fetchAll($0) }.first { $0.mimeType == "text/calendar" }?.data)
        XCTAssertEqual(ICS.events(data).first?.title, "Design review")
    }

    func testGoogleEventsDecodeAndSkipDeclined() throws {
        let json = """
            {"items":[
              {"id":"1","summary":"Standup","colorId":"7","start":{"dateTime":"2026-09-23T09:30:00+02:00"},"end":{"dateTime":"2026-09-23T09:45:00+02:00"},"htmlLink":"https://calendar.google.com/e/1"},
              {"id":"2","summary":"Offsite","start":{"date":"2026-09-24"},"end":{"date":"2026-09-25"}},
              {"id":"3","summary":"Declined","start":{"dateTime":"2026-09-23T10:00:00Z"},"end":{"dateTime":"2026-09-23T11:00:00Z"},"attendees":[{"email":"t@x.com","self":true,"responseStatus":"declined"}]},
              {"id":"4","status":"cancelled","start":{"dateTime":"2026-09-23T10:00:00Z"},"end":{"dateTime":"2026-09-23T11:00:00Z"}}
            ]}
            """
        let events = try JSONDecoder().decode(GoogleEventList.self, from: Data(json.utf8)).items.compactMap(\.event)
        XCTAssertEqual(events.map(\.id), ["1", "2"])
        XCTAssertEqual(events[0].color, 0x039BE5)
        XCTAssertEqual(events[0].end.timeIntervalSince(events[0].start), 900)
        XCTAssertTrue(events[1].isAllDay)
    }

    func testNotionPageBodyUsesDatabaseProperties() throws {
        let store = try Store()
        try Fixtures.seed(store)
        let detail = try XCTUnwrap(try store.db.read { db in
            try Store.threads(db, in: .inbox).first { $0.messageCount >= 5 }.flatMap { try Store.threadDetail(db, id: $0.id) }
        })
        let db = NotionObject(id: "db1", kind: .database, title: "Follow-ups", url: "", titleProperty: "Task", urlProperty: "Gmail")
        let body = NotionClient.pageBody(detail, database: db)
        XCTAssertEqual((body["parent"] as? [String: String])?["database_id"], "db1")
        let props = try XCTUnwrap(body["properties"] as? [String: Any])
        XCTAssertEqual((props["Gmail"] as? [String: String])?["url"], NotionClient.gmailURL(threadId: detail.thread.id))
        let title = try XCTUnwrap(((props["Task"] as? [String: Any])?["title"] as? [[String: Any]])?.first?["text"] as? [String: Any])
        XCTAssertEqual(title["content"] as? String, detail.thread.subject)
        XCTAssertEqual((body["children"] as? [Any])?.count, 3)
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: body))
    }

    @MainActor
    func testNotionCommandsOpenPickerAndEscClosesIt() throws {
        let store = try Store()
        try Fixtures.seed(store)
        let app = AppState(store: store, gmail: nil)
        XCTAssertFalse(app.commands.run("notion.save"))
        let id = try XCTUnwrap(try store.db.read { try Store.threads($0, in: .inbox).first?.id })
        app.open(id)
        XCTAssertTrue(app.commands.run("notion.link"))
        XCTAssertEqual(app.notionPicker, .link(threadId: id))
        XCTAssertTrue(app.dismissTopmost())
        XCTAssertNil(app.notionPicker)
        XCTAssertEqual(app.openThreadId, id)
        XCTAssertNil(app.commands["notion.open"].flatMap { $0.isAvailable() ? $0 : nil })
        try store.save(notionLink: NotionLink(threadId: id, pageId: "p", title: "Q4", url: "https://www.notion.so/p"))
        XCTAssertEqual(app.commands["notion.open"]?.isAvailable(), true)
    }
}

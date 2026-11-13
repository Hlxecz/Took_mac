import XCTest
@testable import TookCore

final class CalendarPlanTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }
    private func date(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text + "+09:00")!
    }
    private var now: Date { date("2026-11-04T12:00:00") }
    private func plan(_ key: String = "calendar|meeting|single", title: String = "회의",
                      start: Date? = nil, end: Date? = nil) -> CalendarPlan {
        CalendarPlan(key: key, title: title, calendarTitle: "일정", start: start ?? now,
                     end: end ?? now.addingTimeInterval(3600), isAllDay: false)
    }

    func testSyncUpdatesWithoutDuplicatesAndKeepsManualPlans() throws {
        var doc = TaskDocument()
        let manual = try doc.add(title: "직접 적은 계획", scheduledDate: now)
        try doc.syncCalendarPlans([plan(), plan()], now: now, calendar: calendar)
        let imported = try XCTUnwrap(doc.tasks.first { $0.calendarPlan != nil }).id
        let moved = plan(title: "바뀐 회의", start: now.addingTimeInterval(3600), end: now.addingTimeInterval(7200))
        try doc.syncCalendarPlans([moved], now: now, calendar: calendar)
        XCTAssertEqual(doc.tasks.map(\.id), [manual, imported])
        XCTAssertEqual(doc.tasks.last?.title, "바뀐 회의")
        XCTAssertEqual(doc.tasks.last?.scheduledDate, moved.start)
        try doc.syncCalendarPlans([], now: now, calendar: calendar)
        XCTAssertEqual(doc.tasks.map(\.id), [manual])
    }

    func testSevenDayWindowIncludesOngoingEventsButExcludesEndBoundary() throws {
        var doc = TaskDocument()
        let ongoing = plan("ongoing", start: date("2026-11-03T00:00:00"), end: date("2026-11-05T00:00:00"))
        let last = plan("last", start: date("2026-11-10T23:00:00"), end: date("2026-11-11T00:00:00"))
        let outside = plan("outside", start: date("2026-11-11T00:00:00"), end: date("2026-11-11T01:00:00"))
        let ended = plan("ended", start: date("2026-11-03T12:00:00"), end: date("2026-11-04T00:00:00"))
        try doc.syncCalendarPlans([ongoing, last, outside, ended], now: now, calendar: calendar)
        XCTAssertEqual(doc.tasks.compactMap { $0.calendarPlan?.key }, ["ongoing", "last"])
        var dst = Calendar(identifier: .gregorian)
        dst.timeZone = TimeZone(identifier: "America/New_York")!
        let day = ISO8601DateFormatter().date(from: "2026-11-01T00:00:00-04:00")!
        XCTAssertEqual(CalendarPlan.window(from: day, calendar: dst).duration, 169 * 3600)
    }

    func testCompletedOccurrenceStaysHiddenAfterHistoryClearAndReload() throws {
        var doc = TaskDocument()
        let first = plan("series|first")
        let next = plan("series|next", start: now.addingTimeInterval(86400), end: now.addingTimeInterval(90000))
        try doc.syncCalendarPlans([first, next], now: now, calendar: calendar)
        doc.complete(id: doc.tasks[0].id, now: now, calendar: calendar)
        doc.clearHistory()
        doc = try JSONDecoder().decode(TaskDocument.self, from: JSONEncoder().encode(doc))
        try doc.syncCalendarPlans([first, next], now: now, calendar: calendar)
        XCTAssertTrue(doc.history.isEmpty)
        XCTAssertEqual(doc.tasks.compactMap { $0.calendarPlan?.key }, [next.key])
    }

    func testDeletedEventStaysHiddenUntilRestored() throws {
        var doc = TaskDocument()
        let event = plan()
        try doc.syncCalendarPlans([event], now: now, calendar: calendar)
        let id = doc.tasks[0].id
        doc.delete(id: id, now: now)
        try doc.syncCalendarPlans([event], now: now, calendar: calendar)
        XCTAssertTrue(doc.tasks.isEmpty)
        doc.restore(recordID: doc.history[0].id)
        try doc.syncCalendarPlans([event], now: now, calendar: calendar)
        XCTAssertEqual(doc.tasks.map(\.id), [id])
    }

    func testOldDocumentLoadsWithoutCalendarMetadataAndFailedSyncDoesNotOverwriteFile() throws {
        let legacy = Data(#"{"version":1,"tasks":[{"id":"00000000-0000-0000-0000-000000000001","title":"기존 계획","scheduledDate":0,"repeatRule":"none","createdAt":0}],"history":[]}"#.utf8)
        let doc = try JSONDecoder().decode(TaskDocument.self, from: legacy)
        XCTAssertNil(doc.tasks.first?.calendarPlan)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = TaskRepository(fileURL: directory.appendingPathComponent("tasks.json"))
        try repository.save(doc)
        XCTAssertThrowsError(try repository.transaction { try $0.syncCalendarPlans([plan(title: "")], now: now, calendar: calendar) })
        XCTAssertEqual(try repository.load(), doc)
    }

    func testRestoreDoesNotDuplicateAnEventRescheduledAfterSuppressionExpires() throws {
        var doc = TaskDocument()
        let event = plan()
        try doc.syncCalendarPlans([event], now: now, calendar: calendar)
        doc.delete(id: doc.tasks[0].id, now: now)
        let moved = plan(title: "옮긴 회의", start: now.addingTimeInterval(86400), end: now.addingTimeInterval(90000))
        try doc.syncCalendarPlans([moved], now: now.addingTimeInterval(86400), calendar: calendar)
        doc.restore(recordID: doc.history[0].id)
        try doc.validate()
        XCTAssertEqual(doc.tasks.count, 1)
        XCTAssertEqual(doc.tasks[0].calendarPlan, moved)
        XCTAssertTrue(doc.history.isEmpty)
    }

    func testCalendarMovesToPlansTwoDaysBeforeAndCanBeCompletedEarly() throws {
        var doc = TaskDocument()
        let start = date("2026-11-06T15:00:00")
        let event = plan(start: start, end: start.addingTimeInterval(3600))
        try doc.syncCalendarPlans([event], now: now, calendar: calendar)
        let id = doc.tasks[0].id
        let threeDaysBefore = date("2026-11-03T23:59:59")
        XCTAssertTrue(doc.pending(on: threeDaysBefore, calendar: calendar).isEmpty)
        XCTAssertEqual(doc.upcoming(after: threeDaysBefore, calendar: calendar).map(\.id), [id])
        let twoDaysBefore = date("2026-11-04T00:00:00")
        XCTAssertEqual(doc.pending(on: twoDaysBefore, calendar: calendar).map(\.id), [id])
        XCTAssertTrue(doc.upcoming(after: twoDaysBefore, calendar: calendar).isEmpty)
        XCTAssertEqual(doc.tasks[0].scheduledDate, start)
        doc.complete(id: id, now: twoDaysBefore, calendar: calendar)
        XCTAssertTrue(doc.tasks.isEmpty)
        try doc.syncCalendarPlans([event], now: now, calendar: calendar)
        XCTAssertTrue(doc.tasks.isEmpty)
    }

    func testManualFuturePlansKeepTheirScheduledDay() throws {
        var doc = TaskDocument()
        try doc.add(title: "직접 적은 계획", scheduledDate: date("2026-11-06T15:00:00"))
        let id = doc.tasks[0].id
        XCTAssertTrue(doc.pending(on: now, calendar: calendar).isEmpty)
        doc.complete(id: id, now: now, calendar: calendar)
        XCTAssertEqual(doc.tasks.count, 1)
        XCTAssertEqual(doc.pending(on: date("2026-11-06T00:00:00"), calendar: calendar).map(\.id), [id])
    }

    func testReminderUsesNineAMTwoCalendarDaysBeforeAcrossDST() {
        let event = plan(start: date("2026-11-06T15:00:00"), end: date("2026-11-06T16:00:00"))
        XCTAssertEqual(event.reminderDate(calendar: calendar), date("2026-11-04T09:00:00"))
        var dst = Calendar(identifier: .gregorian)
        dst.timeZone = TimeZone(identifier: "America/New_York")!
        let start = ISO8601DateFormatter().date(from: "2026-11-02T15:00:00-05:00")!
        let plan = CalendarPlan(key: "dst", title: "일정", calendarTitle: "달력", start: start,
                                end: start.addingTimeInterval(3600), isAllDay: false)
        let expected = ISO8601DateFormatter().date(from: "2026-10-31T09:00:00-04:00")!
        XCTAssertEqual(plan.reminderDate(calendar: dst), expected)
    }
}

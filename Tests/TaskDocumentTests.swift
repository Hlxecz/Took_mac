import XCTest
@testable import TookCore

final class TaskDocumentTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return value
    }
    private func day(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: value + "T12:00:00+09:00")!
    }

    func testCompleteDisappearsAndRestorePreservesIdentity() throws {
        var doc = TaskDocument()
        let now = day("2026-10-31")
        let id = try doc.add(title: "  장보기  ", scheduledDate: now, now: now)
        XCTAssertEqual(doc.pending(on: now, calendar: calendar).first?.title, "장보기")
        doc.complete(id: id, now: now, calendar: calendar)
        XCTAssertTrue(doc.pending(on: now, calendar: calendar).isEmpty)
        XCTAssertEqual(doc.history.count, 1)
        doc.restore(recordID: doc.history[0].id)
        XCTAssertEqual(doc.tasks.first?.id, id)
        XCTAssertTrue(doc.history.isEmpty)
    }

    func testDailyRepeatDoesNotCompleteNextOccurrenceOnDoubleClick() throws {
        var doc = TaskDocument()
        let now = day("2026-10-31")
        let id = try doc.add(title: "산책", scheduledDate: now, repeatRule: .daily)
        doc.complete(id: id, now: now, calendar: calendar)
        doc.complete(id: id, now: now, calendar: calendar)
        XCTAssertTrue(doc.pending(on: now, calendar: calendar).isEmpty)
        XCTAssertEqual(doc.history.count, 1)
        XCTAssertEqual(doc.pending(on: day("2026-11-01"), calendar: calendar).count, 1)
        doc.restore(recordID: doc.history[0].id)
        XCTAssertEqual(doc.tasks.count, 1)
        XCTAssertEqual(doc.pending(on: now, calendar: calendar).count, 1)
    }

    func testWeekdayRepeatSkipsWeekendAndOverdueUsesToday() throws {
        var doc = TaskDocument()
        let id = try doc.add(title: "출근", scheduledDate: day("2026-10-23"), repeatRule: .weekdays)
        doc.complete(id: id, now: day("2026-10-30"), calendar: calendar)
        XCTAssertTrue(calendar.isDate(doc.tasks[0].scheduledDate, inSameDayAs: day("2026-11-02")))
        XCTAssertEqual(doc.upcoming(after: day("2026-10-31"), calendar: calendar).count, 1)
    }

    func testEditValidationAndRecoverableDelete() throws {
        var doc = TaskDocument()
        let now = day("2026-10-31")
        XCTAssertThrowsError(try doc.add(title: " \n"))
        XCTAssertThrowsError(try doc.add(title: String(repeating: "가", count: 301)))
        let id = try doc.add(title: "초안", scheduledDate: now)
        try doc.edit(id: id, title: "수정", scheduledDate: now, repeatRule: .weekly)
        doc.delete(id: id, now: now)
        XCTAssertTrue(doc.tasks.isEmpty)
        XCTAssertEqual(doc.history[0].kind, .deleted)
        doc.restore(recordID: doc.history[0].id)
        XCTAssertEqual(doc.tasks.first?.title, "수정")
        XCTAssertEqual(doc.tasks.first?.repeatRule, .weekly)
    }

    func testAtomicPersistenceAndCorruptDataIsNotOverwrittenByLoad() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repo = TaskRepository(fileURL: directory.appendingPathComponent("tasks.json"))
        XCTAssertTrue(try repo.load().tasks.isEmpty)
        var doc = TaskDocument()
        try doc.add(title: "저장 확인")
        try repo.save(doc)
        XCTAssertEqual(try repo.load(), doc)
        let corrupt = Data("broken".utf8)
        try corrupt.write(to: repo.fileURL)
        XCTAssertThrowsError(try repo.load())
        XCTAssertEqual(try Data(contentsOf: repo.fileURL), corrupt)
    }

    func testTransactionsReloadTheLatestDocumentAcrossWriters() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = TaskRepository(fileURL: directory.appendingPathComponent("tasks.json"))
        let second = TaskRepository(fileURL: first.fileURL)
        _ = try first.transaction { try $0.add(title: "앱에서 추가") }
        _ = try second.transaction { try $0.add(title: "위젯에서 추가") }
        let result = try first.transaction { try $0.add(title: "앱에서 다시 추가") }
        XCTAssertEqual(result.before.tasks.count, 2)
        XCTAssertEqual(try second.load().tasks.map(\.title), ["앱에서 추가", "위젯에서 추가", "앱에서 다시 추가"])
    }

    func testFailedTransactionDoesNotChangeSavedTasks() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repo = TaskRepository(fileURL: directory.appendingPathComponent("tasks.json"))
        _ = try repo.transaction { try $0.add(title: "보존할 할 일") }
        XCTAssertThrowsError(try repo.transaction {
            try $0.add(title: "저장되면 안 되는 할 일")
            throw TaskError.externalChange
        })
        XCTAssertEqual(try repo.load().tasks.map(\.title), ["보존할 할 일"])
    }

    func testPlansRemainUntilCompletedAndDragOrderPersists() throws {
        var doc = TaskDocument()
        let old = day("2026-10-01")
        let first = try doc.add(title: "첫 계획", scheduledDate: old, now: old)
        let second = try doc.add(title: "둘째 계획", scheduledDate: old, now: old)
        let third = try doc.add(title: "셋째 계획", scheduledDate: old, now: old)
        doc.move(id: first, to: third)
        XCTAssertEqual(doc.pending(on: day("2026-11-30"), calendar: calendar).map(\.id), [second, third, first])
        doc.move(id: first, to: second)
        XCTAssertEqual(doc.tasks.map(\.id), [first, second, third])
        let loaded = try JSONDecoder().decode(TaskDocument.self, from: JSONEncoder().encode(doc))
        XCTAssertEqual(loaded.tasks.map(\.id), [first, second, third])
        doc.move(id: UUID(), to: first)
        XCTAssertEqual(doc.tasks.count, 3)
    }

    func testTomorrowPreviewUsesScheduledDayAndUpcomingIncludesLaterDays() throws {
        var doc = TaskDocument()
        let now = day("2026-10-31")
        try doc.add(title: "남아 있는 계획", scheduledDate: day("2026-10-30"))
        try doc.add(title: "내일 계획", scheduledDate: day("2026-11-01"))
        try doc.add(title: "나중 계획", scheduledDate: day("2026-11-03"))
        XCTAssertEqual(doc.pending(on: now, calendar: calendar).map(\.title), ["남아 있는 계획"])
        XCTAssertEqual(doc.scheduled(on: day("2026-11-01"), calendar: calendar).map(\.title), ["내일 계획"])
        XCTAssertEqual(doc.upcoming(after: now, calendar: calendar).map(\.title), ["내일 계획", "나중 계획"])
    }

    func testEmptyTrashKeepsCompletedHistoryAndActivePlans() throws {
        var doc = TaskDocument()
        let now = day("2026-10-31")
        let done = try doc.add(title: "끝낸 계획", scheduledDate: now)
        let deleted = try doc.add(title: "지운 계획", scheduledDate: now)
        try doc.add(title: "남길 계획", scheduledDate: now)
        doc.complete(id: done, now: now, calendar: calendar)
        doc.delete(id: deleted, now: now)
        doc.emptyTrash()
        XCTAssertEqual(doc.history.count, 1)
        XCTAssertEqual(doc.history.first?.kind, .completed)
        XCTAssertEqual(doc.tasks.map(\.title), ["남길 계획"])
        doc.restore(recordID: doc.history[0].id)
        XCTAssertEqual(doc.tasks.count, 2)
    }

    func testUnknownSchemaIsRejected() throws {
        let data = Data(#"{"version":99,"tasks":[],"history":[]}"#.utf8)
        let doc = try JSONDecoder().decode(TaskDocument.self, from: data)
        XCTAssertThrowsError(try doc.validate())
    }
}

import Foundation
import Darwin

public enum RepeatRule: String, Codable, CaseIterable, Sendable {
    case none, daily, weekdays, weekly

    public var title: String {
        switch self {
        case .none: "반복 안 함"
        case .daily: "매일"
        case .weekdays: "평일마다"
        case .weekly: "매주"
        }
    }

    public func nextDate(after date: Date, calendar: Calendar) -> Date? {
        guard self != .none else { return nil }
        var next = calendar.date(byAdding: .day, value: self == .weekly ? 7 : 1,
                                 to: calendar.startOfDay(for: date))!
        if self == .weekdays {
            while calendar.isDateInWeekend(next) {
                next = calendar.date(byAdding: .day, value: 1, to: next)!
            }
        }
        return next
    }
}

public struct TaskItem: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var scheduledDate: Date
    public var repeatRule: RepeatRule
    public let createdAt: Date

    public init(id: UUID = UUID(), title: String, scheduledDate: Date = Date(),
                repeatRule: RepeatRule = .none, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.scheduledDate = scheduledDate
        self.repeatRule = repeatRule
        self.createdAt = createdAt
    }
}

public struct ActivityRecord: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case completed, deleted }
    public let id: UUID
    public let task: TaskItem
    public let date: Date
    public let kind: Kind
}

public enum TaskError: LocalizedError {
    case emptyTitle, longTitle, invalidDocument, sharedContainerUnavailable, externalChange
    public var errorDescription: String? {
        switch self {
        case .emptyTitle: "할 일을 입력해 주세요."
        case .longTitle: "할 일은 300자 이내로 입력해 주세요."
        case .externalChange: "다른 창이나 위젯에서 목록이 바뀌었습니다. 최신 목록을 확인해 주세요."
        case .sharedContainerUnavailable: "위젯 공유 저장소에 접근할 수 없습니다. 앱과 위젯의 App Groups 및 서명을 확인해 주세요."
        case .invalidDocument: "저장된 파일 형식을 확인할 수 없습니다. 원본 파일은 변경하지 않았습니다."
        }
    }
}

public struct TaskDocument: Codable, Equatable, Sendable {
    public private(set) var version = 1
    public private(set) var tasks: [TaskItem] = []
    public private(set) var history: [ActivityRecord] = []
    public init() {}

    public func validate() throws {
        guard version == 1,
              Set(tasks.map(\.id)).count == tasks.count,
              Set(history.map(\.id)).count == history.count else { throw TaskError.invalidDocument }
        for item in tasks + history.map(\.task) { _ = try Self.validTitle(item.title) }
    }

    public func pending(on date: Date, calendar: Calendar = .current) -> [TaskItem] {
        let day = calendar.startOfDay(for: date)
        return tasks.filter { calendar.startOfDay(for: $0.scheduledDate) <= day }
    }

    public func upcoming(after date: Date, calendar: Calendar = .current) -> [TaskItem] {
        let day = calendar.startOfDay(for: date)
        return tasks.filter { calendar.startOfDay(for: $0.scheduledDate) > day }
            .sorted { $0.scheduledDate == $1.scheduledDate ? $0.createdAt < $1.createdAt : $0.scheduledDate < $1.scheduledDate }
    }

    public func scheduled(on date: Date, calendar: Calendar = .current) -> [TaskItem] {
        tasks.filter { calendar.isDate($0.scheduledDate, inSameDayAs: date) }
    }

    public mutating func move(id: UUID, to targetID: UUID) {
        guard id != targetID,
              let source = tasks.firstIndex(where: { $0.id == id }),
              let target = tasks.firstIndex(where: { $0.id == targetID }) else { return }
        let item = tasks.remove(at: source)
        tasks.insert(item, at: target)
    }

    public mutating func clearHistory() {
        history.removeAll()
    }

    @discardableResult
    public mutating func add(title: String, scheduledDate: Date = Date(),
                             repeatRule: RepeatRule = .none, now: Date = Date()) throws -> UUID {
        let item = TaskItem(title: try Self.validTitle(title), scheduledDate: scheduledDate,
                            repeatRule: repeatRule, createdAt: now)
        tasks.append(item)
        return item.id
    }

    public mutating func edit(id: UUID, title: String, scheduledDate: Date, repeatRule: RepeatRule) throws {
        let valid = try Self.validTitle(title)
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].title = valid
        tasks[index].scheduledDate = scheduledDate
        tasks[index].repeatRule = repeatRule
    }

    public mutating func complete(id: UUID, now: Date = Date(), calendar: Calendar = .current) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        let item = tasks[index]
        // 예약 날짜 이전에는 완료되지 않게 해 중복 클릭으로 다음 회차가 사라지는 것을 막는다.
        guard calendar.startOfDay(for: item.scheduledDate) <= calendar.startOfDay(for: now) else { return }
        history.insert(ActivityRecord(id: UUID(), task: item, date: now, kind: .completed), at: 0)
        if let next = item.repeatRule.nextDate(after: max(item.scheduledDate, now), calendar: calendar) {
            tasks[index].scheduledDate = next
        } else {
            tasks.remove(at: index)
        }
    }

    public mutating func delete(id: UUID, now: Date = Date()) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        let item = tasks.remove(at: index)
        history.insert(ActivityRecord(id: UUID(), task: item, date: now, kind: .deleted), at: 0)
    }

    public mutating func restore(recordID: UUID) {
        guard let index = history.firstIndex(where: { $0.id == recordID }) else { return }
        let record = history.remove(at: index)
        if let existing = tasks.firstIndex(where: { $0.id == record.task.id }) {
            tasks[existing].scheduledDate = min(tasks[existing].scheduledDate, record.task.scheduledDate)
        } else {
            tasks.append(record.task)
        }
    }

    private static func validTitle(_ title: String) throws -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TaskError.emptyTitle }
        guard trimmed.count <= 300 else { throw TaskError.longTitle }
        return trimmed
    }
}

public struct TaskRepository: Sendable {
    public let fileURL: URL
    public init(fileURL: URL) { self.fileURL = fileURL }

    public func load() throws -> TaskDocument {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return TaskDocument() }
        let document = try JSONDecoder().decode(TaskDocument.self, from: Data(contentsOf: fileURL))
        try document.validate()
        return document
    }

    public func transaction(_ update: (inout TaskDocument) throws -> Void) throws -> (before: TaskDocument, after: TaskDocument) {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let descriptor = Darwin.open(directory.appendingPathComponent("tasks.lock").path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
        defer { Darwin.close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw POSIXError(.EIO) }
        defer { flock(descriptor, LOCK_UN) }
        let previous = try load()
        var next = previous
        try update(&next)
        if previous != next { try save(next) }
        return (previous, next)
    }

    public func save(_ document: TaskDocument) throws {
        try document.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try data.write(to: fileURL, options: .atomic)
    }
}

public enum SharedTaskStorage {
    public static let widgetKind = "TookDesktopWidget"

    public static func repository(bundle: Bundle = .main) throws -> TaskRepository {
        let directory: URL
        if let testPath = ProcessInfo.processInfo.environment["TOOK_DATA_DIRECTORY"] {
            directory = URL(fileURLWithPath: testPath, isDirectory: true)
        } else if bundle.object(forInfoDictionaryKey: "TookStorageMode") as? String == "local" {
            // shortcut: 개인용 빌드는 전용 폴더만 공유한다. 배포 서명을 도입할 때 App Groups로 전환한다.
            guard let home = getpwuid(getuid())?.pointee.pw_dir else { throw TaskError.sharedContainerUnavailable }
            directory = URL(fileURLWithPath: String(cString: home), isDirectory: true)
                .appendingPathComponent("Library/Application Support/TookMac", isDirectory: true)
        } else if let group = bundle.object(forInfoDictionaryKey: "TookAppGroup") as? String, !group.isEmpty {
            guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
                throw TaskError.sharedContainerUnavailable
            }
            directory = container.appendingPathComponent("TookMac", isDirectory: true)
            // 첫 공유 저장소 전환에서만 기존 맥 버전 데이터를 복사한다. 원본은 보존한다.
            let old = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("TookMac/tasks.json")
            let target = directory.appendingPathComponent("tasks.json")
            if FileManager.default.fileExists(atPath: old.path), !FileManager.default.fileExists(atPath: target.path),
               bundle.bundleIdentifier == "local.tookmac.desktop" {
                let source = try TaskRepository(fileURL: old).load()
                _ = try TaskRepository(fileURL: target).transaction { current in
                    if current == TaskDocument() { current = source }
                }
            }
        } else {
            directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("TookMac", isDirectory: true)
        }
        return TaskRepository(fileURL: directory.appendingPathComponent("tasks.json"))
    }
}

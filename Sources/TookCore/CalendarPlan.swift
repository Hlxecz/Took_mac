import Foundation

public struct CalendarPlan: Codable, Equatable, Sendable {
    public let key: String
    public let title: String
    public let calendarTitle: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool

    public init(key: String, title: String, calendarTitle: String, start: Date, end: Date, isAllDay: Bool) {
        self.key = key
        self.title = title
        self.calendarTitle = calendarTitle
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
    }

    public static func window(from date: Date, calendar: Calendar = .current) -> DateInterval {
        let start = calendar.startOfDay(for: date)
        return DateInterval(start: start, end: calendar.date(byAdding: .day, value: 7, to: start)!)
    }

    public func reminderDate(calendar: Calendar = .current) -> Date {
        let day = calendar.date(byAdding: .day, value: -2, to: calendar.startOfDay(for: start))!
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day)!
    }
}

extension TaskDocument {
    public mutating func syncCalendarPlans(_ plans: [CalendarPlan], now: Date = Date(), calendar: Calendar = .current) throws {
        let window = CalendarPlan.window(from: now, calendar: calendar)
        var incoming: [String: CalendarPlan] = [:]
        for plan in plans where plan.end > window.start && plan.start < window.end {
            guard !plan.key.isEmpty, plan.end >= plan.start else { throw TaskError.invalidDocument }
            incoming[plan.key] = plan
        }
        suppressedCalendarPlans = suppressedCalendarPlans?.filter { $0.value > window.start }
        tasks.removeAll { task in
            guard let plan = task.calendarPlan else { return false }
            return incoming[plan.key] == nil || suppressedCalendarPlans?[plan.key] != nil
        }
        for plan in incoming.values.sorted(by: { $0.start == $1.start ? $0.key < $1.key : $0.start < $1.start }) {
            guard suppressedCalendarPlans?[plan.key] == nil else { continue }
            if let index = tasks.firstIndex(where: { $0.calendarPlan?.key == plan.key }) {
                tasks[index].title = plan.title
                tasks[index].scheduledDate = plan.start
                tasks[index].calendarPlan = plan
            } else {
                var task = TaskItem(title: plan.title, scheduledDate: plan.start, createdAt: now)
                task.calendarPlan = plan
                tasks.append(task)
            }
        }
        try validate()
    }
}

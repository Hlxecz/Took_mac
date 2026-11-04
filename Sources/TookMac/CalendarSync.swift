import AppKit
import Combine
import EventKit
import TookCore

struct CalendarChoice: Identifiable {
    let id: String
    let title: String
    let account: String
}

@MainActor
final class CalendarSync: ObservableObject {
    @Published private(set) var calendars: [CalendarChoice] = []
    @Published private(set) var selectedIDs: Set<String>
    @Published private(set) var authorized = false
    @Published private(set) var requesting = false
    @Published private(set) var status = "맥 캘린더에 연결된 구글 일정을 가져올 수 있어요."
    @Published private(set) var lastSynced: Date?
    private let events = EKEventStore()
    private let store: TaskStore
    private var subscriptions = Set<AnyCancellable>()

    init(store: TaskStore) {
        self.store = store
        selectedIDs = Set(UserDefaults.standard.stringArray(forKey: "calendarIDs") ?? [])
        NotificationCenter.default.publisher(for: .EKEventStoreChanged, object: events)
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }.store(in: &subscriptions)
        Timer.publish(every: 300, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.refresh() }.store(in: &subscriptions)
        refresh()
    }

    func connect() {
        guard !requesting else { return }
        requesting = true
        events.requestFullAccessToEvents { [weak self] granted, error in
            let message = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.requesting = false
                if let message { self.status = "캘린더에 연결하지 못했어요: \(message)" }
                else if granted { self.refresh() }
                else { self.authorized = false; self.status = "시스템 설정 → 개인정보 보호 및 보안 → 캘린더에서 Took Mac을 허용해 주세요." }
            }
        }
    }

    func select(_ id: String, enabled: Bool) {
        if enabled { selectedIDs.insert(id) } else { selectedIDs.remove(id) }
        UserDefaults.standard.set(selectedIDs.sorted(), forKey: "calendarIDs")
        refresh()
    }

    func deselectAll() {
        selectedIDs = []
        UserDefaults.standard.removeObject(forKey: "calendarIDs")
        _ = store.syncCalendarPlans([], now: Date())
        refresh()
    }

    func refresh() {
        authorized = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        guard authorized else {
            calendars = []
            if !selectedIDs.isEmpty { status = "캘린더 권한이 필요해요. 기존에 가져온 일정은 유지됩니다." }
            return
        }
        let available = events.calendars(for: .event)
        calendars = available.sorted { ($0.source.title, $0.title) < ($1.source.title, $1.title) }
            .map { CalendarChoice(id: $0.calendarIdentifier, title: $0.title, account: $0.source.title) }
        let selected = available.filter { selectedIDs.contains($0.calendarIdentifier) }
        // 계정 동기화가 잠깐 끊겨도 캐시된 일정을 비우지 않는다.
        guard selectedIDs.isEmpty || Set(selected.map(\.calendarIdentifier)) == selectedIDs else {
            status = "선택한 캘린더를 찾을 수 없어요. 맥 캘린더의 계정 연결을 확인해 주세요."
            return
        }
        let now = Date()
        let window = CalendarPlan.window(from: now)
        let matching = selected.isEmpty ? [] : events.events(matching: events.predicateForEvents(withStart: window.start, end: window.end, calendars: selected))
        let plans = matching.filter { event in
            event.status != .canceled && !(event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false)
        }.map { event in
            // 반복 일정은 원래 회차 날짜를 키에 넣어 각 회차를 따로 완료한다.
            let identity = event.calendarItemExternalIdentifier ?? event.calendarItemIdentifier
            let occurrence = event.occurrenceDate ?? event.startDate!
            let key = "\(event.calendar.calendarIdentifier)|\(identity)|\(event.hasRecurrenceRules || event.isDetached ? String(occurrence.timeIntervalSince1970) : "single")"
            let title = (event.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return CalendarPlan(key: key, title: title.isEmpty ? "제목 없는 일정" : String(title.prefix(300)),
                                calendarTitle: event.calendar.title, start: event.startDate, end: event.endDate,
                                isAllDay: event.isAllDay)
        }
        if store.syncCalendarPlans(plans, now: now) {
            lastSynced = now
            status = selected.isEmpty ? "가져올 캘린더를 선택해 주세요." : "오늘부터 7일 일정 \(plans.count)개를 확인했어요."
        } else { status = "일정을 저장하지 못했어요. 계획 화면의 오류를 확인해 주세요." }
    }
}

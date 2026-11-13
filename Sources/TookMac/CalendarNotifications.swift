import AppKit
import Combine
import CryptoKit
import TookCore
import UserNotifications

@MainActor
final class CalendarNotifications: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var authorized = false
    @Published private(set) var requesting = false
    @Published private(set) var status = "캘린더 일정을 이틀 전 오전 9시에 알려드려요."
    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "calendarRemindersEnabled")
            if enabled { requestAccess() } else { refresh() }
        }
    }
    var openPlans: (() -> Void)?
    private let center = UNUserNotificationCenter.current()
    private let store: TaskStore
    private var subscription: AnyCancellable?
    private var revision = 0
    private var booking = Set<String>()
    private var booked: [String: Date]
    private static let prefix = "took.calendar."

    init(store: TaskStore) {
        self.store = store
        enabled = UserDefaults.standard.object(forKey: "calendarRemindersEnabled") as? Bool ?? true
        booked = UserDefaults.standard.dictionary(forKey: "calendarReminderBookings") as? [String: Date] ?? [:]
        super.init()
        center.delegate = self
        subscription = store.$document.debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
        refresh()
    }

    func requestAccess() {
        guard enabled, !requesting else { return }
        requesting = true
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] _, error in
            let message = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.requesting = false
                if let message { self.status = "알림을 허용하지 못했어요: \(message)" }
                self.refresh()
            }
        }
    }

    func refresh() {
        revision += 1
        let currentRevision = revision
        center.getNotificationSettings { [weak self] settings in
            let allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            Task { @MainActor [weak self] in
                guard let self, self.revision == currentRevision else { return }
                self.authorized = allowed
                self.status = allowed ? "이틀 전 오전 9시 알림 · 늦게 가져온 일정은 한 번 바로 알려드려요." : "알림 허용이 필요해요. 허용한 뒤에도 안 뜨면 시스템 설정의 Took Mac 알림을 확인해 주세요."
                self.schedule(revision: currentRevision)
            }
        }
    }

    func sendTest() {
        guard authorized else { requestAccess(); return }
        let content = UNMutableNotificationContent()
        content.title = "Took 알림이 연결됐어요"
        content.body = "캘린더 일정은 이틀 전 오전 9시에 알려드려요."
        content.sound = .default
        center.add(UNNotificationRequest(identifier: "took.notification-test", content: content,
                                         trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))) { [weak self] error in
            let message = error?.localizedDescription
            Task { @MainActor [weak self] in
                self?.status = message.map { "테스트 알림을 보내지 못했어요: \($0)" } ?? "테스트 알림을 보냈어요."
            }
        }
    }

    private func schedule(revision currentRevision: Int) {
        let now = Date()
        let plans = enabled && authorized ? store.document.tasks.compactMap(\.calendarPlan).filter { $0.start > now } : []
        let desired = Dictionary(uniqueKeysWithValues: plans.map { (Self.identifier(for: $0), $0) })
        center.getPendingNotificationRequests { [weak self] requests in
            let pending = Set(requests.map(\.identifier))
            Task { @MainActor [weak self] in
                guard let self, self.revision == currentRevision else { return }
                self.center.removePendingNotificationRequests(withIdentifiers: Array(pending.filter {
                    $0.hasPrefix(Self.prefix) && desired[$0] == nil
                }))
                self.booked = self.booked.filter { $0.value > Calendar.current.startOfDay(for: now) }
                for (id, plan) in desired {
                    let fire = plan.reminderDate()
                    // 이미 예약했던 알림은 앱 재실행이나 5분 갱신으로 다시 울리지 않는다.
                    if fire <= now && (self.booked[id] != nil || pending.contains(id)) { continue }
                    guard !self.booking.contains(id) else { continue }
                    let content = UNMutableNotificationContent()
                    content.title = "다가오는 계획"
                    content.body = "\(plan.title) · \(plan.start.formatted(.dateTime.month().day())) \(plan.isAllDay ? "종일" : plan.start.formatted(date: .omitted, time: .shortened))"
                    content.sound = .default
                    let trigger: UNNotificationTrigger
                    if fire > now {
                        trigger = UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire), repeats: false)
                    } else {
                        trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
                    }
                    self.booking.insert(id)
                    self.center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger)) { [weak self] error in
                        let message = error?.localizedDescription
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            self.booking.remove(id)
                            if let message { self.status = "알림을 예약하지 못했어요: \(message)" }
                            else {
                                self.booked[id] = plan.start
                                UserDefaults.standard.set(self.booked, forKey: "calendarReminderBookings")
                            }
                        }
                    }
                }
                UserDefaults.standard.set(self.booked, forKey: "calendarReminderBookings")
            }
        }
    }

    private static func identifier(for plan: CalendarPlan) -> String {
        let data = Data("\(plan.key)|\(plan.start.timeIntervalSince1970)".utf8)
        return prefix + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor [weak self] in self?.openPlans?() }
        completionHandler()
    }
}

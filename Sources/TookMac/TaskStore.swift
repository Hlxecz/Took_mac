import AppKit
import Combine
import TookCore
import WidgetKit

@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var document = TaskDocument()
    @Published private(set) var undoDocument: TaskDocument?
    @Published private(set) var notice: String?
    @Published var error: String?
    @Published private(set) var loadFailed = false
    let repository: TaskRepository?
    private var refreshSubscription: AnyCancellable?

    init() {
        do { repository = try SharedTaskStorage.repository() }
        catch {
            repository = nil
            loadFailed = true
            self.error = error.localizedDescription
        }
        if repository != nil { reload() }
        refreshSubscription = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    func reload() {
        guard let repository else { return }
        do {
            document = try repository.load()
            loadFailed = false
            error = nil
        } catch {
            loadFailed = true
            self.error = "할 일을 불러오지 못했습니다. 저장 파일을 확인한 뒤 다시 시도해 주세요.\n\(error.localizedDescription)"
        }
    }

    func refresh() {
        guard let repository, !loadFailed else { return }
        do {
            let latest = try repository.load()
            if latest != document {
                document = latest
                dismissNotice()
            }
        } catch {
            loadFailed = true
            self.error = error.localizedDescription
        }
    }

    @discardableResult
    func syncCalendarPlans(_ plans: [CalendarPlan], now: Date) -> Bool {
        guard let repository, !loadFailed else { return false }
        do {
            let result = try repository.transaction { try $0.syncCalendarPlans(plans, now: now) }
            if document != result.after {
                document = result.after
                // 자동 동기화 직전에 있던 되돌리기로 최신 캘린더 내용을 덮어쓰지 않는다.
                dismissNotice()
            }
            if result.before != result.after {
                WidgetCenter.shared.reloadTimelines(ofKind: SharedTaskStorage.widgetKind)
            }
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    @discardableResult
    func change(_ message: String, allowsUndo: Bool = true, _ update: (inout TaskDocument) throws -> Void) -> Bool {
        guard let repository, !loadFailed else { return false }
        do {
            let result = try repository.transaction(update)
            guard result.before != result.after else { return true }
            undoDocument = allowsUndo ? result.before : nil
            document = result.after
            notice = message
            WidgetCenter.shared.reloadTimelines(ofKind: SharedTaskStorage.widgetKind)
            return true
        } catch {
            self.error = "변경 사항을 저장하지 못했습니다.\n\(error.localizedDescription)"
            return false
        }
    }

    func undo() {
        guard let repository, let previous = undoDocument else { return }
        do {
            let expected = document
            let result = try repository.transaction { current in
                guard current == expected else { throw TaskError.externalChange }
                current = previous
            }
            document = result.after
            dismissNotice()
            WidgetCenter.shared.reloadTimelines(ofKind: SharedTaskStorage.widgetKind)
        } catch { self.error = error.localizedDescription; refresh() }
    }

    func dismissNotice() { undoDocument = nil; notice = nil }
    func openDataFolder() {
        if let repository { NSWorkspace.shared.open(repository.fileURL.deletingLastPathComponent()) }
    }
}

@MainActor
final class WidgetPreferences: ObservableObject {
    @Published var appearance: String {
        didSet { UserDefaults.standard.set(appearance, forKey: "appearance"); windowChanged?() }
    }
    @Published var knockEnabled: Bool {
        didSet { UserDefaults.standard.set(knockEnabled, forKey: "knockEnabled"); windowChanged?() }
    }
    @Published var knockThreshold: Double {
        didSet { UserDefaults.standard.set(knockThreshold, forKey: "knockThreshold"); windowChanged?() }
    }
    var windowChanged: (() -> Void)?
    init() {
        knockEnabled = UserDefaults.standard.bool(forKey: "knockEnabled")
        knockThreshold = UserDefaults.standard.object(forKey: "knockThreshold") as? Double ?? 0.045
        appearance = UserDefaults.standard.string(forKey: "appearance") ?? "system"
    }
}

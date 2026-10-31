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

    init() {
        do { repository = try SharedTaskStorage.repository() }
        catch {
            repository = nil
            loadFailed = true
            self.error = error.localizedDescription
        }
        if repository != nil { reload() }
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
    func change(_ message: String, _ update: (inout TaskDocument) throws -> Void) -> Bool {
        guard let repository, !loadFailed else { return false }
        do {
            let result = try repository.transaction(update)
            guard result.before != result.after else { return true }
            undoDocument = result.before
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
    @Published var alwaysOnTop: Bool {
        didSet { UserDefaults.standard.set(alwaysOnTop, forKey: "alwaysOnTop"); windowChanged?() }
    }
    @Published var appearance: String {
        didSet { UserDefaults.standard.set(appearance, forKey: "appearance"); windowChanged?() }
    }
    @Published var showDesktopWidget: Bool {
        didSet { UserDefaults.standard.set(showDesktopWidget, forKey: "showDesktopWidget"); windowChanged?() }
    }
    var windowChanged: (() -> Void)?
    init() {
        showDesktopWidget = UserDefaults.standard.object(forKey: "showDesktopWidget") as? Bool ?? false
        alwaysOnTop = UserDefaults.standard.bool(forKey: "alwaysOnTop")
        appearance = UserDefaults.standard.string(forKey: "appearance") ?? "system"
    }
}

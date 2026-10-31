import AppKit
import Combine
import TookCore

@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var document = TaskDocument()
    @Published private(set) var undoDocument: TaskDocument?
    @Published private(set) var notice: String?
    @Published var error: String?
    @Published private(set) var loadFailed = false
    let repository: TaskRepository

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory: URL
        if let testPath = ProcessInfo.processInfo.environment["TOOK_DATA_DIRECTORY"] {
            directory = URL(fileURLWithPath: testPath, isDirectory: true)
        } else {
            directory = support.appendingPathComponent("TookMac", isDirectory: true)
        }
        repository = TaskRepository(fileURL: directory.appendingPathComponent("tasks.json"))
        reload()
    }

    func reload() {
        do {
            document = try repository.load()
            loadFailed = false
            error = nil
        } catch {
            loadFailed = true
            self.error = "할 일을 불러오지 못했습니다. 저장 파일을 확인한 뒤 다시 시도해 주세요.\n\(error.localizedDescription)"
        }
    }

    @discardableResult
    func change(_ message: String, _ update: (inout TaskDocument) throws -> Void) -> Bool {
        guard !loadFailed else { return false }
        do {
            var next = document
            try update(&next)
            guard next != document else { return true }
            try repository.save(next)
            undoDocument = document
            document = next
            notice = message
            return true
        } catch {
            self.error = "변경 사항을 저장하지 못했습니다.\n\(error.localizedDescription)"
            return false
        }
    }

    func undo() {
        guard let previous = undoDocument else { return }
        do {
            try repository.save(previous)
            document = previous
            dismissNotice()
        } catch { self.error = error.localizedDescription }
    }

    func dismissNotice() { undoDocument = nil; notice = nil }
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
        showDesktopWidget = UserDefaults.standard.object(forKey: "showDesktopWidget") as? Bool ?? true
        alwaysOnTop = UserDefaults.standard.bool(forKey: "alwaysOnTop")
        appearance = UserDefaults.standard.string(forKey: "appearance") ?? "system"
    }
}

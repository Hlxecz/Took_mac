import AppIntents
import TookCore
import WidgetKit

struct CompleteTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "계획 완료"
    static let description = IntentDescription("완료한 계획을 위젯에서 숨깁니다.")
    static let openAppWhenRun = false
    @Parameter(title: "계획 ID") var taskID: String

    init() {}
    init(taskID: String) { self.taskID = taskID }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: taskID) else { return .result() }
        let repository = try SharedTaskStorage.repository()
        _ = try repository.transaction { $0.complete(id: id) }
        WidgetCenter.shared.reloadTimelines(ofKind: SharedTaskStorage.widgetKind)
        return .result()
    }
}

import AppKit
import WidgetKit
import TookCore

if CommandLine.arguments.contains("--widget-check") {
    var finished = false
    Task { @MainActor in
        do {
            let repository = try SharedTaskStorage.repository()
            let document = try repository.load()
            print("저장 파일: \(repository.fileURL.path)")
            print("활성 계획: \(document.tasks.count), 기록: \(document.history.count)")
            if #available(macOS 15.0, *) {
                let widgets = try await WidgetCenter.shared.currentConfigurations()
                print("바탕화면·알림 센터 위젯: \(widgets.count)")
                for widget in widgets { print("종류: \(widget.kind), 크기: \(widget.family)") }
            }
            WidgetCenter.shared.reloadAllTimelines()
            print("위젯 갱신 요청 전달")
        } catch { print("위젯 진단 실패: \(error.localizedDescription)") }
        finished = true
    }
    let deadline = Date().addingTimeInterval(15)
    while !finished && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
    exit(finished ? 0 : 1)
}

if let flag = CommandLine.arguments.firstIndex(of: "--motion-check") {
    let seconds = flag + 1 < CommandLine.arguments.count ? Double(CommandLine.arguments[flag + 1]) ?? 3 : 3
    let motion = MotionMonitor()
    motion.onDoubleKnock = { print("두 번 두드림 감지") }
    motion.start()
    RunLoop.current.run(until: Date().addingTimeInterval(min(max(seconds, 1), 60)))
    print("센서 상태: \(motion.status), 읽은 표본: \(motion.sampleCount), 두 번 두드림: \(motion.doubleKnockCount)")
    let received = motion.sampleCount > 0
    motion.stop()
    exit(received ? 0 : 1)
}
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()

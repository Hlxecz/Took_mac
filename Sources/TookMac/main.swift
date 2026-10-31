import AppKit

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

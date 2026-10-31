import AppKit
import Combine
import IOKit
import IOKit.hid
import TookCore

@MainActor
final class MotionMonitor: NSObject, ObservableObject {
    @Published private(set) var status = "두드리기 감지 꺼짐"
    @Published private(set) var sampleCount = 0
    @Published private(set) var doubleKnockCount = 0
    @Published private(set) var recentPeak = 0.0
    var onDoubleKnock: (() -> Void)?
    var threshold = 0.045 { didSet { detector.threshold = threshold } }
    private(set) var isRunning = false
    private var enabled = false
    private var sleeping = false
    private var device: IOHIDDevice?
    private var driver: io_service_t = 0
    private var oldInterval = 0
    private let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
    private var detector = DoubleKnockDetector()
    private var healthTimer: Timer?
    private var totalSamples = 0
    private var lastSampleAt = 0.0
    private var inputCheckedAt = 0.0
    private var inputSuppressed = false
    private var peak = 0.0

    override init() {
        super.init()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
    }

    func configure(enabled: Bool, threshold: Double) {
        self.enabled = enabled
        self.threshold = threshold
        if enabled && !sleeping { start() } else { stop() }
    }

    func start() {
        guard !isRunning else { return }
        detector = DoubleKnockDetector(threshold: threshold)
        totalSamples = 0; sampleCount = 0; peak = 0
        guard let service = Self.findAccelerometer(className: "AppleSPUHIDDevice") else {
            status = "이 맥에서 몸체 센서를 찾지 못했어요"
            return
        }
        defer { IOObjectRelease(service) }
        guard let sensor = IOHIDDeviceCreate(nil, service) else {
            status = "몸체 센서에 연결하지 못했어요"
            return
        }
        let opened = IOHIDDeviceOpen(sensor, 0)
        guard opened == kIOReturnSuccess else {
            status = "센서 접근 실패 (\(String(format: "0x%08x", UInt32(bitPattern: opened))))"
            return
        }
        device = sensor
        guard let driver = Self.findAccelerometer(className: "AppleSPUHIDDriver") else {
            stop(); status = "몸체 센서 드라이버를 찾지 못했어요"; return
        }
        self.driver = driver
        oldInterval = (IORegistryEntryCreateCFProperty(driver, "ReportInterval" as CFString, nil, 0)?.takeRetainedValue() as? NSNumber)?.intValue ?? 0
        IOHIDDeviceRegisterInputReportCallback(sensor, buffer, 4096, { context, result, _, _, _, report, length in
            guard result == kIOReturnSuccess, let context, length == 22 else { return }
            MainActor.assumeIsolated {
                Unmanaged<MotionMonitor>.fromOpaque(context).takeUnretainedValue().receive(Array(UnsafeBufferPointer(start: report, count: length)))
            }
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDDeviceScheduleWithRunLoop(sensor, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        // shortcut: SPU의 비공개 보고서 형식을 사용한다. OS 변경으로 읽기가 멈추면 상태를 표시하고 수동 열기를 유지한다.
        let activated = IORegistryEntrySetCFProperty(driver, "ReportInterval" as CFString, NSNumber(value: 1250))
        guard activated == kIOReturnSuccess else {
            stop(); status = "센서를 활성화하지 못했어요. 앱을 다시 실행해 주세요."; return
        }
        isRunning = true
        lastSampleAt = ProcessInfo.processInfo.systemUptime
        status = "몸체 센서 연결 중…"
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkStream() }
        }
        RunLoop.main.add(timer, forMode: .common)
        healthTimer = timer
    }

    func stop() {
        healthTimer?.invalidate(); healthTimer = nil
        if let device {
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDDeviceClose(device, 0)
            self.device = nil
        }
        if driver != 0 {
            let current = (IORegistryEntryCreateCFProperty(driver, "ReportInterval" as CFString, nil, 0)?.takeRetainedValue() as? NSNumber)?.intValue
            if current == 1250 { IORegistryEntrySetCFProperty(driver, "ReportInterval" as CFString, NSNumber(value: oldInterval)) }
            IOObjectRelease(driver); driver = 0
        }
        isRunning = false
        status = "두드리기 감지 꺼짐"
    }

    private func receive(_ report: [UInt8]) {
        guard let sample = AccelerometerSample(report: report) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        totalSamples += 1; lastSampleAt = now
        if now - inputCheckedAt >= 0.05 {
            inputCheckedAt = now
            // 입력 내용은 읽지 않고 마지막 키·클릭 이후 경과 시간만 확인한다.
            inputSuppressed = [CGEventType.keyDown, .leftMouseDown, .rightMouseDown].contains {
                CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) < 0.22
            }
        }
        let detected = detector.process(sample, at: now, inputSuppressed: inputSuppressed)
        peak = max(peak, detector.impulse)
        if detected {
            doubleKnockCount += 1
            onDoubleKnock?()
        }
    }

    private func checkStream() {
        guard ProcessInfo.processInfo.systemUptime - lastSampleAt < 3 else {
            stop(); status = "센서 응답이 없어요. 다시 연결해 주세요."; return
        }
        sampleCount = totalSamples
        recentPeak = peak; peak = 0
        if totalSamples > 0 { status = "감지 중 · 몸체를 톡톡 두드려 보세요" }
    }

    private static func findAccelerometer(className: String) -> io_service_t? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator) == kIOReturnSuccess else { return nil }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            let page = IORegistryEntryCreateCFProperty(service, "PrimaryUsagePage" as CFString, nil, 0)?.takeRetainedValue() as? NSNumber
            let usage = IORegistryEntryCreateCFProperty(service, "PrimaryUsage" as CFString, nil, 0)?.takeRetainedValue() as? NSNumber
            if page?.intValue == 0xFF00 && usage?.intValue == 3 { return service }
            IOObjectRelease(service)
        }
        return nil
    }

    @objc private func willSleep() { sleeping = true; stop() }
    @objc private func didWake() { sleeping = false; if enabled { start() } }
}

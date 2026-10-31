import Foundation

public struct AccelerometerSample: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let z: Double

    public init(x: Double, y: Double, z: Double) { self.x = x; self.y = y; self.z = z }

    public init?(report: [UInt8]) {
        guard report.count == 22 else { return nil }
        func axis(_ offset: Int) -> Double {
            let value = (0..<4).reduce(UInt32(0)) { $0 | (UInt32(report[offset + $1]) << ($1 * 8)) }
            return Double(Int32(bitPattern: value)) / 65536
        }
        self.init(x: axis(6), y: axis(10), z: axis(14))
    }
}

public struct DoubleKnockDetector: Sendable {
    public var threshold: Double
    public private(set) var impulse = 0.0
    private var gravity: AccelerometerSample?
    private var startedAt: TimeInterval?
    private var previousTime: TimeInterval?
    private var firstKnock: TimeInterval?
    private var lastOnset = -Double.infinity
    private var lastTrigger = -Double.infinity
    private var armed = true

    public init(threshold: Double = 0.045) { self.threshold = threshold }

    public mutating func process(_ sample: AccelerometerSample, at time: TimeInterval, inputSuppressed: Bool = false) -> Bool {
        guard sample.x.isFinite, sample.y.isFinite, sample.z.isFinite, time.isFinite,
              abs(sample.x) < 16, abs(sample.y) < 16, abs(sample.z) < 16 else { return false }
        guard let previousTime, time > previousTime, time - previousTime < 0.25,
              let oldGravity = gravity, let startedAt else {
            gravity = sample; startedAt = time; previousTime = time
            firstKnock = nil; armed = true; impulse = 0
            return false
        }
        let dt = time - previousTime
        self.previousTime = time
        let alpha = 1 - exp(-dt / 0.35)
        gravity = AccelerometerSample(x: oldGravity.x + alpha * (sample.x - oldGravity.x),
                                      y: oldGravity.y + alpha * (sample.y - oldGravity.y),
                                      z: oldGravity.z + alpha * (sample.z - oldGravity.z))
        let dx = sample.x - oldGravity.x, dy = sample.y - oldGravity.y, dz = sample.z - oldGravity.z
        impulse = sqrt(dx * dx + dy * dy + dz * dz)
        let minimum = max(0.015, min(threshold, 0.3))
        if let firstKnock, time - firstKnock > 0.5 { self.firstKnock = nil }
        guard time - startedAt >= 0.5, !inputSuppressed, impulse < 0.8 else {
            firstKnock = nil
            armed = false
            return false
        }
        if impulse < minimum * 0.4 { armed = true }
        guard armed, impulse >= minimum, time - lastOnset >= 0.1, time - lastTrigger >= 0.65 else { return false }
        armed = false
        lastOnset = time
        if let firstKnock, time - firstKnock >= 0.1, time - firstKnock <= 0.5 {
            self.firstKnock = nil
            lastTrigger = time
            return true
        }
        firstKnock = time
        return false
    }
}

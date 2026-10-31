import XCTest
@testable import TookCore

final class DoubleKnockDetectorTests: XCTestCase {
    private let rest = AccelerometerSample(x: 0, y: 0, z: -1)
    private let tap = AccelerometerSample(x: 0.02, y: 0, z: -0.86)

    private func warmed() -> DoubleKnockDetector {
        var detector = DoubleKnockDetector()
        for frame in 0...600 { XCTAssertFalse(detector.process(rest, at: Double(frame) / 1000)) }
        return detector
    }

    func testTwoDistinctKnocksTriggerOnceAndCooldownBlocksThird() {
        var detector = warmed()
        XCTAssertFalse(detector.process(tap, at: 0.61))
        XCTAssertFalse(detector.process(rest, at: 0.65))
        XCTAssertTrue(detector.process(tap, at: 0.81))
        XCTAssertFalse(detector.process(rest, at: 0.85))
        XCTAssertFalse(detector.process(tap, at: 1.01))
    }

    func testASecondDeliberatePairCanHideTheWindow() {
        var detector = warmed()
        XCTAssertFalse(detector.process(tap, at: 0.61))
        XCTAssertFalse(detector.process(rest, at: 0.65))
        XCTAssertTrue(detector.process(tap, at: 0.81))
        for frame in 850...1500 { XCTAssertFalse(detector.process(rest, at: Double(frame) / 1000)) }
        XCTAssertFalse(detector.process(tap, at: 1.51))
        XCTAssertFalse(detector.process(rest, at: 1.55))
        XCTAssertTrue(detector.process(tap, at: 1.71))
    }

    func testSingleHitAndRingingDoNotTrigger() {
        var detector = warmed()
        for frame in 601...900 {
            let ringing = frame < 680 && frame % 10 == 0
            XCTAssertFalse(detector.process(ringing ? tap : rest, at: Double(frame) / 1000))
        }
    }

    func testTypingAndLargeBumpsAreIgnored() {
        var detector = warmed()
        XCTAssertFalse(detector.process(tap, at: 0.61, inputSuppressed: true))
        XCTAssertFalse(detector.process(rest, at: 0.65))
        XCTAssertFalse(detector.process(tap, at: 0.81, inputSuppressed: true))
        XCTAssertFalse(detector.process(rest, at: 0.85))
        XCTAssertFalse(detector.process(AccelerometerSample(x: 0, y: 0, z: 1), at: 1.01))
        XCTAssertFalse(detector.process(tap, at: 1.1))
    }

    func testSlowPairAndResumeFromSleepDoNotTrigger() {
        var detector = warmed()
        XCTAssertFalse(detector.process(tap, at: 0.61))
        for frame in 650...1250 { XCTAssertFalse(detector.process(rest, at: Double(frame) / 1000)) }
        XCTAssertFalse(detector.process(tap, at: 1.26))
        XCTAssertFalse(detector.process(tap, at: 40))
        XCTAssertFalse(detector.process(tap, at: 40.2))
    }

    func testReportDecoderHandlesSignedAxesAndRejectsWrongLength() {
        var bytes = [UInt8](repeating: 0, count: 22)
        for (offset, value) in [(6, Int32(32768)), (10, Int32(-65536)), (14, Int32(131072))] {
            let raw = UInt32(bitPattern: value)
            for index in 0..<4 { bytes[offset + index] = UInt8(truncatingIfNeeded: raw >> (index * 8)) }
        }
        XCTAssertEqual(AccelerometerSample(report: bytes), AccelerometerSample(x: 0.5, y: -1, z: 2))
        XCTAssertNil(AccelerometerSample(report: Array(bytes.prefix(18))))
    }
}

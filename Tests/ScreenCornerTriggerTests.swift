import CoreGraphics
import XCTest
@testable import TookCore

final class ScreenCornerTriggerTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func testBothBottomCornersTriggerAfterBriefDwell() {
        for point in [CGPoint(x: 1, y: 1), CGPoint(x: 1439, y: 1)] {
            var trigger = ScreenCornerTrigger()
            XCTAssertFalse(trigger.update(pointer: point, screens: [screen], now: 0))
            XCTAssertFalse(trigger.update(pointer: point, screens: [screen], now: 0.2))
            XCTAssertTrue(trigger.update(pointer: point, screens: [screen], now: 0.3))
        }
    }

    func testTopCornersAndBottomMiddleDoNotTrigger() {
        for point in [CGPoint(x: 1, y: 899), CGPoint(x: 1439, y: 899), CGPoint(x: 720, y: 1), CGPoint(x: 9, y: 1)] {
            var trigger = ScreenCornerTrigger()
            XCTAssertFalse(trigger.update(pointer: point, screens: [screen], now: 0))
            XCTAssertFalse(trigger.update(pointer: point, screens: [screen], now: 1))
        }
    }

    func testTriggersOnceUntilPointerLeaves() {
        var trigger = ScreenCornerTrigger()
        let corner = CGPoint(x: 0, y: 0)
        XCTAssertFalse(trigger.update(pointer: corner, screens: [screen], now: 0))
        XCTAssertTrue(trigger.update(pointer: corner, screens: [screen], now: 0.3))
        XCTAssertFalse(trigger.update(pointer: corner, screens: [screen], now: 2))
        XCTAssertFalse(trigger.update(pointer: CGPoint(x: 20, y: 20), screens: [screen], now: 3))
        XCTAssertFalse(trigger.update(pointer: corner, screens: [screen], now: 4))
        XCTAssertTrue(trigger.update(pointer: corner, screens: [screen], now: 4.3))
    }

    func testPassingThroughCornerDoesNotOpenWidget() {
        var trigger = ScreenCornerTrigger()
        XCTAssertFalse(trigger.update(pointer: .zero, screens: [screen], now: 0))
        XCTAssertFalse(trigger.update(pointer: CGPoint(x: 20, y: 20), screens: [screen], now: 0.1))
        XCTAssertFalse(trigger.update(pointer: .zero, screens: [screen], now: 0.2))
        XCTAssertFalse(trigger.update(pointer: .zero, screens: [screen], now: 0.4))
        XCTAssertTrue(trigger.update(pointer: .zero, screens: [screen], now: 0.5))
    }

    func testSecondaryScreenUsesItsOwnOrigin() {
        let other = CGRect(x: -1920, y: -1080, width: 1920, height: 1080)
        for point in [CGPoint(x: -1919, y: -1079), CGPoint(x: -1, y: -1079)] {
            var trigger = ScreenCornerTrigger()
            XCTAssertFalse(trigger.update(pointer: point, screens: [screen, other], now: 0))
            XCTAssertTrue(trigger.update(pointer: point, screens: [screen, other], now: 0.3))
        }
    }

    func testChangingCornersStartsNewDwell() {
        var trigger = ScreenCornerTrigger()
        XCTAssertFalse(trigger.update(pointer: .zero, screens: [screen], now: 0))
        XCTAssertFalse(trigger.update(pointer: CGPoint(x: 1439, y: 1), screens: [screen], now: 0.2))
        XCTAssertFalse(trigger.update(pointer: CGPoint(x: 1439, y: 1), screens: [screen], now: 0.3))
        XCTAssertTrue(trigger.update(pointer: CGPoint(x: 1439, y: 1), screens: [screen], now: 0.5))
    }
}

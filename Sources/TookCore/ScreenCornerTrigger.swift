import CoreGraphics
import Foundation

public struct ScreenCornerTrigger {
    private var activeCorner: CGRect?
    private var enteredAt: TimeInterval = 0
    private var triggered = false

    public init() {}

    public mutating func update(pointer: CGPoint, screens: [CGRect], now: TimeInterval) -> Bool {
        let corner = screens.flatMap { screen in
            [CGRect(x: screen.minX, y: screen.minY, width: 8, height: 8),
             CGRect(x: screen.maxX - 8, y: screen.minY, width: 8, height: 8)]
        }.first { $0.contains(pointer) }
        guard let corner else {
            activeCorner = nil
            triggered = false
            return false
        }
        if activeCorner != corner {
            activeCorner = corner
            enteredAt = now
            triggered = false
        }
        guard !triggered, now - enteredAt >= 0.25 else { return false }
        triggered = true
        return true
    }
}

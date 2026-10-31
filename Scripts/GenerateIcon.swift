import AppKit

let output = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = base * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current!.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        NSColor(calibratedRed: 0.97, green: 0.51, blue: 0.43, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 52, y: 52, width: 920, height: 920), xRadius: 212, yRadius: 212).fill()
        NSColor.white.withAlphaComponent(0.22).setStroke()
        let circle = NSBezierPath(ovalIn: NSRect(x: 232, y: 232, width: 560, height: 560))
        circle.lineWidth = 20
        circle.stroke()
        NSColor.white.setStroke()
        let check = NSBezierPath()
        check.move(to: NSPoint(x: 340, y: 505))
        check.line(to: NSPoint(x: 467, y: 378))
        check.line(to: NSPoint(x: 700, y: 637))
        check.lineWidth = 67
        check.lineCapStyle = .round
        check.lineJoinStyle = .round
        check.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(output)/icon_\(base)x\(base)\(suffix).png"))
    }
}

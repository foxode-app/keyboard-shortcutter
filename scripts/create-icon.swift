import AppKit

// Rebuild with: scripts/swift-env.sh xcrun swift scripts/create-icon.swift
// All artwork is drawn here; no downloaded assets or font files are required.
let projectURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
let iconsetURL = projectURL.appendingPathComponent("build/KeyboardShortcutter.iconset")
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

func color(_ hex: UInt32) -> NSColor {
    NSColor(
        red: CGFloat((hex >> 16) & 255) / 255,
        green: CGFloat((hex >> 8) & 255) / 255,
        blue: CGFloat(hex & 255) / 255, alpha: 1
    )
}

func rounded(_ rect: NSRect, radius: CGFloat, fill: NSColor) {
    fill.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

func key(_ rect: NSRect, accent: Bool = false) {
    rounded(rect.offsetBy(dx: 0, dy: -9), radius: 20, fill: color(accent ? 0xB04B36 : 0xADB5BF))
    let path = NSBezierPath(roundedRect: rect, xRadius: 20, yRadius: 20)
    NSGradient(colors: accent ? [color(0xE77551), color(0xF39871)] : [color(0xE8ECEF), color(0xFFFFFF)])!
        .draw(in: path, angle: 90)
}

func render(size: Int) throws -> Data {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    context.imageInterpolation = .high

    let tile = NSBezierPath(
        roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 202, yRadius: 202)
    NSGradient(colors: [color(0xE4E8F0), color(0xF9F5F0)])!.draw(in: tile, angle: 75)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x1D2336).withAlphaComponent(0.25)
    shadow.shadowBlurRadius = 36
    shadow.shadowOffset = NSSize(width: 0, height: -22)
    shadow.set()
    rounded(NSRect(x: 126, y: 250, width: 772, height: 524), radius: 88, fill: color(0x293548))
    NSGraphicsContext.restoreGraphicsState()

    let keyboard = NSBezierPath(
        roundedRect: NSRect(x: 126, y: 266, width: 772, height: 508), xRadius: 88, yRadius: 88)
    NSGradient(colors: [color(0x293344), color(0x465368)])!.draw(in: keyboard, angle: 90)
    color(0xFFFFFF).withAlphaComponent(0.13).setStroke()
    keyboard.lineWidth = 3
    keyboard.stroke()

    for row in 0..<2 {
        for column in 0..<6 {
            key(NSRect(x: 181 + column * 114, y: 620 - row * 118, width: 91, height: 80))
        }
    }
    let option = NSRect(x: 181, y: 380, width: 132, height: 80)
    key(option, accent: true)
    key(NSRect(x: 335, y: 380, width: 356, height: 80))
    key(NSRect(x: 713, y: 380, width: 129, height: 80))

    // Option is drawn as a vector to remain crisp at every icon size.
    let symbol = NSBezierPath()
    symbol.move(to: NSPoint(x: 210, y: 438))
    symbol.line(to: NSPoint(x: 235, y: 438))
    symbol.line(to: NSPoint(x: 259, y: 402))
    symbol.line(to: NSPoint(x: 285, y: 402))
    symbol.move(to: NSPoint(x: 260, y: 438))
    symbol.line(to: NSPoint(x: 285, y: 438))
    symbol.lineWidth = 8
    symbol.lineCapStyle = .round
    symbol.lineJoinStyle = .round
    NSColor.white.setStroke()
    symbol.stroke()

    let returnArrow = NSBezierPath()
    returnArrow.move(to: NSPoint(x: 804, y: 435))
    returnArrow.line(to: NSPoint(x: 804, y: 415))
    returnArrow.line(to: NSPoint(x: 752, y: 415))
    returnArrow.move(to: NSPoint(x: 766, y: 429))
    returnArrow.line(to: NSPoint(x: 752, y: 415))
    returnArrow.line(to: NSPoint(x: 766, y: 401))
    returnArrow.lineWidth = 7
    returnArrow.lineCapStyle = .round
    returnArrow.lineJoinStyle = .round
    color(0x536176).setStroke()
    returnArrow.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        try render(size: points * scale).write(
            to: iconsetURL.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}
let conversion = Process()
conversion.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
conversion.arguments = [
    "-c", "icns", iconsetURL.path,
    "-o", projectURL.appendingPathComponent("Resources/KeyboardShortcutter.icns").path,
]
try conversion.run()
conversion.waitUntilExit()
guard conversion.terminationStatus == 0 else { exit(conversion.terminationStatus) }
print("Generated Resources/KeyboardShortcutter.icns")

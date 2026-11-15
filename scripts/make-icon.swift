// Draws the DisplayLab app icon and writes an .iconset folder.
// Usage: swift scripts/make-icon.swift <out.iconset>   then: iconutil -c icns <out.iconset> -o AppIcon.icns
import AppKit

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func rounded(_ r: NSRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
}

/// Draws on a 1024×1024 canvas (origin bottom-left), following Apple's macOS icon grid (824pt tile).
func drawIcon() {
    // Tile with soft drop shadow
    let tile = rounded(NSRect(x: 100, y: 100, width: 824, height: 824), 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.shadowBlurRadius = 28
    shadow.set()
    NSColor.white.setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    tile.addClip()
    NSGradient(starting: rgb(0xFFFFFF), ending: rgb(0xE8ECF3))!.draw(in: tile, angle: -90)
    NSGraphicsContext.restoreGraphicsState()
    // Hairline edge so the white tile still reads on a white Finder window
    rgb(0x000000, 0.08).setStroke()
    let edge = rounded(NSRect(x: 101, y: 101, width: 822, height: 822), 184)
    edge.lineWidth = 2
    edge.stroke()

    // Monitor: stand
    rgb(0x1E2638).setFill()
    rounded(NSRect(x: 468, y: 286, width: 88, height: 90), 10).fill()
    rounded(NSRect(x: 356, y: 250, width: 312, height: 52), 26).fill()

    // Monitor: bezel + screen
    let bezel = NSRect(x: 196, y: 352, width: 632, height: 420)
    NSGraphicsContext.saveGraphicsState()
    let bezelShadow = NSShadow()
    bezelShadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    bezelShadow.shadowOffset = NSSize(width: 0, height: -8)
    bezelShadow.shadowBlurRadius = 18
    bezelShadow.set()
    rgb(0x1E2638).setFill()
    rounded(bezel, 64).fill()
    NSGraphicsContext.restoreGraphicsState()

    let screen = bezel.insetBy(dx: 30, dy: 30)
    let screenPath = rounded(screen, 38)
    NSGradient(starting: rgb(0x5BA2FF), ending: rgb(0x3240D8))!.draw(in: screenPath, angle: -90)

    // Slider inside the screen (echoes the app's capsule slider)
    let track = NSRect(x: screen.minX + 70, y: screen.midY - 32, width: screen.width - 140, height: 64)
    NSColor.white.withAlphaComponent(0.28).setFill()
    rounded(track, 32).fill()
    let fillWidth = track.width * 0.62
    NSColor.white.withAlphaComponent(0.92).setFill()
    rounded(NSRect(x: track.minX, y: track.minY, width: fillWidth, height: track.height), 32).fill()

    NSGraphicsContext.saveGraphicsState()
    let knobShadow = NSShadow()
    knobShadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    knobShadow.shadowOffset = NSSize(width: 0, height: -4)
    knobShadow.shadowBlurRadius = 10
    knobShadow.set()
    NSColor.white.setFill()
    let knob: CGFloat = 92
    NSBezierPath(ovalIn: NSRect(x: track.minX + fillWidth - knob / 2, y: track.midY - knob / 2,
                                width: knob, height: knob)).fill()
    NSGraphicsContext.restoreGraphicsState()
}

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = CGFloat(pixels) / 1024
    NSAffineTransform(transform: { let t = NSAffineTransform(); t.scale(by: scale); return t }() as AffineTransform).concat()
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(pixels: base).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(pixels: base * 2).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
print("wrote \(out.path)")

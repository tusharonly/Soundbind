// Draws the disk image window background: swift scripts/dmg/generate_background.swift scripts/dmg
// Writes background.png (660x400) and background@2x.png. The icons sit at x 170 and x 490, y 185.
import AppKit

let size = NSSize(width: 660, height: 400)
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

func color(_ hex: Int, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

for scale in [1, 2] {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // A mid fuchsia, so Finder's icon labels stay readable whether they are black (light mode) or white (dark mode).
    NSGradient(starting: color(0xC078D2), ending: color(0xAA5CC0))!
        .draw(in: NSRect(origin: .zero, size: size), angle: -90)

    // The logo's sound waves, large and faint, in the top-right corner.
    let waves = NSBezierPath()
    for radius in [120, 190, 260] as [CGFloat] {
        let arc = NSBezierPath()
        arc.appendArc(withCenter: NSPoint(x: size.width + 20, y: size.height + 20), radius: radius, startAngle: 180, endAngle: 270)
        waves.append(arc)
    }
    waves.lineWidth = 34
    waves.lineCapStyle = .round
    color(0x292524, 0.10).setStroke()
    waves.stroke()

    // Arrow from the app to the Applications folder. Coordinates here are y-up; the icon row is at y = 215.
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 270, y: 222))
    arrow.line(to: NSPoint(x: 386, y: 222))
    arrow.move(to: NSPoint(x: 366, y: 242))
    arrow.line(to: NSPoint(x: 388, y: 222))
    arrow.line(to: NSPoint(x: 366, y: 202))
    arrow.lineWidth = 11
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    color(0x292524).setStroke()
    arrow.stroke()

    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let caption = NSAttributedString(string: "Drag Soundbind into Applications", attributes: [
        .font: NSFont.systemFont(ofSize: 19, weight: .bold),
        .foregroundColor: color(0xFFF7ED),
        .paragraphStyle: style,
        .kern: -0.3,
    ])
    caption.draw(in: NSRect(x: 0, y: 44, width: size.width, height: 28))

    NSGraphicsContext.current = nil
    let name = scale == 1 ? "background.png" : "background@2x.png"
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outDir).appendingPathComponent(name))
}

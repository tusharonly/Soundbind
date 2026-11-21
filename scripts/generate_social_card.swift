// Draws the 1200x630 link-preview image for the website:
//   swift scripts/generate_social_card.swift card.png && sips -s format jpeg -s formatOptions 86 card.png --out site/images/social-card.jpg
import AppKit

let size = NSSize(width: 1200, height: 630)
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "social-card.png"
let iconPath = "Soundbind/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png"

func color(_ hex: Int, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

NSGradient(starting: color(0xF6C3FE), ending: color(0xE592F5))!.draw(in: NSRect(origin: .zero, size: size), angle: -50)

// The logo's sound waves, spreading from the bottom-right corner.
for (index, radius) in ([220, 360, 500, 640] as [CGFloat]).enumerated() {
    let arc = NSBezierPath()
    arc.appendArc(withCenter: NSPoint(x: size.width + 40, y: -40), radius: radius, startAngle: 90, endAngle: 180)
    arc.lineWidth = 46
    arc.lineCapStyle = .round
    color(0xFFF7ED, 0.34 - CGFloat(index) * 0.06).setStroke()
    arc.stroke()
}

if let icon = NSImage(contentsOfFile: iconPath) {
    icon.draw(in: NSRect(x: 70, y: 418, width: 150, height: 150))
}
func draw(_ text: String, size fontSize: CGFloat, weight: NSFont.Weight, hex: Int, at point: NSPoint, kern: CGFloat = 0) {
    NSAttributedString(string: text, attributes: [
        .font: NSFont.systemFont(ofSize: fontSize, weight: weight),
        .foregroundColor: color(hex),
        .kern: kern,
    ]).draw(at: point)
}
draw("Soundbind", size: 54, weight: .heavy, hex: 0x292524, at: NSPoint(x: 228, y: 458), kern: -1.5)
draw("Drop in a sound.", size: 118, weight: .black, hex: 0x292524, at: NSPoint(x: 80, y: 252), kern: -5)
draw("Bind a key. Done.", size: 118, weight: .black, hex: 0x292524, at: NSPoint(x: 80, y: 122), kern: -5)
draw("A free menu bar soundboard for Mac", size: 38, weight: .semibold, hex: 0x292524, at: NSPoint(x: 86, y: 52), kern: -0.6)

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))

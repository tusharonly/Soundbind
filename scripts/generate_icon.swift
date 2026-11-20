// Generates the placeholder Soundbind app icon (a keycap with a waveform glyph).
// Usage: swift scripts/generate_icon.swift Soundbind/Resources/Assets.xcassets/AppIcon.appiconset
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [r / 255, g / 255, b / 255, a])!
}

func roundedRect(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func drawIcon(size: Int) -> CGImage {
    let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    // Draw in a 1024-point design space.
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)

    // Background tile (macOS icon grid: 824pt tile inside a 1024pt canvas).
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = roundedRect(tile, 186)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0, 0, 0, 0.3))
    context.addPath(tilePath)
    context.setFillColor(color(74, 58, 255))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    let background = CGGradient(
        colorsSpace: colorSpace,
        colors: [color(124, 92, 255), color(58, 44, 190)] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(background, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    context.restoreGState()

    // Keycap: a darker base (the sides) with a lighter top face sitting slightly higher.
    let base = CGRect(x: 252, y: 236, width: 520, height: 520)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -18), blur: 36, color: color(20, 10, 80, 0.45))
    context.addPath(roundedRect(base, 112))
    context.setFillColor(color(206, 204, 232))
    context.fillPath()
    context.restoreGState()

    let face = CGRect(x: 282, y: 300, width: 460, height: 432)
    context.saveGState()
    context.addPath(roundedRect(face, 88))
    context.clip()
    let faceGradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [color(255, 255, 255), color(238, 237, 250)] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(faceGradient, start: CGPoint(x: 512, y: face.maxY), end: CGPoint(x: 512, y: face.minY), options: [])
    context.restoreGState()

    // Waveform glyph on the key face.
    let heights: [CGFloat] = [96, 190, 280, 150, 232, 110]
    let barWidth: CGFloat = 38
    let gap: CGFloat = 26
    let totalWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
    var x = face.midX - totalWidth / 2
    context.setFillColor(color(88, 66, 232))
    for height in heights {
        let bar = CGRect(x: x, y: face.midY - height / 2, width: barWidth, height: height)
        context.addPath(roundedRect(bar, barWidth / 2))
        context.fillPath()
        x += barWidth + gap
    }

    return context.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Could not write \(url.path)") }
}

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

// (point size, scale)
let slots: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
var entries: [String] = []
for (points, scale) in slots {
    let pixels = points * scale
    let fileName = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    writePNG(drawIcon(size: pixels), to: outputDirectory.appendingPathComponent(fileName))
    entries.append("""
        { "filename" : "\(fileName)", "idiom" : "mac", "scale" : "\(scale)x", "size" : "\(points)x\(points)" }
    """)
}

let contents = """
{
  "images" : [
\(entries.joined(separator: ",\n"))
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}

"""
try contents.write(to: outputDirectory.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("Wrote \(slots.count) icons to \(outputDirectory.path)")

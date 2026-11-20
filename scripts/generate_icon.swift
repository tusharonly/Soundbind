// Generates the Soundbind app icon (a key throwing sound waves across a fuchsia tile).
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
    // Work in a 1024-point canvas first.
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)

    let ink = color(41, 37, 36)
    let cream = color(255, 247, 237)

    // Background tile (macOS icon grid: 824pt tile inside a 1024pt canvas).
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = roundedRect(tile, 186)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0, 0, 0, 0.3))
    context.addPath(tilePath)
    context.setFillColor(color(240, 171, 252))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    let background = CGGradient(
        colorsSpace: colorSpace,
        colors: [color(247, 196, 255), color(232, 146, 248)] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(background, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    context.restoreGState()

    // The artwork is designed on a 120-unit grid with the origin at the tile's top left.
    context.translateBy(x: tile.minX, y: tile.maxY)
    context.scaleBy(x: tile.width / 120, y: -tile.height / 120)

    // Key: a darker base (the sides) with the top face sitting slightly higher.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: color(110, 30, 130, 0.45))
    context.addPath(roundedRect(CGRect(x: 18, y: 62, width: 42, height: 42), 11))
    context.setFillColor(color(12, 10, 9))
    context.fillPath()
    context.restoreGState()

    let face = CGRect(x: 18, y: 58, width: 42, height: 40)
    context.saveGState()
    context.addPath(roundedRect(face, 11))
    context.clip()
    let faceGradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [color(68, 62, 58), ink] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(faceGradient, start: CGPoint(x: 39, y: face.minY), end: CGPoint(x: 39, y: face.maxY), options: [])
    context.restoreGState()

    context.setFillColor(cream)
    context.fillEllipse(in: CGRect(x: 33, y: 72, width: 12, height: 12))

    // Sound waves leaving the key's top right corner.
    context.setStrokeColor(ink)
    context.setLineWidth(7)
    context.setLineCap(.round)
    for radius: CGFloat in [16, 30, 44] {
        context.addArc(center: CGPoint(x: 62, y: 60), radius: radius, startAngle: -.pi / 2, endAngle: 0, clockwise: false)
        context.strokePath()
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

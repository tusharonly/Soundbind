import AppKit

/// The menu bar glyph: the app icon's "Loud key" (a key throwing sound waves), drawn as a
/// template image so it follows the menu bar's light, dark and highlighted appearances.
enum MenuBarIcon {
    /// Key and waves on a clear background.
    static let idle = make(filled: false)
    /// The same glyph knocked out of a solid tile, shown briefly when a hotkey fires.
    static let active = make(filled: true)

    private static let pointSize: CGFloat = 18

    private static func make(filled: Bool) -> NSImage {
        let size = NSSize(width: pointSize, height: pointSize)
        let image = NSImage(size: size, flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            NSColor.black.set()

            // The glyph is laid out in the app icon's 120-unit space, where it spans
            // roughly x 18...110 and y 12...102, and is scaled to fit the menu bar.
            let glyphSpan: CGFloat = 92
            let glyphCenter = CGPoint(x: 64, y: 57)
            let scale = (filled ? 12.5 : 16.5) / glyphSpan

            if filled {
                NSBezierPath(roundedRect: rect, xRadius: 4.5, yRadius: 4.5).fill()
            }

            context.saveGState()
            context.translateBy(x: rect.midX, y: rect.midY)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -glyphCenter.x, y: -glyphCenter.y)

            let key = NSBezierPath(roundedRect: NSRect(x: 18, y: 60, width: 42, height: 42), xRadius: 11, yRadius: 11)
            let dot = NSBezierPath(ovalIn: NSRect(x: 32, y: 74, width: 14, height: 14))
            let waves = NSBezierPath()
            for radius in [16, 30, 44] as [CGFloat] {
                let arc = NSBezierPath()
                arc.appendArc(withCenter: NSPoint(x: 62, y: 60), radius: radius, startAngle: 270, endAngle: 360)
                waves.append(arc)
            }
            waves.lineWidth = filled ? 9 : 8
            waves.lineCapStyle = .round

            // Idle: solid key and waves with the dot cut out. Active: the reverse, cut from the tile.
            context.setBlendMode(filled ? .destinationOut : .normal)
            key.fill()
            waves.stroke()
            context.setBlendMode(filled ? .normal : .destinationOut)
            dot.fill()
            context.restoreGState()
            return true
        }
        image.isTemplate = true
        return image
    }
}

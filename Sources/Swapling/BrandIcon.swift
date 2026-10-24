import AppKit

/// Island Spirit's asymmetric silhouette, optically simplified for the menu bar.
enum BrandIcon {
    static let menuBarImage: NSImage = {
        let image = NSImage(size: NSSize(width: 22, height: 18), flipped: true) { bounds in
            drawMark(in: bounds, color: .black)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Swapling"
        return image
    }()

    /// Coordinates use a top-left origin, matching the editable SVG master.
    static func drawMark(in rect: NSRect, color: NSColor) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }
        let scale = min(rect.width / 24, rect.height / 20)
        context.translateBy(x: rect.midX - 12 * scale, y: rect.midY - 10 * scale)
        context.scaleBy(x: scale, y: scale)

        let spirit = NSBezierPath()
        spirit.move(to: NSPoint(x: 1, y: 12))
        spirit.curve(to: NSPoint(x: 10.2, y: 3),
                     controlPoint1: NSPoint(x: 1, y: 8), controlPoint2: NSPoint(x: 6, y: 3))
        spirit.curve(to: NSPoint(x: 18.7, y: 4.5),
                     controlPoint1: NSPoint(x: 14, y: 3), controlPoint2: NSPoint(x: 16.7, y: 6))
        spirit.curve(to: NSPoint(x: 22, y: 3),
                     controlPoint1: NSPoint(x: 20.5, y: 3.6), controlPoint2: NSPoint(x: 21.2, y: 2.2))
        spirit.curve(to: NSPoint(x: 22.3, y: 9),
                     controlPoint1: NSPoint(x: 22.9, y: 3.9), controlPoint2: NSPoint(x: 21.7, y: 6.8))
        spirit.curve(to: NSPoint(x: 21.5, y: 15.1),
                     controlPoint1: NSPoint(x: 23, y: 11.3), controlPoint2: NSPoint(x: 23.2, y: 13.4))
        spirit.curve(to: NSPoint(x: 13.8, y: 16.4),
                     controlPoint1: NSPoint(x: 19.7, y: 17.1), controlPoint2: NSPoint(x: 16.6, y: 17.5))
        spirit.curve(to: NSPoint(x: 9.3, y: 16.3),
                     controlPoint1: NSPoint(x: 12.2, y: 15.8), controlPoint2: NSPoint(x: 11.2, y: 15.6))
        spirit.curve(to: NSPoint(x: 2.1, y: 15.5),
                     controlPoint1: NSPoint(x: 6.7, y: 17.4), controlPoint2: NSPoint(x: 3.8, y: 17.2))
        spirit.curve(to: NSPoint(x: 1, y: 12),
                     controlPoint1: NSPoint(x: 1.2, y: 14.7), controlPoint2: NSPoint(x: 1, y: 13.3))
        spirit.close()
        // True holes let the menu-bar material show through in every system appearance.
        spirit.windingRule = .evenOdd
        spirit.appendOval(in: NSRect(x: 7.9, y: 9.5, width: 1.95, height: 2.9))
        spirit.appendOval(in: NSRect(x: 13.9, y: 9.45, width: 1.95, height: 2.9))
        color.setFill()
        spirit.fill()
    }
}

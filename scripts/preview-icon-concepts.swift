import AppKit

@main
enum IconConcepts {
    static let output = URL(fileURLWithPath: "Resources/Brand/Concepts", isDirectory: true)

    static func render(_ width: Int, _ height: Int, name: String, draw: () -> Void) throws {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        draw()
        NSGraphicsContext.restoreGraphicsState()
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
    }

    static func color(_ hex: Int) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
    }

    static func text(_ value: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat,
                     _ hex: Int = 0x252525, _ weight: NSFont.Weight = .regular) {
        (value as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color(hex),
        ])
    }

    static func mark(_ index: Int, _ rect: NSRect, _ ink: NSColor) {
        let context = NSGraphicsContext.current!.cgContext
        context.saveGState()
        defer { context.restoreGState() }
        let scale = min(rect.width / 24, rect.height / 20)
        context.translateBy(x: rect.midX - 12 * scale, y: rect.midY - 10 * scale)
        context.scaleBy(x: scale, y: scale)
        ink.setFill()
        ink.setStroke()
        if index == 0 {
            let p = NSBezierPath()
            p.move(to: NSPoint(x: 3, y: 6.8))
            p.line(to: NSPoint(x: 10.6, y: 2.5))
            p.curve(to: NSPoint(x: 13.4, y: 2.5), controlPoint1: NSPoint(x: 11.5, y: 2), controlPoint2: NSPoint(x: 12.5, y: 2))
            p.line(to: NSPoint(x: 21, y: 6.8))
            p.curve(to: NSPoint(x: 21, y: 9.2), controlPoint1: NSPoint(x: 22.4, y: 7.6), controlPoint2: NSPoint(x: 22.4, y: 8.4))
            p.line(to: NSPoint(x: 13.4, y: 13.5))
            p.curve(to: NSPoint(x: 10.6, y: 13.5), controlPoint1: NSPoint(x: 12.5, y: 14), controlPoint2: NSPoint(x: 11.5, y: 14))
            p.line(to: NSPoint(x: 3, y: 9.2))
            p.curve(to: NSPoint(x: 3, y: 6.8), controlPoint1: NSPoint(x: 1.6, y: 8.4), controlPoint2: NSPoint(x: 1.6, y: 7.6))
            p.close()
            p.fill()
            let base = NSBezierPath()
            base.move(to: NSPoint(x: 3, y: 13))
            base.line(to: NSPoint(x: 10.6, y: 17.3))
            base.curve(to: NSPoint(x: 13.4, y: 17.3), controlPoint1: NSPoint(x: 11.5, y: 17.8), controlPoint2: NSPoint(x: 12.5, y: 17.8))
            base.line(to: NSPoint(x: 21, y: 13))
            base.lineWidth = 2.4
            base.lineCapStyle = .round
            base.lineJoinStyle = .round
            base.stroke()
        } else if index == 1 {
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            NSBezierPath(ovalIn: NSRect(x: 4.8, y: 2.8, width: 14.4, height: 14.4)).fill()
            context.saveGState()
            context.translateBy(x: 12, y: 10)
            context.rotate(by: -.pi * 26 / 180)
            let orbit = NSBezierPath(ovalIn: NSRect(x: -10.5, y: -3.4, width: 21, height: 6.8))
            context.setBlendMode(.clear)
            orbit.lineWidth = 4.8
            orbit.stroke()
            context.setBlendMode(.normal)
            ink.setStroke()
            orbit.lineWidth = 2
            orbit.stroke()
            context.restoreGState()
            context.endTransparencyLayer()
        } else {
            let frame = NSBezierPath(roundedRect: NSRect(x: 1.4, y: 2.4, width: 21.2, height: 15.2), xRadius: 4, yRadius: 4)
            frame.lineWidth = 2.2
            frame.stroke()
            NSBezierPath(roundedRect: NSRect(x: 7, y: 1.8, width: 10, height: 5.4), xRadius: 2, yRadius: 2).fill()
        }
    }

    static func main() throws {
        for index in 0..<3 {
            try render(96, 80, name: "0\(index + 1)-mark.png") {
                mark(index, NSRect(x: 0, y: 0, width: 96, height: 80), .black)
            }
        }
        try render(1560, 1080, name: "directions.png") {
            color(0xF4F3EF).setFill()
            NSRect(x: 0, y: 0, width: 1560, height: 1080).fill()
            text("Swapling", 80, 54, 28, 0x202421, .semibold)
            text("重新从轮廓开始。", 80, 101, 18, 0x757A73)
            text("ICON EXPLORATIONS / 02", 1195, 70, 12, 0x757A73, .medium)
            let titles = ["01   浮屿", "02   引力", "03   刘海"]
            let subtitles = ["ISLET", "ORBIT", "NOTCH"]
            let descriptions = ["层叠的岛体，轻轻悬浮。", "一颗小行星，自带运行轨道。", "把 MacBook 的刘海变成标记。"]
            let colors = [0xC8F4D4, 0xC6D2FF, 0xF1E3C9]
            for index in 0..<3 {
                let x = CGFloat(80 + index * 490)
                text(titles[index], x, 192, 25, 0x202421, .medium)
                text(subtitles[index], x, 234, 11, 0x878B83, .medium)
                color(0x1B211F).setFill()
                let tile = NSBezierPath(roundedRect: NSRect(x: x + 50, y: 302, width: 280, height: 280), xRadius: 66, yRadius: 66)
                tile.fill()
                mark(index, NSRect(x: x + 107, y: 374, width: 166, height: 138), color(colors[index]))
                text(descriptions[index], x, 621, 17, 0x5E655E)
                mark(index, NSRect(x: x + 156, y: 695, width: 68, height: 57), color(0x232923))

                color(0xE5E6DF).setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: 806, width: 380, height: 52), xRadius: 13, yRadius: 13).fill()
                text("浅色", x + 18, 824, 11, 0x777D74)
                mark(index, NSRect(x: x + 157, y: 823, width: 22, height: 18), color(0x252A25))
                text("72%", x + 187, 823, 14, 0x252A25, .medium)

                color(0x252A25).setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: 871, width: 380, height: 52), xRadius: 13, yRadius: 13).fill()
                text("深色", x + 18, 889, 11, 0xAEB6AC)
                mark(index, NSRect(x: x + 157, y: 888, width: 22, height: 18), .white)
                text("72%", x + 187, 888, 14, 0xFFFFFF, .medium)
            }
            color(0xD9DCD3).setFill()
            NSRect(x: 80, y: 982, width: 1400, height: 1).fill()
            text("下方均为 22 × 18 pt 菜单栏原尺寸效果。", 80, 1012, 14, 0x757A73)
        }
        print(output.appendingPathComponent("directions.png").path)
    }
}

import AppKit

/// swiftc Sources/Swapling/BrandIcon.swift scripts/generate-brand-assets.swift -o /tmp/swapling-brand
/// /tmp/swapling-brand
/// iconutil -c icns Resources/Brand/AppIcon.iconset -o Resources/Brand/AppIcon.icns
@main
enum GenerateBrandAssets {
    static let directory = URL(fileURLWithPath: "Resources/Brand", isDirectory: true)

    static func render(width: Int, height: Int, to url: URL, draw: () -> Void) throws {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.current?.imageInterpolation = .high
        draw()
        NSGraphicsContext.restoreGraphicsState()
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
    }

    static func color(_ value: Int) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                green: CGFloat((value >> 8) & 255) / 255,
                blue: CGFloat(value & 255) / 255, alpha: 1)
    }

    static func text(_ string: String, x: CGFloat, y: CGFloat, size: CGFloat,
                     color: NSColor, weight: NSFont.Weight = .regular) {
        (string as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color,
        ])
    }

    static func main() throws {
        let manager = FileManager.default
        let iconset = directory.appendingPathComponent("AppIcon.iconset", isDirectory: true)
        try manager.createDirectory(at: iconset, withIntermediateDirectories: true)
        guard let artwork = NSImage(contentsOf: directory.appendingPathComponent("AppIcon-master.png")) else {
            throw NSError(domain: "BrandAssets", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Missing approved AppIcon-master.png"])
        }
        func drawArtwork(_ rect: NSRect) {
            artwork.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1,
                         respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        }
        for size in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = size * scale
                let filename = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
                try render(width: pixels, height: pixels, to: iconset.appendingPathComponent(filename)) {
                    drawArtwork(NSRect(x: 0, y: 0, width: pixels, height: pixels))
                }
            }
        }
        try render(width: 1024, height: 1024, to: directory.appendingPathComponent("AppIcon.png")) {
            drawArtwork(NSRect(x: 0, y: 0, width: 1024, height: 1024))
        }
        for scale in [1, 2, 3] {
            try render(width: 22 * scale, height: 18 * scale,
                       to: directory.appendingPathComponent("MenuBar\(scale == 1 ? "" : "@\(scale)x").png")) {
                BrandIcon.drawMark(in: NSRect(x: 0, y: 0, width: 22 * scale, height: 18 * scale), color: .black)
            }
        }
        try render(width: 1200, height: 800, to: directory.appendingPathComponent("preview.png")) {
            color(0xEEEDE9).setFill()
            NSRect(x: 0, y: 0, width: 1200, height: 800).fill()
            text("Swapling", x: 64, y: 46, size: 27, color: color(0x252728), weight: .semibold)
            text("岛灵 / Island Spirit", x: 64, y: 88, size: 16, color: color(0x777A7A))
            drawArtwork(NSRect(x: 66, y: 160, width: 420, height: 420))
            BrandIcon.drawMark(in: NSRect(x: 670, y: 225, width: 290, height: 242), color: color(0x252728))
            text("单色轮廓 · 透明眼睛", x: 726, y: 495, size: 16, color: color(0x777A7A))
            color(0xD4D6D3).setFill()
            NSRect(x: 64, y: 606, width: 1072, height: 1).fill()
            let modes: [(String, Int, Int)] = [
                ("浅色", 0xF8F8F6, 0x252728), ("深色", 0x252728, 0xFFFFFF),
                ("选中", 0x2863CF, 0xFFFFFF),
            ]
            for (index, mode) in modes.enumerated() {
                let x = CGFloat(64 + index * 368)
                color(mode.1).setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: 644, width: 336, height: 54), xRadius: 14, yRadius: 14).fill()
                text(mode.0, x: x + 20, y: 664, size: 12, color: color(mode.2).withAlphaComponent(0.65))
                BrandIcon.drawMark(in: NSRect(x: x + 143, y: 662, width: 22, height: 18), color: color(mode.2))
                text("72%", x: x + 174, y: 662, size: 14, color: color(mode.2), weight: .medium)
            }
            text("菜单栏原尺寸 22 × 18 pt · 矢量绘制，适配 Retina", x: 64, y: 743, size: 14, color: color(0x777A7A))
        }
        print("Generated Island Spirit app icon, menu-bar assets, and preview")
    }
}

import AppKit

/// Delivery normalization for generated sprites: `size` px (default 96, the panel's 96pt slot at
/// two screen pixels per sprite pixel), shared <=31-color palette, binary alpha.
/// Each sprite pixel is the average of its whole source area (not one nearest sample, which
/// picks up the generator's edge noise); stray single pixels are cleaned up after quantizing.
/// swiftc -parse-as-library scripts/export-pixel-avatars.swift -o /tmp/export-pixel-avatars
/// /tmp/export-pixel-avatars <source-directory> <output-directory> [size]
@main
enum ExportPixelAvatars {
    struct RGB: Hashable {
        let r: Int
        let g: Int
        let b: Int
        func distance(_ other: RGB) -> Int {
            let dr = r - other.r, dg = g - other.g, db = b - other.b
            return dr * dr + dg * dg + db * db
        }
    }
    static let names = ["normal", "worried", "exhausted"]

    static func bitmap(_ width: Int, _ height: Int) -> NSBitmapImageRep {
        NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    }

    static func withDrawing(_ output: NSBitmapImageRep, _ draw: () -> Void) {
        let context = NSGraphicsContext(bitmapImageRep: output)!.cgContext
        context.clear(CGRect(x: 0, y: 0, width: output.pixelsWide, height: output.pixelsHigh))
        context.translateBy(x: 0, y: CGFloat(output.pixelsHigh))
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.current?.imageInterpolation = .none
        draw()
        NSGraphicsContext.restoreGraphicsState()
    }

    static func draw(_ image: NSImage, in rect: NSRect) {
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1,
                   respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none])
    }

    /// Alpha-weighted average of each source cell; transparent when under half covered.
    static func areaAverage(_ image: NSImage, size: Int) -> [RGB?] {
        let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let (w, h) = (cg.width, cg.height)
        let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        let data = context.data!.assumingMemoryBound(to: UInt8.self)
        var pixels: [RGB?] = []
        for cy in 0..<size {
            for cx in 0..<size {
                let (x0, x1) = (cx * w / size, (cx + 1) * w / size)
                let (y0, y1) = (cy * h / size, (cy + 1) * h / size)
                var (r, g, b, a, n) = (0, 0, 0, 0, 0)
                for y in y0..<y1 {
                    for x in x0..<x1 {
                        let o = y * w * 4 + x * 4
                        r += Int(data[o]); g += Int(data[o + 1]); b += Int(data[o + 2]); a += Int(data[o + 3]); n += 1
                    }
                }
                // Premultiplied sums divided by alpha give the un-premultiplied mean colour.
                pixels.append(a < n * 128 || a == 0 ? nil : RGB(r: r * 255 / a, g: g * 255 / a, b: b * 255 / a))
            }
        }
        return pixels
    }

    /// A pixel unlike all of its neighbours takes the colour most of them share; a lone opaque
    /// speck with at most one opaque neighbour is dropped.
    static func despeckle(_ pixels: [Int?], size: Int) -> [Int?] {
        var result = pixels
        for y in 0..<size {
            for x in 0..<size {
                guard let own = pixels[y * size + x] else { continue }
                var neighbours: [Int?] = []
                for dy in -1...1 {
                    for dx in -1...1 where dx != 0 || dy != 0 {
                        let (nx, ny) = (x + dx, y + dy)
                        neighbours.append(nx >= 0 && ny >= 0 && nx < size && ny < size ? pixels[ny * size + nx] : nil)
                    }
                }
                let opaque = neighbours.compactMap { $0 }
                if opaque.count <= 1 { result[y * size + x] = nil; continue }
                guard !opaque.contains(own) else { continue }
                let counts = Dictionary(opaque.map { ($0, 1) }, uniquingKeysWith: +)
                if let (major, count) = counts.max(by: { $0.value < $1.value }), count >= 4 {
                    result[y * size + x] = major
                }
            }
        }
        return result
    }

    static func sharedPalette(_ samples: [RGB]) -> [RGB] {
        // Farthest-point seeds retain rare, saturated eye/sweat colors, then weighted k-means.
        let histogram = Dictionary(samples.map { ($0, 1) }, uniquingKeysWith: +)
        let colors = histogram.keys.sorted {
            ($0.r, $0.g, $0.b) < ($1.r, $1.g, $1.b)
        }
        var centers = [colors[0]]
        while centers.count < min(31, colors.count) {
            let next = colors.max { a, b in
                centers.map { a.distance($0) }.min()! < centers.map { b.distance($0) }.min()!
            }!
            centers.append(next)
        }
        for _ in 0..<12 {
            var totals = Array(repeating: (r: 0, g: 0, b: 0, count: 0), count: centers.count)
            for value in colors {
                let best = centers.indices.min { value.distance(centers[$0]) < value.distance(centers[$1]) }!
                let count = histogram[value]!
                totals[best].r += value.r * count
                totals[best].g += value.g * count
                totals[best].b += value.b * count
                totals[best].count += count
            }
            centers = totals.enumerated().map { index, total in
                guard total.count > 0 else { return centers[index] }
                return RGB(r: total.r / total.count, g: total.g / total.count, b: total.b / total.count)
            }
        }
        return centers
    }

    static func main() throws {
        guard (3...4).contains(CommandLine.arguments.count) else {
            fatalError("Expected source-directory, output-directory and optional size")
        }
        let size = CommandLine.arguments.count == 4 ? Int(CommandLine.arguments[3])! : 96
        let source = URL(fileURLWithPath: CommandLine.arguments[1])
        let destination = URL(fileURLWithPath: CommandLine.arguments[2])
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        var sprites: [[RGB?]] = []
        for name in names {
            guard let image = NSImage(contentsOf: source.appendingPathComponent("\(name).png")) else {
                fatalError("Missing source sprite: \(name)")
            }
            sprites.append(areaAverage(image, size: size))
        }
        let palette = sharedPalette(sprites.flatMap { $0.compactMap { $0 } })
        var outputs: [NSImage] = []
        var report: [[String: Any]] = []
        for (index, name) in names.enumerated() {
            let output = bitmap(size, size)
            var used = Set<RGB>()
            let indices = despeckle(sprites[index].map { input in
                input.map { input in palette.indices.min { input.distance(palette[$0]) < input.distance(palette[$1]) }! }
            }, size: size)
            for y in 0..<size {
                for x in 0..<size {
                    guard let paletteIndex = indices[y * size + x] else {
                        output.setColor(NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 0), atX: x, y: y)
                        continue
                    }
                    let color = palette[paletteIndex]
                    used.insert(color)
                    output.setColor(NSColor(deviceRed: CGFloat(color.r) / 255,
                                            green: CGFloat(color.g) / 255,
                                            blue: CGFloat(color.b) / 255, alpha: 1), atX: x, y: y)
                }
            }
            let png = output.representation(using: .png, properties: [:])!
            try png.write(to: destination.appendingPathComponent("\(name).png"))
            let image = NSImage(data: png)!
            outputs.append(image)
            let preview = bitmap(512, 512)
            withDrawing(preview) { draw(image, in: NSRect(x: 0, y: 0, width: 512, height: 512)) }
            try preview.representation(using: .png, properties: [:])!
                .write(to: destination.appendingPathComponent("\(name)@8x.png"))
            report.append(["state": name, "width": size, "height": size,
                           "opaqueColors": used.count, "alphaValues": [0, 255]])
            print("\(name): \(size)x\(size), \(used.count) opaque colors, alpha 0/255")
        }
        let paletteText = palette.map { String(format: "#%02X%02X%02X", $0.r, $0.g, $0.b) }.joined(separator: "\n")
        try paletteText.write(to: destination.appendingPathComponent("palette.txt"), atomically: true, encoding: .utf8)
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: destination.appendingPathComponent("validation.json"))

        let sheet = bitmap(936, 424)
        withDrawing(sheet) {
            NSColor(deviceRed: 0.09, green: 0.09, blue: 0.11, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: 936, height: 424).fill()
            for (index, title) in ["正常微笑", "紧张冒汗", "用完 · 打瞌睡"].enumerated() {
                let x = CGFloat(28 + index * 312)
                draw(outputs[index], in: NSRect(x: x, y: 16, width: 256, height: 256))
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 16, weight: .medium), .foregroundColor: NSColor.white,
                ]
                let textWidth = (title as NSString).size(withAttributes: attributes).width
                (title as NSString).draw(at: NSPoint(x: x + (256 - textWidth) / 2, y: 286), withAttributes: attributes)
                // Actual panel size: 96pt.
                draw(outputs[index], in: NSRect(x: x + 80, y: 316, width: 96, height: 96))
            }
        }
        try sheet.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent("preview.png"))
    }
}

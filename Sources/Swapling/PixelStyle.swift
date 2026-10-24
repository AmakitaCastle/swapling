import AppKit
import CoreText
import IslandCore
import SwiftUI

/// The cozy pixel-game look of the panel.
enum Pixel {
    static let background = Color(hex: 0x15100D)
    static let card = Color(hex: 0x231914)
    static let frame = Color(hex: 0xE9D8BD)
    static let frameDim = Color(hex: 0x6B5644)
    static let text = Color(hex: 0xF3E6CF)
    static let muted = Color(hex: 0xA8937A)
    static let ok = Color(hex: 0x7BD36B)
    static let warn = Color(hex: 0xF2D14B)
    static let bad = Color(hex: 0xE8574A)
    static let emptyCell = Color(hex: 0x3A2C23)
    /// Raised button face.
    static let button = Color(hex: 0x3A2A1F)

    /// Width of one stepped frame line.
    static let line: CGFloat = 3
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// Fusion Pixel Font (12px grid, OFL-1.1), bundled in Contents/Resources/Fonts. Sizes stay on
/// multiples of the 12px grid so every glyph pixel lands on whole screen pixels; without the font
/// (e.g. `swift run`, outside the .app) the system font stands in at the same sizes.
enum PixelFont {
    static let fileName = "FusionPixel-12px-Proportional-zh_hans"
    static let postScriptName = "Fusion-Pixel-12px-Prop-zh-Hans-Regular"

    /// One glyph-grid pixel per point: body text, labels, numbers.
    static let small: CGFloat = 12
    /// Two points per grid pixel: headline numbers.
    static let large: CGFloat = 24

    private(set) static var isAvailable = false

    /// Call once at launch, before any view asks for the font.
    static func register() {
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "otf", subdirectory: "Fonts") else { return }
        var error: Unmanaged<CFError>?
        let registered = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        // Already registered (a second call) still leaves the font usable.
        isAvailable = registered || NSFont(name: postScriptName, size: small) != nil
    }

    static func font(_ size: CGFloat = small) -> Font {
        isAvailable ? .custom(postScriptName, fixedSize: size) : .system(size: size * 0.92, weight: .medium)
    }

    static func nsFont(_ size: CGFloat = small) -> NSFont {
        (isAvailable ? NSFont(name: postScriptName, size: size) : nil) ?? .systemFont(ofSize: size * 0.92, weight: .medium)
    }
}

/// A square frame drawn just outside the view's bounds with the corners left out, so it reads as
/// a stepped pixel border (the mockup's four offset box-shadows).
struct PixelBorder: Shape {
    var width: CGFloat = Pixel.line

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(CGRect(x: rect.minX, y: rect.minY - width, width: rect.width, height: width))
        path.addRect(CGRect(x: rect.minX, y: rect.maxY, width: rect.width, height: width))
        path.addRect(CGRect(x: rect.minX - width, y: rect.minY, width: width, height: rect.height))
        path.addRect(CGRect(x: rect.maxX, y: rect.minY, width: width, height: rect.height))
        return path
    }
}

extension View {
    /// Fills with `fill` and frames with `border` outside the bounds; leaves room for the frame.
    func pixelBox(fill: Color = Pixel.card, border: Color = Pixel.frameDim, width: CGFloat = Pixel.line) -> some View {
        background(fill)
            .overlay(PixelBorder(width: width).fill(border))
            .padding(width)
    }
}

/// Block progress bar: `cells` squares, lit from the left for the shown share.
struct SegmentedBar: View {
    /// 0...100.
    var percent: Double
    var color: Color
    var cells = 20
    var cellHeight: CGFloat = 8
    var gap: CGFloat = 2

    /// Cells lit for `percent`; a sliver of use still lights one, so 1% never looks like 0%.
    static func litCells(percent: Double, cells: Int) -> Int {
        let lit = Int((min(max(percent, 0), 100) / 100 * Double(cells)).rounded())
        return percent > 0 ? max(lit, 1) : 0
    }

    var body: some View {
        let shown = Self.litCells(percent: percent, cells: cells)
        HStack(spacing: gap) {
            ForEach(0..<cells, id: \.self) { index in
                Rectangle()
                    .fill(index < shown ? color : Pixel.emptyCell)
                    .frame(height: cellHeight)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The active agent's sweep over a `SegmentedBar` (4pt cells, 2pt gaps): one brighter cell
/// stepping left to right, then a rest. A Core Animation keyframe animation run by the window
/// server, so the app does no work per step; removed (and stopped) with the view.
struct SweepLayer: NSViewRepresentable {
    let cells: Int
    let filled: Int
    var cellWidth: CGFloat = 4
    var cellHeight: CGFloat = 8
    var gap: CGFloat = 2

    final class Coordinator {
        var drawn: (cells: Int, filled: Int)?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.addSublayer(CALayer())
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let highlight = view.layer?.sublayers?.first else { return }
        // Restart only when the bar itself changed, so redraws elsewhere don't reset the sweep.
        let drawn = (cells: cells, filled: filled)
        if let last = context.coordinator.drawn, last == drawn, highlight.animation(forKey: "sweep") != nil { return }
        context.coordinator.drawn = drawn
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        highlight.backgroundColor = NSColor.white.cgColor
        highlight.anchorPoint = .zero
        highlight.bounds = CGRect(x: 0, y: 0, width: cellWidth, height: cellHeight)
        highlight.position = .zero
        highlight.opacity = 0
        CATransaction.commit()

        let steps = (0..<(cells + CollapsedDisplay.sweepPause)).map { CollapsedDisplay.sweepCell(tick: $0, cells: cells) }
        // Discrete keyframes: n values hold over n + 1 key times.
        let times = (0...steps.count).map { NSNumber(value: Double($0) / Double(steps.count)) }
        let x = CAKeyframeAnimation(keyPath: "position.x")
        x.values = steps.map { CGFloat($0 ?? 0) * (cellWidth + gap) }
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = steps.map { cell in cell.map { $0 < filled ? 0.6 : 0.45 } ?? 0 }
        let group = CAAnimationGroup()
        for animation in [x, opacity] {
            animation.calculationMode = .discrete
            animation.keyTimes = times
        }
        group.animations = [x, opacity]
        group.duration = Double(steps.count) * CollapsedDisplay.sweepStep
        group.repeatCount = .infinity
        highlight.removeAnimation(forKey: "sweep")
        highlight.add(group, forKey: "sweep")
    }
}


/// Solid-colour status tag: 正常 / 紧张 / 用完 / 待确认 / 按余额.
struct PixelTag: View {
    let text: String
    let color: Color
    var textColor = Pixel.background

    var body: some View {
        Text(text)
            .font(PixelFont.font())
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color)
            .foregroundStyle(textColor)
    }
}

/// Square framed button face used for panel actions.
struct PixelButtonLabel: View {
    let title: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 9, weight: .semibold))
            }
            Text(title).font(PixelFont.font())
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .foregroundStyle(Pixel.text)
        .pixelBox(fill: Pixel.button, border: Pixel.frameDim, width: 2)
        .contentShape(Rectangle())
    }
}

/// Character art and pixelated brand icons, prepared once per file and size.
@MainActor
enum PixelSprite {
    private struct Key: Hashable {
        let url: URL
        let modified: Date?
        let pixels: Int
        let crop: Bool
    }

    private static var cache: [Key: NSImage] = [:]
    private static var iconCache: [String: NSImage] = [:]
    static var library = CharacterLibrary.standard

    /// The character image for `providerID` in `mood`, nil when the provider has no art.
    /// Pixel art (folders with a `pixel-art` marker) is reduced to `pixels` × `pixels` and its
    /// alpha snapped to fully on or off, so it can be drawn with nearest-neighbour scaling and
    /// nothing behind it shows through the body. `head` crops to the face for small spots.
    static func character(for providerID: String, mood: CharacterMood, pixels: Int, head: Bool = false) -> NSImage? {
        guard let url = library.imageURL(for: providerID, mood: mood) else { return nil }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let key = Key(url: url, modified: modified, pixels: pixels, crop: head)
        if let image = cache[key] { return image }
        guard let source = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let isPixelArt = FileManager.default.fileExists(
            atPath: url.deletingLastPathComponent().appendingPathComponent("pixel-art").path
        )
        let cropped = head ? source.cropping(to: headRect(in: source)) ?? source : source
        let image = isPixelArt
            ? reduce(cropped, to: pixels).map { NSImage(cgImage: $0, size: NSSize(width: pixels, height: pixels)) }
            : NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
        if let image { cache[key] = image }
        return image
    }

    static func isPixelArt(_ providerID: String, mood: CharacterMood) -> Bool {
        guard let url = library.imageURL(for: providerID, mood: mood) else { return false }
        return FileManager.default.fileExists(atPath: url.deletingLastPathComponent().appendingPathComponent("pixel-art").path)
    }

    /// The brand icon rasterised on a small grid, to be enlarged with nearest-neighbour scaling.
    static func icon(for providerID: String, pixels: Int) -> NSImage? {
        let cacheKey = "\(providerID)@\(pixels)"
        if let image = iconCache[cacheKey] { return image }
        guard let template = ProviderIconCache.image(for: providerID) else { return nil }
        let color = ProviderIconName.brandColor(for: providerID).map { hex in
            NSColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        } ?? NSColor(Pixel.text)
        guard let context = bitmap(pixels) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: pixels, height: pixels)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        template.draw(in: rect)
        color.set()
        rect.fill(using: .sourceIn)
        NSGraphicsContext.restoreGraphicsState()
        guard let snapped = snapAlpha(context).makeImage() else { return nil }
        let image = NSImage(cgImage: snapped, size: NSSize(width: pixels, height: pixels))
        iconCache[cacheKey] = image
        return image
    }

    /// The face and hair of a square bust portrait.
    private static func headRect(in image: CGImage) -> CGRect {
        let side = Double(min(image.width, image.height)) * 0.62
        return CGRect(x: (Double(image.width) - side) / 2, y: Double(image.height) * 0.08, width: side, height: side)
    }

    private static func reduce(_ image: CGImage, to pixels: Int) -> CGImage? {
        guard let context = bitmap(pixels) else { return nil }
        // Preserve native sprite pixels when enlarging; smooth only oversized source art.
        context.interpolationQuality = pixels >= max(image.width, image.height) ? .none : .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        return snapAlpha(context).makeImage()
    }

    private static func bitmap(_ pixels: Int) -> CGContext? {
        CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: pixels * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    /// Alpha below half becomes fully clear, the rest fully opaque (colour un-premultiplied).
    private static func snapAlpha(_ context: CGContext) -> CGContext {
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return context }
        for offset in stride(from: 0, to: context.bytesPerRow * context.height, by: 4) {
            let alpha = Int(data[offset + 3])
            if alpha < 128 {
                data[offset] = 0; data[offset + 1] = 0; data[offset + 2] = 0; data[offset + 3] = 0
            } else if alpha < 255 {
                for channel in 0..<3 {
                    data[offset + channel] = UInt8(min(255, Int(data[offset + channel]) * 255 / alpha))
                }
                data[offset + 3] = 255
            }
        }
        return context
    }
}

/// The panel's character: its art when it has some, else its brand icon enlarged in a framed box.
struct MascotSprite: View {
    let providerID: String
    let mood: CharacterMood
    /// Points; the art is drawn on a grid of this many pixels (two screen pixels each on Retina).
    let size: CGFloat
    var head = false

    var body: some View {
        if let image = PixelSprite.character(for: providerID, mood: mood, pixels: Int(size), head: head) {
            Image(nsImage: image)
                .resizable()
                .interpolation(PixelSprite.isPixelArt(providerID, mood: mood) ? .none : .high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                // Asleep: a touch dimmer, still fully opaque.
                .brightness(mood == .exhausted && !head ? -0.12 : 0)
        } else {
            fallback
        }
    }

    /// No art for this provider: its icon on a 16-pixel grid, scaled up in whole steps.
    @ViewBuilder
    private var fallback: some View {
        let inner = head ? size * 0.8 : size - Pixel.line * 2 - 12
        Group {
            if let icon = PixelSprite.icon(for: providerID, pixels: 16) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: floor(inner / 16) * 16, height: floor(inner / 16) * 16)
            } else {
                Text(String(ProviderCatalog.shortName(for: providerID).prefix(1)))
                    .font(PixelFont.font(head ? PixelFont.small : PixelFont.large))
                    .foregroundStyle(Pixel.text)
            }
        }
        .opacity(mood == .exhausted ? 0.55 : 1)
        .frame(width: head ? size : size - Pixel.line * 2, height: head ? size : size - Pixel.line * 2)
        .modifier(FallbackBox(enabled: !head))
    }

    private struct FallbackBox: ViewModifier {
        let enabled: Bool
        func body(content: Content) -> some View {
            if enabled {
                content.pixelBox(fill: Pixel.card, border: Pixel.frame)
            } else {
                content
            }
        }
    }
}

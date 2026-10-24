import AppKit
import IslandCore
import SwiftUI

/// CodexBar's provider artwork as a template image, tinted with the provider's brand color (or the
/// surrounding foreground style when it has none). Falls back to the text badge when a provider
/// has no icon (or when run outside the .app).
struct ProviderIcon: View {
    let providerID: String
    let size: CGFloat
    var fallback: String = ""

    var body: some View {
        if let image = ProviderIconCache.image(for: providerID) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .foregroundStyle(brandColor.map(AnyShapeStyle.init) ?? AnyShapeStyle(.foreground))
        } else if !fallback.isEmpty {
            Text(fallback)
                .font(.system(size: size * 0.8, weight: .bold, design: .rounded))
        }
    }

    private var brandColor: Color? {
        ProviderIconName.brandColor(for: providerID).map { hex in
            Color(
                red: Double((hex >> 16) & 0xFF) / 255,
                green: Double((hex >> 8) & 0xFF) / 255,
                blue: Double(hex & 0xFF) / 255
            )
        }
    }
}

@MainActor
enum ProviderIconCache {
    private static var cache: [String: NSImage?] = [:]

    static func image(for providerID: String) -> NSImage? {
        let name = ProviderIconName.resourceName(for: providerID)
        if let cached = cache[name] { return cached }
        let image = Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: "ProviderIcons")
            .flatMap { NSImage(contentsOf: $0) }
        image?.isTemplate = true
        cache[name] = image
        return image
    }
}

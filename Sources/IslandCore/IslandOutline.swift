import CoreGraphics

/// Black island outline: flat top that flares into the menu bar with concave "shoulders",
/// and continuous-curvature bottom corners. Shared by the drawn shape and hover hit-testing
/// so the hot zone matches what the user sees.
/// Adapted from CodeIsland's NotchPanelShape (https://github.com/wxtsky/CodeIsland, MIT License,
/// Copyright (c) 2026 wxtsky). See THIRD_PARTY_NOTICES.md.
public enum IslandOutline {
    /// `rect` is the island body; the shoulders extend `topExtension` beyond its left and right edges.
    public static func path(in rect: CGRect, topExtension: CGFloat, bottomRadius: CGFloat) -> CGPath {
        let ext = topExtension
        let br = min(bottomRadius, rect.width / 4, rect.height / 2)
        let k: CGFloat = 0.62

        let p = CGMutablePath()
        p.move(to: CGPoint(x: rect.minX - ext, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX + ext, y: rect.minY))
        p.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + ext),
            control1: CGPoint(x: rect.maxX + ext * 0.35, y: rect.minY),
            control2: CGPoint(x: rect.maxX, y: rect.minY + ext * 0.35)
        )
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        p.addCurve(
            to: CGPoint(x: rect.maxX - br, y: rect.maxY),
            control1: CGPoint(x: rect.maxX, y: rect.maxY - br * (1 - k)),
            control2: CGPoint(x: rect.maxX - br * (1 - k), y: rect.maxY)
        )
        p.addLine(to: CGPoint(x: rect.minX + br, y: rect.maxY))
        p.addCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - br),
            control1: CGPoint(x: rect.minX + br * (1 - k), y: rect.maxY),
            control2: CGPoint(x: rect.minX, y: rect.maxY - br * (1 - k))
        )
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + ext))
        p.addCurve(
            to: CGPoint(x: rect.minX - ext, y: rect.minY),
            control1: CGPoint(x: rect.minX, y: rect.minY + ext * 0.35),
            control2: CGPoint(x: rect.minX - ext * 0.35, y: rect.minY)
        )
        p.closeSubpath()
        return p
    }

    /// Whether `point` lies on the visible island, including the shoulders and excluding the
    /// transparent area cut away by the bottom corners.
    public static func contains(_ point: CGPoint, in rect: CGRect, topExtension: CGFloat, bottomRadius: CGFloat) -> Bool {
        path(in: rect, topExtension: topExtension, bottomRadius: bottomRadius).contains(point)
    }

    /// Hover hit-test in the coordinates of the hover view, which is the island body padded by
    /// `topExtension` on each side so the shoulders can receive the pointer. An unmeasured
    /// (zero) island never counts as hovered.
    public static func hoverContains(
        _ point: CGPoint,
        islandSize: CGSize,
        topExtension: CGFloat,
        bottomRadius: CGFloat
    ) -> Bool {
        guard islandSize.width > 0, islandSize.height > 0 else { return false }
        let body = CGRect(x: topExtension, y: 0, width: islandSize.width, height: islandSize.height)
        return contains(point, in: body, topExtension: topExtension, bottomRadius: bottomRadius)
    }
}

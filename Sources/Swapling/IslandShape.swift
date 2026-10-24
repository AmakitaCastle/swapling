import IslandCore
import SwiftUI

/// Black island outline; the geometry lives in `IslandOutline` so hover hit-testing uses the same path.
struct IslandShape: Shape {
    var topExtension: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topExtension, bottomRadius) }
        set {
            topExtension = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        Path(IslandOutline.path(in: rect, topExtension: topExtension, bottomRadius: bottomRadius))
    }
}

/// Small circular gauge; the arc is the used share of a quota window, or what's left of it.
/// A nil percent draws an empty grey ring: unknown is never shown as 0% or normal.
struct QuotaRing: View {
    var usedPercent: Double?
    var thresholds: QuotaThresholds
    var lineWidth: CGFloat = 2.5
    var showsRemaining = false
    /// Breathe with a soft glow from the second warning line until the window runs out.
    var glows = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let used = usedPercent.map { min(max($0, 0), 100) }
        let fill = used.map { showsRemaining ? 100 - $0 : $0 } ?? 0
        // Spelled out as closures: with -O, `used.map(thresholds.level(forUsed:))` drew a 2% ring red
        // (Swift 6.2.4 release build), though the same call returned .normal.
        let level: QuotaLevel = used.map { thresholds.level(forUsed: $0) } ?? .unknown
        let color = QuotaColor.color(for: level)
        ZStack {
            Circle().stroke(Color.white.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fill / 100)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: fill)
        // With Reduce Motion the glow stays lit instead of breathing.
        .modifier(Breathing(
            active: glows && (used.map { thresholds.glows(used: $0) } ?? false), still: reduceMotion, color: color
        ))
        .accessibilityHidden(true)
    }
}

private struct Breathing: ViewModifier {
    let active: Bool
    var still = false
    let color: Color

    func body(content: Content) -> some View {
        if active, still {
            content.shadow(color: color.opacity(0.7), radius: 3)
        } else if active {
            content.phaseAnimator([false, true]) { view, bright in
                view.shadow(color: color.opacity(bright ? 0.95 : 0.2), radius: bright ? 4 : 1)
            } animation: { _ in
                .easeInOut(duration: 1.1)
            }
        } else {
            content
        }
    }
}

/// Quota colours from the pixel palette, shared by the notch, pop-ups and panel.
enum QuotaColor {
    static func color(for level: QuotaLevel) -> Color {
        switch level {
        case .critical, .exhausted: return Pixel.bad
        case .warning: return Pixel.warn
        case .normal: return Pixel.ok
        case .unknown: return Pixel.muted
        }
    }

    static func color(forUsed used: Double, _ thresholds: QuotaThresholds) -> Color {
        color(for: thresholds.level(forUsed: used))
    }
}

/// Tiny line chart of daily cost.
struct Sparkline: View {
    var values: [Double]

    var body: some View {
        GeometryReader { proxy in
            let maxValue = max(values.max() ?? 0, 0.0001)
            let step = values.count > 1 ? proxy.size.width / CGFloat(values.count - 1) : 0
            let points = values.enumerated().map { index, value in
                CGPoint(
                    x: CGFloat(index) * step,
                    y: proxy.size.height * (1 - CGFloat(value / maxValue))
                )
            }
            ZStack {
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for point in points.dropFirst() { path.addLine(to: point) }
                }
                .stroke(Color.white.opacity(0.75), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                if let last = points.last {
                    Circle().fill(Color.white).frame(width: 4, height: 4).position(last)
                }
            }
        }
    }
}

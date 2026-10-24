import CoreGraphics
import Foundation

/// How long the pointer must rest on the island before the panel opens.
public enum HoverDelay: String, CaseIterable, Sendable {
    case short
    case medium
    case long

    public var seconds: TimeInterval {
        switch self {
        case .short: return 0.2
        case .medium: return 0.4
        case .long: return 0.7
        }
    }

    public var label: String {
        switch self {
        case .short: return "短（0.2 秒）"
        case .medium: return "中（0.4 秒）"
        case .long: return "长（0.7 秒）"
        }
    }
}

/// Tells a deliberate hover from the pointer sweeping across the island: the panel opens only
/// after the pointer has stayed inside, within a small radius, for the whole delay. Moving
/// further than the radius restarts the wait, so a pass on the way to the menu bar never opens it.
public struct HoverIntent: Sendable {
    public var delay: TimeInterval
    /// Movement within this distance (points) still counts as resting.
    public var restRadius: CGFloat

    private var anchor: CGPoint?
    private var since: Date?

    public init(delay: TimeInterval, restRadius: CGFloat = 12) {
        self.delay = delay
        self.restRadius = restRadius
    }

    /// Feeds a pointer position inside the island, or nil once it left. Returns when the panel
    /// should open if the pointer stays put from here on, or nil when outside.
    @discardableResult
    public mutating func update(point: CGPoint?, at time: Date) -> Date? {
        guard let point else {
            anchor = nil
            since = nil
            return nil
        }
        if let anchor, let since, hypot(point.x - anchor.x, point.y - anchor.y) <= restRadius {
            return since.addingTimeInterval(delay)
        }
        anchor = point
        since = time
        return time.addingTimeInterval(delay)
    }

    /// True once the pointer has rested long enough.
    public func isReady(at time: Date) -> Bool {
        guard let since else { return false }
        // A millisecond of slack: Date arithmetic can land a hair short of the exact delay.
        return time.timeIntervalSince(since) >= delay - 0.001
    }
}

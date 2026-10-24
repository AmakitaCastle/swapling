import Foundation

/// How close a quota window is to its limit, in words as well as colour.
public enum QuotaLevel: Equatable, Sendable {
    case normal
    /// At or past the first warning line.
    case warning
    /// At or past the second warning line, not yet used up.
    case critical
    case exhausted
    /// No trustworthy number: an error, no window, or nothing reported yet.
    case unknown

    public var label: String {
        switch self {
        case .normal: return "正常"
        case .warning: return "紧张"
        case .critical: return "接近上限"
        case .exhausted: return "已用完"
        case .unknown: return "未知"
        }
    }
}

/// The one pair of warning lines behind ring colours, the glow and pop-up alerts.
public struct QuotaThresholds: Equatable, Sendable {
    public static let range = 50...99
    public static let standard = QuotaThresholds(warn1: 80, warn2: 95)

    public let warn1: Int
    public let warn2: Int

    /// Always yields `warn1 < warn2` inside `range`, whatever was stored.
    public init(warn1: Int, warn2: Int) {
        let low = Self.range.lowerBound, high = Self.range.upperBound
        var first = min(max(warn1, low), high - 1)
        let second = min(max(warn2, low + 1), high)
        // Keep the second line where the user put it and pull the first under it.
        if first >= second { first = second - 1 }
        self.warn1 = first
        self.warn2 = second
    }

    public static func isValid(warn1: Int, warn2: Int) -> Bool {
        range.contains(warn1) && range.contains(warn2) && warn1 < warn2
    }

    /// Levels the alert engine fires at.
    public var alertLevels: [Int] { [warn1, warn2] }

    public func level(forUsed used: Double) -> QuotaLevel {
        if used >= 100 { return .exhausted }
        if used >= Double(warn2) { return .critical }
        if used >= Double(warn1) { return .warning }
        return .normal
    }

    public func level(for window: QuotaWindow?) -> QuotaLevel {
        guard let window else { return .unknown }
        return level(forUsed: window.usedPercent)
    }

    /// The ring breathes from the second line until the window runs out.
    public func glows(used: Double) -> Bool {
        used >= Double(warn2) && used < 100
    }
}

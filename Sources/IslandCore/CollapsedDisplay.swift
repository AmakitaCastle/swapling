import Foundation

public extension QuotaWindow {
    /// Tiny tag beside the collapsed percent so "44%" says which quota it is: "5h", "周", "月"…
    /// Nil when nothing short and meaningful can be derived.
    var shortLabel: String? {
        if let minutes = windowMinutes {
            switch minutes {
            case 1440: return "日"
            case 10080: return "周"
            case let m where m >= 40000: return "月"
            case let m where m >= 60 && m % 60 == 0: return "\(m / 60)h"
            case let m where m > 0: return "\(m)m"
            default: break
            }
        }
        let title = title.lowercased()
        if title.contains("week") || title.contains("周") { return "周" }
        if title.contains("month") || title.contains("月") { return "月" }
        if title.contains("daily") || title.contains("day") || title.contains("日") { return "日" }
        if title.contains("5 小时") || title.contains("5h") || title.contains("5-hour") { return "5h" }
        if title.contains("session") || title.contains("会话") { return "会话" }
        return nil
    }
}

/// What the collapsed island shows and when it counts as out of date.
public enum CollapsedDisplay {
    /// Seconds between rotations when more providers are pinned than fit beside the notch.
    public static let rotationPeriod: TimeInterval = 6

    /// Percent shown beside the notch, in the menu bar and in the panel: used share, or what's
    /// left when the user prefers that. One setting for every surface.
    public static func shownPercent(for window: QuotaWindow, showRemaining: Bool) -> Double {
        showRemaining ? window.remainingPercent : window.clampedUsed
    }

    /// "已用" or "剩余": names what the shown percent means.
    public static func modeLabel(showRemaining: Bool) -> String {
        showRemaining ? "剩余" : "已用"
    }

    /// Both readings in one line for tooltips and VoiceOver: "已用 30%，剩余 70%".
    public static func bothPercents(for window: QuotaWindow) -> String {
        "已用 \(IslandFormat.percent(window.clampedUsed))，剩余 \(IslandFormat.percent(window.remainingPercent))"
    }

    /// Providers to draw beside the notch when only `limit` fit. Providers at or above
    /// `urgentPercent` always get a slot (most used first); the remaining slots rotate through the
    /// others by `page`. The result keeps the pinned order so items don't jump sides.
    public static func visibleProviders(
        _ pinned: [ProviderUsage],
        limit: Int,
        urgentPercent: Double,
        page: Int
    ) -> [ProviderUsage] {
        guard limit > 0, pinned.count > limit else { return pinned }
        let used: (ProviderUsage) -> Double = { $0.error == nil ? ($0.tightestWindow?.usedPercent ?? 0) : 0 }
        let urgent = pinned.filter { used($0) >= urgentPercent }.sorted { used($0) > used($1) }
        var chosen = Array(urgent.prefix(limit))
        let others = pinned.filter { provider in !chosen.contains { $0.id == provider.id } }
        let slots = limit - chosen.count
        if slots > 0, !others.isEmpty {
            let start = (max(page, 0) * slots) % others.count
            for offset in 0..<min(slots, others.count) {
                chosen.append(others[(start + offset) % others.count])
            }
        }
        let order = Dictionary(uniqueKeysWithValues: pinned.enumerated().map { ($1.id, $0) })
        return chosen.sorted { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }
    }
}

/// The AI in use right now (`ActiveAgent`) beside the notch: which item it is, keeping it on
/// show, and the cell a slow highlight sweeps across its bar.
public extension CollapsedDisplay {
    /// Seconds per sweep step: one cell at a time, stepped, not tweened.
    static let sweepStep: TimeInterval = 0.14
    /// Steps the highlight rests off the bar before starting over.
    static let sweepPause = 4

    /// "claude" matches "claude" and account rows such as "claude:work"; the first in order wins.
    static func activeID(in providers: [ProviderUsage], activeProviderID: String?) -> String? {
        guard let activeProviderID else { return nil }
        return providers.first { $0.id == activeProviderID || $0.baseID == activeProviderID }?.id
    }

    /// `visible` with the active provider kept on show. Already shown: unchanged. Otherwise it is
    /// taken from `candidates` (pinned first, then every provider in the panel) and added when a
    /// slot is free, or put in place of the last item under `urgentPercent`; items at or past the
    /// warning line are never displaced. Keeps the order of `candidates`.
    static func withActive(
        _ visible: [ProviderUsage],
        candidates: [ProviderUsage],
        activeProviderID: String?,
        limit: Int,
        urgentPercent: Double
    ) -> [ProviderUsage] {
        guard activeID(in: visible, activeProviderID: activeProviderID) == nil,
              let id = activeID(in: candidates, activeProviderID: activeProviderID),
              let active = candidates.first(where: { $0.id == id }) else { return visible }
        var result = visible
        if result.count < max(limit, 1) {
            result.append(active)
        } else {
            let used: (ProviderUsage) -> Double = { $0.error == nil ? ($0.tightestWindow?.usedPercent ?? 0) : 0 }
            guard let index = result.lastIndex(where: { used($0) < urgentPercent }) else { return visible }
            result[index] = active
        }
        let order = Dictionary(candidates.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        return result.sorted { (order[$0.id] ?? .max) < (order[$1.id] ?? .max) }
    }

    /// The cell lit by the sweep at `tick` (one tick per `sweepStep`), nil while it rests.
    static func sweepCell(tick: Int, cells: Int, pause: Int = sweepPause) -> Int? {
        guard cells > 0 else { return nil }
        let position = ((tick % (cells + pause)) + cells + pause) % (cells + pause)
        return position < cells ? position : nil
    }
}

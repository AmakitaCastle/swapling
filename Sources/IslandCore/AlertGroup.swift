import Foundation

/// One pop-up: every event a provider raised in the same refresh, so Claude's 5-hour and weekly
/// windows crossing 80% together show once instead of twice in a row.
public struct AlertGroup: Equatable, Sendable, Identifiable {
    public let providerID: String
    public private(set) var events: [IslandEvent]

    public var id: String { providerID }

    public init(providerID: String, events: [IslandEvent]) {
        self.providerID = providerID
        self.events = events
    }

    /// The event that sets the ring and icon.
    public var primary: IslandEvent {
        events.max { $0.severity < $1.severity } ?? events[0]
    }

    /// Folds newer events in; a window's newer event replaces its older one.
    public mutating func merge(_ newer: AlertGroup) {
        for event in newer.events {
            events.removeAll { $0.window.id == event.window.id }
            events.append(event)
        }
    }

    /// Groups events by provider, in the order providers first appear.
    public static func group(_ events: [IslandEvent]) -> [AlertGroup] {
        var groups: [AlertGroup] = []
        for event in events {
            if let index = groups.firstIndex(where: { $0.providerID == event.providerID }) {
                groups[index].events.append(event)
            } else {
                groups.append(AlertGroup(providerID: event.providerID, events: [event]))
            }
        }
        return groups
    }

    /// Adds events to a waiting queue, merging into a provider's pop-up that hasn't shown yet.
    public static func enqueue(_ events: [IslandEvent], into queue: inout [AlertGroup]) {
        for group in group(events) {
            if let index = queue.firstIndex(where: { $0.providerID == group.providerID }) {
                queue[index].merge(group)
            } else {
                queue.append(group)
            }
        }
    }

    /// One line per pop-up with several windows, e.g. "5h 已用 87% · 周 已用 82%".
    public var summary: String {
        events.map { event in
            let name = event.window.shortLabel ?? event.window.title
            switch event {
            case .threshold: return "\(name) 已用 \(IslandFormat.percent(event.window.clampedUsed))"
            case .exhausted: return "\(name) 已用完"
            case .reset: return "\(name) 已重置"
            }
        }
        .joined(separator: " · ")
    }
}

// MARK: - Text

public extension AlertGroup {
    /// "Claude · 5 小时", or "Claude · 2 项额度" when several windows fired together.
    var title: String {
        let name = ProviderCatalog.displayName(for: providerID)
        return events.count == 1 ? "\(name) · \(primary.window.title)" : "\(name) · \(events.count) 项额度"
    }

    /// Detail line with the real usage (not the threshold it crossed) and the reset countdown.
    func subtitle(now: Date) -> String {
        let window = primary.window
        let countdown = window.resetsAt.map { " · \(IslandFormat.countdown(to: $0, now: now)) 后重置" } ?? ""
        guard events.count == 1 else {
            if case .exhausted = primary { return summary + countdown }
            return summary
        }
        switch primary {
        case .threshold:
            return "已用 \(IslandFormat.percent(window.clampedUsed))，剩余 \(IslandFormat.percent(window.remainingPercent))\(countdown)"
        case .exhausted:
            return "额度已用完\(countdown)"
        case .reset:
            return "额度已重置，可以继续用了"
        }
    }
}

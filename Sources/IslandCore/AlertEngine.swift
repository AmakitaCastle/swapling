import Foundation

public enum IslandEvent: Equatable, Sendable {
    /// Usage crossed one of the warning thresholds (e.g. 80 or 95).
    case threshold(providerID: String, window: QuotaWindow, level: Int)
    /// Usage hit 100%.
    case exhausted(providerID: String, window: QuotaWindow)
    /// A previously exhausted window has quota again.
    case reset(providerID: String, window: QuotaWindow)

    public var providerID: String {
        switch self {
        case let .threshold(id, _, _), let .exhausted(id, _), let .reset(id, _): return id
        }
    }

    public var window: QuotaWindow {
        switch self {
        case let .threshold(_, window, _), let .exhausted(_, window), let .reset(_, window): return window
        }
    }

    /// Ranks events of one pop-up: running out beats a warning, a warning beats a reset.
    var severity: Int {
        switch self {
        case .exhausted: return 300
        case let .threshold(_, _, level): return 100 + level
        case .reset: return 0
        }
    }
}

/// Turns successive usage snapshots into one-shot pop-up events.
/// Each level fires once per quota period; a new period (reset) re-arms it.
public struct AlertEngine: Sendable {
    public var thresholds: [Int]

    private struct LaneState: Sendable {
        var firedLevel: Int
        var wasExhausted: Bool
    }

    private var lanes: [String: LaneState] = [:]

    public init(thresholds: [Int] = [80, 95]) {
        self.thresholds = thresholds.sorted()
    }

    public mutating func process(_ providers: [ProviderUsage]) -> [IslandEvent] {
        var events: [IslandEvent] = []
        for provider in providers where provider.error == nil {
            for window in provider.windows {
                let key = "\(provider.id)|\(window.id)"
                var state = lanes[key] ?? LaneState(firedLevel: 0, wasExhausted: false)
                let used = window.usedPercent

                if state.wasExhausted && !window.isExhausted {
                    events.append(.reset(providerID: provider.id, window: window))
                    state = LaneState(firedLevel: 0, wasExhausted: false)
                } else if used < Double(thresholds.first ?? 100) {
                    // Dropped back below every threshold: new period, re-arm.
                    state.firedLevel = 0
                }

                if window.isExhausted {
                    if !state.wasExhausted {
                        events.append(.exhausted(providerID: provider.id, window: window))
                        state.wasExhausted = true
                        state.firedLevel = 100
                    }
                } else if let level = thresholds.last(where: { used >= Double($0) }), level > state.firedLevel {
                    events.append(.threshold(providerID: provider.id, window: window, level: level))
                    state.firedLevel = level
                }
                lanes[key] = state
            }
        }
        return events
    }
}

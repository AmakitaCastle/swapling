import Foundation

/// How old one provider's numbers are, judged per provider rather than by the last refresh.
public struct DataFreshness: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// The data source reported when it produced the numbers ("更新于").
        case source
        /// Only the time Swapling read them is known ("采集于").
        case collected
    }

    public let kind: Kind
    public let date: Date
    public let isStale: Bool
    /// The last read failed; these numbers are from an earlier one.
    public let isCarriedOver: Bool

    /// "更新于 3 分钟前" or "采集于 3 分钟前".
    public func label(now: Date) -> String {
        let verb = kind == .source ? "更新于" : "采集于"
        return "\(verb) \(PanelDisplay.ago(date, now: now))"
    }

    /// Why the numbers shouldn't be trusted as current, or nil when they can be.
    public var warning: String? {
        if isCarriedOver { return "本次读取失败，显示的是上次的数据" }
        if isStale { return "数据已过期" }
        return nil
    }
}

public enum Freshness {
    /// Numbers count as stale once they are older than two refresh intervals plus slack.
    public static func staleAfter(refreshInterval: TimeInterval) -> TimeInterval {
        max(refreshInterval, 30) * 2 + 30
    }

    /// Nil when the row has no numbers to judge (an error with nothing kept, or nothing yet).
    public static func of(_ provider: ProviderUsage, refreshInterval: TimeInterval, now: Date) -> DataFreshness? {
        guard provider.hasData else { return nil }
        let kind: DataFreshness.Kind
        let date: Date
        if let updated = provider.updatedAt {
            // A clock a little ahead on either side must not make data look newer than now.
            (kind, date) = (.source, min(updated, now))
        } else if let fetched = provider.fetchedAt {
            (kind, date) = (.collected, min(fetched, now))
        } else {
            return DataFreshness(kind: .collected, date: now, isStale: true, isCarriedOver: provider.isCarriedOver)
        }
        let old = now.timeIntervalSince(date) > staleAfter(refreshInterval: refreshInterval)
        return DataFreshness(
            kind: kind, date: date, isStale: old || provider.isCarriedOver, isCarriedOver: provider.isCarriedOver
        )
    }

    /// True when the row's numbers can be shown as current and fed to alerts.
    public static func isCurrent(_ provider: ProviderUsage, refreshInterval: TimeInterval, now: Date) -> Bool {
        guard provider.error == nil, let freshness = of(provider, refreshInterval: refreshInterval, now: now) else {
            return false
        }
        return !freshness.isStale
    }

    /// Rows to keep after a refresh failed as a whole. With no provider turned on there is nothing
    /// to show, so earlier rows go: a provider the user just switched off must not stay on screen
    /// as current. Any other failure keeps the numbers, marked as carried over so they read as old.
    public static func afterFailedRefresh(_ previous: [ProviderUsage], issue: DataIssue) -> [ProviderUsage] {
        guard issue != .notConfigured else { return [] }
        return previous.map { row in
            var row = row
            if row.hasData { row.isCarriedOver = true }
            return row
        }
    }

    /// Folds a new read into the previous rows. Rows that came back with numbers are stamped
    /// `fetchedAt = now`; rows that failed keep their earlier numbers, marked as carried over,
    /// so a failure never wipes them silently nor makes them look freshly read.
    /// Providers missing from `fetched` (turned off) are dropped.
    public static func merge(previous: [ProviderUsage], fetched: [ProviderUsage], now: Date) -> [ProviderUsage] {
        fetched.map { row in
            var row = row
            if row.error == nil, row.hasData {
                row.fetchedAt = now
                row.isCarriedOver = false
                return row
            }
            guard let old = previous.first(where: { $0.id == row.id }), old.hasData else { return row }
            var kept = old
            kept.error = row.error ?? kept.error
            kept.errorDetail = row.errorDetail
            kept.source = row.source ?? kept.source
            kept.isCarriedOver = true
            return kept
        }
    }
}

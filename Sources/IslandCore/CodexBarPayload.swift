import Foundation

// Decodes the JSON printed by the CodexBar CLI (https://github.com/steipete/CodexBar, MIT).
//   codexbar usage --format json   -> [UsagePayload]
//   codexbar cost  --format json   -> [CostPayload]
// Every field is optional and each provider decodes on its own, so a schema change in one
// provider never blanks the whole island.

enum CodexBarJSON {
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = parseDate(raw) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Bad date: \(raw)")
        }
        return decoder
    }

    static func parseDate(_ raw: String) -> Date? {
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: raw) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: raw)
    }

    /// Decodes a top-level array element by element, dropping elements that fail.
    /// Also accepts a single object for robustness.
    static func decodeList<T: Decodable>(_ type: T.Type, from data: Data) -> [T] {
        let decoder = decoder()
        if let items = try? decoder.decode([Lossy<T>].self, from: data) {
            return items.compactMap(\.value)
        }
        if let single = try? decoder.decode(T.self, from: data) {
            return [single]
        }
        return []
    }
}

private struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

struct CBError: Decodable {
    let message: String?
}

struct CBWindow: Decodable {
    let usedPercent: Double
    let windowMinutes: Int?
    let resetsAt: Date?
    let resetDescription: String?
    let isSyntheticPlaceholder: Bool?
}

struct CBNamedWindow: Decodable {
    let id: String
    let title: String
    let window: CBWindow
    let usageKnown: Bool?
}

struct CBProviderCost: Decodable {
    let used: Double?
    let limit: Double?
    let currencyCode: String?
    let balance: Double?
}

struct CBIdentity: Decodable {
    let loginMethod: String?
}

struct CBUsage: Decodable {
    let primary: CBWindow?
    let secondary: CBWindow?
    let tertiary: CBWindow?
    let extraRateWindows: [CBNamedWindow]?
    let providerCost: CBProviderCost?
    let updatedAt: Date?
    let identity: CBIdentity?
    let loginMethod: String?
}

struct CBLabels: Decodable {
    let primary: String?
    let secondary: String?
    let tertiary: String?
}

struct CBCredits: Decodable {
    let remaining: Double?
}

struct UsagePayload: Decodable {
    let provider: String
    let account: String?
    let source: String?
    let usage: CBUsage?
    let rateWindowLabels: CBLabels?
    let credits: CBCredits?
    let error: CBError?
}

struct CostDailyPayload: Decodable {
    let date: String
    let totalCost: Double?
}

struct CostPayload: Decodable {
    let provider: String
    /// In CodexBar 0.77.0 this equals the `daily` entry for today's local date; we read that entry.
    let sessionCostUSD: Double?
    /// e.g. `listPriceEstimate`: tokens from local logs priced at list prices, not a bill.
    let provenance: String?
    let daily: [CostDailyPayload]?
    let error: CBError?
}

/// One provider's cost history from `codexbar cost`.
public struct CostSummary: Equatable, Sendable {
    public let daily: [DailyCost]
    public let isEstimate: Bool

    public init(daily: [DailyCost], isEstimate: Bool) {
        self.daily = daily
        self.isEstimate = isEstimate
    }

    /// Cost dated `date` (`yyyy-MM-dd`, local); nil when the logs have no entry for that day.
    public func cost(on date: String) -> Double? {
        daily.first { $0.date == date }?.cost
    }
}

public enum CodexBarParser {
    /// Converts `codexbar usage --format json` output into island models.
    public static func parseUsage(_ data: Data) -> [ProviderUsage] {
        CodexBarJSON.decodeList(UsagePayload.self, from: data).map(makeUsage)
    }

    /// Converts `codexbar cost --format json` output into provider id -> daily history.
    public static func parseCost(_ data: Data) -> [String: CostSummary] {
        var result: [String: CostSummary] = [:]
        for payload in CodexBarJSON.decodeList(CostPayload.self, from: data) where payload.error == nil {
            let daily = (payload.daily ?? [])
                .compactMap { entry in entry.totalCost.map { DailyCost(date: entry.date, cost: $0) } }
                .sorted { $0.date < $1.date }
            // Unknown provenance is treated as an estimate too: it comes from local log scans.
            let isEstimate = payload.provenance.map { $0.lowercased().contains("estimate") } ?? true
            result[payload.provider] = CostSummary(daily: daily, isEstimate: isEstimate)
        }
        return result
    }

    /// Attaches cost to usage rows. Cost comes from this Mac's logs for a whole provider, so it is
    /// attached only when exactly one row (account) of that provider is shown; with several
    /// accounts it can't be told apart and is left off rather than shown on each.
    /// `today` is today's local date as `yyyy-MM-dd`.
    public static func attachCosts(
        _ costs: [String: CostSummary], to providers: [ProviderUsage], today: String
    ) -> [ProviderUsage] {
        let bases = providers.map(\.baseID)
        return providers.map { row in
            var row = row
            guard let cost = costs[row.baseID], bases.filter({ $0 == row.baseID }).count == 1 else { return row }
            row.todayCost = cost.cost(on: today)
            row.dailyCosts = cost.daily
            row.costIsEstimate = cost.isEstimate
            return row
        }
    }

    static func makeUsage(_ payload: UsagePayload) -> ProviderUsage {
        // Several accounts of one provider come back as separate rows; keep them apart.
        let id = payload.account.map { "\(payload.provider):\($0)" } ?? payload.provider
        var usage = ProviderUsage(id: id)
        usage.source = payload.source
        usage.error = payload.error?.message ?? (payload.error != nil ? "获取失败" : nil)
        guard let snapshot = payload.usage else { return usage }

        let labels = payload.rateWindowLabels
        var windows: [QuotaWindow] = []
        let lanes: [(String, CBWindow?, String?)] = [
            ("primary", snapshot.primary, labels?.primary),
            ("secondary", snapshot.secondary, labels?.secondary),
            ("tertiary", snapshot.tertiary, labels?.tertiary),
        ]
        var windowBalance: Balance?
        for (key, window, label) in lanes {
            guard let window, window.isSyntheticPlaceholder != true else { continue }
            if BalanceText.isBalanceLabel(label), let balance = BalanceText.parse(window.resetDescription) {
                windowBalance = balance
                continue
            }
            windows.append(QuotaWindow(
                id: key,
                title: label ?? defaultTitle(minutes: window.windowMinutes, fallback: key),
                usedPercent: window.usedPercent,
                windowMinutes: window.windowMinutes,
                resetsAt: window.resetsAt,
                resetDescription: window.resetDescription
            ))
        }
        for named in snapshot.extraRateWindows ?? [] where named.usageKnown != false {
            windows.append(QuotaWindow(
                id: "extra-\(named.id)",
                title: named.title,
                usedPercent: named.window.usedPercent,
                windowMinutes: named.window.windowMinutes,
                resetsAt: named.window.resetsAt,
                resetDescription: named.window.resetDescription
            ))
        }
        usage.windows = windows
        usage.plan = snapshot.identity?.loginMethod ?? snapshot.loginMethod
        usage.updatedAt = snapshot.updatedAt

        if let cost = snapshot.providerCost, let balance = cost.balance {
            usage.balance = Balance(amount: balance, currencyCode: cost.currencyCode ?? "USD")
        } else if let remaining = payload.credits?.remaining {
            usage.balance = Balance(amount: remaining, currencyCode: "credits")
        } else {
            usage.balance = windowBalance
        }
        return usage
    }

    static func defaultTitle(minutes: Int?, fallback: String) -> String {
        switch minutes {
        case 300: return "5 小时"
        case 1440: return "每日"
        case 10080: return "每周"
        case let m? where m >= 40000: return "每月"
        case let m? where m % 60 == 0: return "\(m / 60) 小时"
        case let m?: return "\(m) 分钟"
        case nil:
            switch fallback {
            case "primary": return "会话"
            case "secondary": return "每周"
            default: return "其他"
            }
        }
    }
}

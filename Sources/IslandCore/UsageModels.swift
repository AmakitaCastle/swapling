import Foundation

/// One quota lane of a provider, e.g. Claude's 5-hour session or weekly window.
public struct QuotaWindow: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let usedPercent: Double
    public let windowMinutes: Int?
    public let resetsAt: Date?
    public let resetDescription: String?

    public init(
        id: String,
        title: String,
        usedPercent: Double,
        windowMinutes: Int? = nil,
        resetsAt: Date? = nil,
        resetDescription: String? = nil
    ) {
        self.id = id
        self.title = title
        self.usedPercent = usedPercent
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
        self.resetDescription = resetDescription
    }

    /// Used percentage clamped to 0...100 for display.
    public var clampedUsed: Double { min(max(usedPercent, 0), 100) }
    public var remainingPercent: Double { 100 - clampedUsed }
    public var isExhausted: Bool { usedPercent >= 100 }
}

public struct DailyCost: Equatable, Sendable {
    /// `yyyy-MM-dd` as reported by CodexBar.
    public let date: String
    public let cost: Double

    public init(date: String, cost: Double) {
        self.date = date
        self.cost = cost
    }
}

public struct Balance: Equatable, Sendable {
    public let amount: Double
    public let currencyCode: String
    /// What the amount is made of, e.g. 充值 and 赠送 for DeepSeek; same currency as `amount`.
    public var parts: [BalancePart]

    public init(amount: Double, currencyCode: String, parts: [BalancePart] = []) {
        self.amount = amount
        self.currencyCode = currencyCode
        self.parts = parts
    }
}

public struct BalancePart: Equatable, Sendable {
    public let label: String
    public let amount: Double

    public init(label: String, amount: Double) {
        self.label = label
        self.amount = amount
    }
}

/// Some API-key providers (DeepSeek in CodexBar 0.77.0) report their balance as a quota window
/// titled "Balance" whose used percent is always 0, with the money only in its description:
/// "¥36.94 (Paid: ¥35.75 / Granted: ¥1.18)". There is no total to divide by, so it is a balance.
public enum BalanceText {
    public static func isBalanceLabel(_ label: String?) -> Bool {
        label?.trimmingCharacters(in: .whitespaces).lowercased() == "balance"
    }

    public static func parse(_ text: String?) -> Balance? {
        guard let text else { return nil }
        let amounts = matches(in: text)
        guard let total = amounts.first else { return nil }
        let names = ["paid": "充值", "granted": "赠送", "topped up": "充值", "bonus": "赠送"]
        let parts = amounts.dropFirst().compactMap { match -> BalancePart? in
            guard let label = match.label else { return nil }
            return BalancePart(label: names[label.lowercased()] ?? label, amount: match.amount)
        }
        return Balance(amount: total.amount, currencyCode: total.currency, parts: parts)
    }

    private struct Match {
        var label: String?
        var amount: Double
        var currency: String
    }

    private static let pattern = try! NSRegularExpression(
        pattern: #"(?:([A-Za-z][A-Za-z ]*?)\s*:\s*)?([¥￥$])\s*(-?[0-9][0-9,]*(?:\.[0-9]+)?)"#
    )

    private static func matches(in text: String) -> [Match] {
        let range = NSRange(text.startIndex..., in: text)
        return pattern.matches(in: text, range: range).compactMap { result in
            func group(_ i: Int) -> String? {
                Range(result.range(at: i), in: text).map { String(text[$0]) }
            }
            guard let symbol = group(2), let number = group(3),
                  let amount = Double(number.replacingOccurrences(of: ",", with: ""))
            else { return nil }
            return Match(label: group(1), amount: amount, currency: symbol == "$" ? "USD" : "CNY")
        }
    }
}

/// Everything the island knows about one provider account.
public struct ProviderUsage: Identifiable, Equatable, Sendable {
    public let id: String
    public var windows: [QuotaWindow]
    public var plan: String?
    public var balance: Balance?
    /// Today's cost from this Mac's local logs, for the whole provider (not one account).
    public var todayCost: Double?
    /// The cost is priced from token counts at list prices, not read from a bill.
    public var costIsEstimate = true
    public var dailyCosts: [DailyCost]
    public var error: String?
    /// The provider's original message when `error` was rewritten into a friendlier one.
    public var errorDetail: String?
    /// CodexBar's data source for this row (`web`, `cli`, `oauth`, …), when it reports one.
    public var source: String?
    /// When the data source says it produced these numbers; nil when it doesn't say.
    public var updatedAt: Date?
    /// When Swapling last read valid numbers for this row ("采集于").
    public var fetchedAt: Date?
    /// The latest read failed and the numbers are kept from an earlier one.
    public var isCarriedOver = false

    public init(
        id: String,
        windows: [QuotaWindow] = [],
        plan: String? = nil,
        balance: Balance? = nil,
        todayCost: Double? = nil,
        dailyCosts: [DailyCost] = [],
        error: String? = nil,
        errorDetail: String? = nil,
        updatedAt: Date? = nil,
        fetchedAt: Date? = nil
    ) {
        self.id = id
        self.windows = windows
        self.plan = plan
        self.balance = balance
        self.todayCost = todayCost
        self.dailyCosts = dailyCosts
        self.error = error
        self.errorDetail = errorDetail
        self.updatedAt = updatedAt
        self.fetchedAt = fetchedAt
    }

    /// Anything worth showing besides an error: quota windows or a balance.
    public var hasData: Bool { !windows.isEmpty || balance != nil }

    public var displayName: String { ProviderCatalog.displayName(for: id) }

    /// "claude" for both "claude" and "claude:work".
    public var baseID: String { id.split(separator: ":").first.map(String.init) ?? id }

    /// The window closest to its limit; this is what the collapsed ring shows.
    public var tightestWindow: QuotaWindow? {
        windows.max { $0.usedPercent < $1.usedPercent }
    }

    /// The exhausted window that frees up soonest, used for the reset countdown.
    public var nextResetOfExhausted: QuotaWindow? {
        windows
            .filter { $0.isExhausted && $0.resetsAt != nil }
            .min { ($0.resetsAt ?? .distantFuture) < ($1.resetsAt ?? .distantFuture) }
    }
}

public enum ProviderCatalog {
    /// v1 only shows GPT (Codex and the OpenAI API), Claude and DeepSeek. The CLI still knows every
    /// other provider and their names stay below; widen this set to bring them back.
    public static let visibleBaseIDs: Set<String> = ["codex", "openai", "claude", "deepseek"]

    /// Accepts plain and account-scoped ids ("claude:work").
    public static func isVisible(_ id: String) -> Bool {
        visibleBaseIDs.contains(id.split(separator: ":").first.map(String.init) ?? id)
    }

    private static let names: [String: String] = [
        "claude": "Claude",
        "codex": "Codex",
        "openai": "OpenAI",
        "cursor": "Cursor",
        "gemini": "Gemini",
        "copilot": "Copilot",
        "openrouter": "OpenRouter",
        "zai": "z.ai",
        "kimi": "Kimi",
        "moonshot": "Moonshot",
        "deepseek": "DeepSeek",
        "doubao": "Doubao",
        "qwencloud": "Qwen",
        "antigravity": "Antigravity",
        "grok": "Grok",
        "windsurf": "Windsurf",
        "minimax": "MiniMax",
        "factory": "Factory",
        "amp": "Amp",
        "kiro": "Kiro",
        "workbuddy": "WorkBuddy",
    ]

    /// Accepts plain provider ids ("claude") and account-scoped ids ("claude:work").
    public static func displayName(for id: String) -> String {
        let parts = id.split(separator: ":", maxSplits: 1).map(String.init)
        let base = parts.first ?? id
        let name: String
        if let known = names[base] {
            name = known
        } else if let first = base.first {
            name = first.uppercased() + base.dropFirst()
        } else {
            name = base
        }
        return parts.count > 1 ? "\(name) (\(parts[1]))" : name
    }

    /// Short label that fits beside the notch.
    public static func shortName(for id: String) -> String {
        let base = id.split(separator: ":").first.map(String.init) ?? id
        let name = displayName(for: base)
        return name.count <= 6 ? name : String(name.prefix(5))
    }

    /// One-letter badge per provider, lengthened to the shortest prefix (up to 3 letters) that
    /// tells it apart from the others shown, so Codex and Claude read "Co" and "Cl", not "C" twice.
    public static func badges(for ids: [String]) -> [String: String] {
        let names = ids.map { shortName(for: $0) }
        var result: [String: String] = [:]
        for (index, id) in ids.enumerated() {
            let name = names[index]
            var length = 1
            while length < 3, names.indices.contains(where: { other in
                other != index && names[other].prefix(length).lowercased() == name.prefix(length).lowercased()
            }) {
                length += 1
            }
            result[id] = String(name.prefix(length))
        }
        return result
    }
}

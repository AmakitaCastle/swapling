import Foundation

/// The one character standing at the top of the panel ("看板娘") and why it is that one.
public struct MascotChoice: Equatable, Sendable {
    public enum Reason: Equatable, Sendable {
        /// The AI the user is working with right now, not used up.
        case active
        /// Nothing is used up: the provider that needs attention first.
        case mostUrgent
        /// Something is used up: the best provider still usable, standing in for `exhaustedIDs`.
        case standIn(exhaustedIDs: [String])
        /// Nothing is usable: the used-up provider that comes back first, asleep. Nil when no
        /// used-up provider says when it resets.
        case allExhausted(returnsAt: Date?)
    }

    public let providerID: String
    /// The face follows this provider's own state, not the panel's worst.
    public let mood: CharacterMood
    public let reason: Reason

    public init(providerID: String, mood: CharacterMood, reason: Reason) {
        self.providerID = providerID
        self.mood = mood
        self.reason = reason
    }
}

/// Which provider's character to show, and the one sentence it says about what to use now.
public enum MascotPicker {
    /// `providers` in panel order (ties go to the earlier one). `activeProviderID` is the AI in
    /// use right now (see `ActiveAgent`); it is shown unless it is used up or not in the panel,
    /// in which case the quota rules below pick as usual.
    public static func pick(
        _ providers: [ProviderUsage],
        thresholds: QuotaThresholds,
        now: Date,
        activeProviderID: String? = nil,
        status: (ProviderUsage) -> ProviderStatus
    ) -> MascotChoice? {
        let rated = providers.map { Rated(provider: $0, status: status($0), thresholds: thresholds, now: now) }
        guard !rated.isEmpty else { return nil }
        // "claude" also matches an account row such as "claude:work"; the first in panel order.
        let active = activeProviderID.flatMap { id in rated.first { $0.provider.id == id || $0.provider.baseID == id } }
        if let active, !active.isExhausted {
            return MascotChoice(providerID: active.provider.id, mood: active.mood, reason: .active)
        }
        // The active one leads the list of what ran out, so the bubble names it first.
        let usedUp = rated.filter(\.isExhausted)
        let exhausted = usedUp.filter { $0.provider.id == active?.provider.id }
            + usedUp.filter { $0.provider.id != active?.provider.id }

        if exhausted.isEmpty {
            let urgent = rated.enumerated().min { lhs, rhs in
                let (a, b) = (lhs.element, rhs.element)
                if a.status.attentionRank != b.status.attentionRank { return a.status.attentionRank > b.status.attentionRank }
                if a.used != b.used { return a.used > b.used }
                return lhs.offset < rhs.offset
            }!.element
            return MascotChoice(providerID: urgent.provider.id, mood: urgent.mood, reason: .mostUrgent)
        }

        if let best = bestUsable(rated) {
            return MascotChoice(
                providerID: best.provider.id, mood: best.mood,
                reason: .standIn(exhaustedIDs: exhausted.map(\.provider.id))
            )
        }

        // Soonest back first; an unknown reset never beats a known one.
        let first = exhausted.enumerated().min { lhs, rhs in
            let (a, b) = (lhs.element.returnsAt ?? .distantFuture, rhs.element.returnsAt ?? .distantFuture)
            return a != b ? a < b : lhs.offset < rhs.offset
        }!.element
        return MascotChoice(providerID: first.provider.id, mood: .exhausted, reason: .allExhausted(returnsAt: first.returnsAt))
    }

    /// One sentence for the speech bubble, e.g. "Codex 已经用了 86%，1小时20分后重置，先换 Claude 吧！".
    public static func sentence(
        for choice: MascotChoice,
        providers: [ProviderUsage],
        thresholds: QuotaThresholds,
        now: Date,
        money: MoneyDisplay = .usd,
        status: (ProviderUsage) -> ProviderStatus
    ) -> String {
        let rated = providers.map { Rated(provider: $0, status: status($0), thresholds: thresholds, now: now) }
        guard let me = rated.first(where: { $0.provider.id == choice.providerID }) else { return "" }
        let name = me.provider.displayName

        switch choice.reason {
        case .active:
            let using = "正在用 \(name)，"
            switch me.status {
            case .nearLimit:
                var text = using + "已经用了 \(IslandFormat.percent(me.used))"
                if let reset = me.key?.resetsAt, reset > now {
                    text += "，\(IslandFormat.relative(to: reset, now: now))后重置"
                }
                let calmer = bestUsable(rated.filter { $0.provider.id != me.provider.id && $0.status != .nearLimit })
                return text + (calmer.map { "，快不够的话换 \($0.provider.displayName) 吧！" } ?? "，省着点用哦～")
            case .balance:
                guard let balance = me.provider.balance else { return using + "按余额计费～" }
                return using + "余额还剩 \(money.format(balance.amount, from: balance.currencyCode))，放心用～"
            case .unconfirmed, .limited:
                return using + "暂时读不到可靠的额度数据～"
            case .normal:
                guard me.key != nil else { return using + "放心用～" }
                return using + "额度还剩 \(IslandFormat.percent(100 - me.used))，放心用～"
            }

        case let .allExhausted(returnsAt):
            guard let returnsAt else { return "大家都用完了，恢复时间还不知道……先休息一下吧 zzz" }
            let others = rated.count > 1 ? "大家都用完了，" : ""
            return "\(others)\(name) \(IslandFormat.relative(to: returnsAt, now: now))后最先恢复，先休息一下吧 zzz"

        case let .standIn(exhaustedIDs):
            let out = exhaustedIDs.compactMap { id in rated.first { $0.provider.id == id } }
            let names = out.map(\.provider.displayName).joined(separator: "、")
            let tail = "先去用 \(name) 吧！"
            if out.count == 1, let only = out.first {
                let what = only.status == .limited(partial: true) ? "部分额度用完了" : "用完了"
                guard let back = only.returnsAt else { return "\(names) \(what)，恢复时间未知。\(tail)" }
                return "\(names) \(what)……\(IslandFormat.relative(to: back, now: now))后恢复。\(tail)"
            }
            return "\(names) 都用完了……\(tail)"

        case .mostUrgent:
            switch me.status {
            case .nearLimit:
                var text = "\(name) 已经用了 \(IslandFormat.percent(me.used))"
                if let reset = me.key?.resetsAt, reset > now {
                    text += "，\(IslandFormat.relative(to: reset, now: now))后重置"
                }
                let calmer = bestUsable(rated.filter { $0.provider.id != me.provider.id && $0.status != .nearLimit })
                return text + (calmer.map { "，先换 \($0.provider.displayName) 吧！" } ?? "，省着点用哦～")
            case .normal:
                return rated.count > 1 ? "额度都很充足，放心用吧～" : "\(name) 额度很充足，放心用吧～"
            case .balance:
                if let balance = me.provider.balance {
                    return "\(name) 按余额计费，还剩 \(money.format(balance.amount, from: balance.currencyCode))。"
                }
                return "\(name) 按余额计费。"
            case .unconfirmed, .limited:
                return "暂时读不到可靠的额度数据，稍后再看看吧～"
            }
        }
    }

    /// Quota providers before pay-as-you-go ones, then the least used.
    private static func bestUsable(_ rated: [Rated]) -> Rated? {
        rated.enumerated().filter(\.element.isUsable).min { lhs, rhs in
            let (a, b) = (lhs.element, rhs.element)
            let (balanceA, balanceB) = (a.status == .balance, b.status == .balance)
            if balanceA != balanceB { return !balanceA }
            if a.used != b.used { return a.used < b.used }
            return lhs.offset < rhs.offset
        }?.element
    }

    private struct Rated {
        let provider: ProviderUsage
        let status: ProviderStatus
        let mood: CharacterMood
        let key: QuotaWindow?
        let now: Date

        init(provider: ProviderUsage, status: ProviderStatus, thresholds: QuotaThresholds, now: Date) {
            self.now = now
            self.provider = provider
            self.status = status
            mood = CharacterMood(provider: provider, status: status)
            key = QuotaOverview.keyWindow(of: provider, thresholds: thresholds)
        }

        var used: Double { key?.clampedUsed ?? 0 }

        /// Used up, including a pay-as-you-go balance at or below zero.
        var isExhausted: Bool { mood == .exhausted }

        var isUsable: Bool {
            switch status {
            case .normal, .nearLimit, .balance: return !isExhausted
            case .limited, .unconfirmed: return false
            }
        }

        /// When this used-up provider works again: the combined release time, else its earliest
        /// known window reset.
        var returnsAt: Date? {
            switch QuotaOverview.release(of: provider, now: now) {
            case let .expected(at): return at
            case let .perWindow(resets): return resets.compactMap(\.resetsAt).min()
            case .notLimited: return nil
            }
        }
    }
}

import Foundation

/// Gives pay-as-you-go providers a bar: the balance right after the last top-up counts as full,
/// so the bar shows how much of that top-up is left. Any rise in the balance is a top-up and
/// becomes the new full mark. Shown as an ordinary quota window, so colours and alerts apply.
public enum BalanceGauge {
    public static let windowID = "balance"

    /// - Parameter baselines: Full mark per provider id, in the provider's own currency; updated
    ///   in place and meant to be persisted by the caller.
    public static func apply(_ providers: [ProviderUsage], baselines: inout [String: Double]) -> [ProviderUsage] {
        providers.map { provider in
            var provider = provider
            provider.windows.removeAll { $0.id == windowID }
            guard provider.windows.isEmpty, let balance = provider.balance else { return provider }
            if !provider.isCarriedOver, balance.amount > (baselines[provider.id] ?? 0) {
                baselines[provider.id] = balance.amount
            }
            guard let full = baselines[provider.id], full > 0 else { return provider }
            let left = min(max(balance.amount / full, 0), 1)
            provider.windows = [QuotaWindow(id: windowID, title: "余额", usedPercent: (1 - left) * 100)]
            return provider
        }
    }
}

public extension QuotaWindow {
    var isBalanceGauge: Bool { id == BalanceGauge.windowID }
}

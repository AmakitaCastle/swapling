import Foundation

/// The one-word state of a provider in the panel overview.
public enum ProviderStatus: Equatable, Sendable {
    case normal
    case nearLimit
    /// At least one quota window is used up. `partial` when only model-scoped windows are, so
    /// the provider may still work with other models.
    case limited(partial: Bool)
    /// No trustworthy numbers: an error, old data, or nothing reported.
    case unconfirmed
    /// Pay-as-you-go provider with a balance and no quota windows; judged by its own numbers.
    case balance

    public var label: String {
        switch self {
        case .normal: return "额度正常"
        case .nearLimit: return "接近上限"
        case .limited(partial: false): return "额度受限"
        case .limited(partial: true): return "部分受限"
        case .unconfirmed: return "待确认"
        case .balance: return "按余额"
        }
    }

    /// Higher needs attention sooner; drives the 优先关注 order.
    public var attentionRank: Int {
        switch self {
        case .limited(partial: false): return 5
        case .limited(partial: true): return 4
        case .nearLimit: return 3
        case .normal: return 2
        case .balance: return 1
        case .unconfirmed: return 0
        }
    }
}

public extension QuotaWindow {
    /// The window limits only some models (Claude's Opus/Sonnet weekly lanes, CodexBar's extra
    /// windows), so it running out doesn't stop the whole provider.
    var isModelScoped: Bool {
        if id.hasPrefix("extra-") { return true }
        let title = title.lowercased()
        let modelWords = ["opus", "sonnet", "haiku", "gpt", "gemini", "model", "模型"]
        return modelWords.contains { title.contains($0) }
    }
}

/// When quota comes back, kept apart from "when the next window resets".
public enum LimitRelease: Equatable, Sendable {
    /// Nothing is used up.
    case notLimited
    /// Every used-up window applies to the whole provider and has a reset time: the provider is
    /// expected to work again once the last of them resets.
    case expected(at: Date)
    /// What is used up can't be combined into one time (model-scoped windows or an unknown reset):
    /// list each used-up window with its own reset time, nil when unknown.
    case perWindow([WindowReset])
}

public struct WindowReset: Equatable, Sendable {
    public let window: QuotaWindow
    public let resetsAt: Date?

    public init(window: QuotaWindow, resetsAt: Date?) {
        self.window = window
        self.resetsAt = resetsAt
    }
}

public enum QuotaOverview {
    /// Stale or failed data wins over any number; then used-up, then near the first warning line.
    public static func status(
        of provider: ProviderUsage,
        thresholds: QuotaThresholds,
        refreshInterval: TimeInterval,
        now: Date
    ) -> ProviderStatus {
        guard Freshness.isCurrent(provider, refreshInterval: refreshInterval, now: now) else { return .unconfirmed }
        if provider.windows.isEmpty {
            return provider.balance != nil ? .balance : .unconfirmed
        }
        let exhausted = provider.windows.filter(\.isExhausted)
        if !exhausted.isEmpty {
            return .limited(partial: exhausted.allSatisfy(\.isModelScoped))
        }
        if provider.windows.contains(where: { $0.usedPercent >= Double(thresholds.warn1) }) {
            return .nearLimit
        }
        return .normal
    }

    /// The window shown beside the notch and, unless something is used up, on the card's first
    /// line. The short session (5h) window by default, so the number doesn't flip between windows
    /// as their usage crosses; a longer window takes over only once it needs attention: used up,
    /// or at or past the first warning line and more used than the session window.
    /// Model-scoped windows only show when there is nothing else.
    public static func displayWindow(of provider: ProviderUsage, thresholds: QuotaThresholds) -> QuotaWindow? {
        let whole = provider.windows.filter { !$0.isModelScoped }
        guard !whole.isEmpty else { return provider.tightestWindow }
        if let blocking = whole.filter(\.isExhausted).max(by: { resetOrder($0, $1) }) {
            return blocking
        }
        let session = whole.first { $0.id == "primary" }
            ?? whole.min { ($0.windowMinutes ?? .max) < ($1.windowMinutes ?? .max) }
            ?? whole[0]
        let pressing = whole
            .filter { $0.id != session.id && $0.usedPercent >= Double(thresholds.warn1) && $0.usedPercent > session.usedPercent }
            .max { $0.usedPercent < $1.usedPercent }
        return pressing ?? session
    }

    /// The window shown on the card's first line: a used-up whole-provider window first (it is
    /// what stops work), then any used-up window, then the most used.
    public static func keyWindow(of provider: ProviderUsage, thresholds: QuotaThresholds = .standard) -> QuotaWindow? {
        let exhausted = provider.windows.filter(\.isExhausted)
        if let blocking = exhausted.filter({ !$0.isModelScoped }).max(by: { resetOrder($0, $1) }) {
            return blocking
        }
        if let any = exhausted.max(by: { resetOrder($0, $1) }) { return any }
        return displayWindow(of: provider, thresholds: thresholds)
    }

    /// The next window to reset after `now`, whatever its state ("下一项额度重置").
    public static func nextReset(of provider: ProviderUsage, now: Date) -> WindowReset? {
        provider.windows
            .compactMap { window in window.resetsAt.flatMap { $0 > now ? WindowReset(window: window, resetsAt: $0) : nil } }
            .min { ($0.resetsAt ?? .distantFuture) < ($1.resetsAt ?? .distantFuture) }
    }

    /// When the limit is expected to lift ("相关限制预计解除"). Only combined into one time when
    /// every used-up window covers the whole provider and says when it resets; otherwise each
    /// window keeps its own time and nothing is inferred about the provider as a whole.
    public static func release(of provider: ProviderUsage, now: Date) -> LimitRelease {
        let exhausted = provider.windows.filter(\.isExhausted)
        guard !exhausted.isEmpty else { return .notLimited }
        let resets = exhausted.map { WindowReset(window: $0, resetsAt: $0.resetsAt.flatMap { $0 > now ? $0 : nil }) }
        if exhausted.allSatisfy({ !$0.isModelScoped }), resets.allSatisfy({ $0.resetsAt != nil }),
           let last = resets.compactMap(\.resetsAt).max() {
            return .expected(at: last)
        }
        return .perWindow(resets.sorted { ($0.resetsAt ?? .distantFuture) < ($1.resetsAt ?? .distantFuture) })
    }

    /// Later reset first, so the window that keeps the limit longest is the key one.
    private static func resetOrder(_ lhs: QuotaWindow, _ rhs: QuotaWindow) -> Bool {
        (lhs.resetsAt ?? .distantFuture) < (rhs.resetsAt ?? .distantFuture)
    }
}

/// How the panel lists providers.
public enum PanelOrderMode: String, CaseIterable, Sendable {
    /// CodexBar's provider order, which never changes by itself.
    case fixed
    /// Limited first, then near the limit, normal, balance, unconfirmed.
    case attention

    public var label: String {
        switch self {
        case .fixed: return "固定顺序"
        case .attention: return "优先关注"
        }
    }
}

public enum PanelOrder {
    /// Order for a panel that is opening now.
    public static func ids(
        for providers: [ProviderUsage],
        mode: PanelOrderMode,
        status: (ProviderUsage) -> ProviderStatus
    ) -> [String] {
        switch mode {
        case .fixed:
            return providers.map(\.id)
        case .attention:
            return providers.enumerated().sorted { lhs, rhs in
                let (a, b) = (status(lhs.element), status(rhs.element))
                if a.attentionRank != b.attentionRank { return a.attentionRank > b.attentionRank }
                let usedA = lhs.element.tightestWindow?.usedPercent ?? -1
                let usedB = rhs.element.tightestWindow?.usedPercent ?? -1
                if usedA != usedB { return usedA > usedB }
                return lhs.offset < rhs.offset
            }
            .map(\.element.id)
        }
    }

    /// Keeps cards where they were while the panel is open: providers follow `snapshot`, ones that
    /// appeared since go to the end in their own order, ones that went away drop out.
    public static func arrange(_ providers: [ProviderUsage], snapshot: [String]) -> [ProviderUsage] {
        let byID = Dictionary(providers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let kept = snapshot.compactMap { byID[$0] }
        let added = providers.filter { !snapshot.contains($0.id) }
        return kept + added
    }
}

import Foundation

/// Decisions behind `CodexBarClient.recoverClaude`, kept free of process spawning so they can be tested.
public enum ClaudeFallback {
    static let tokenEnvironmentKey = "CODEXBAR_CLAUDE_OAUTH_TOKEN"
    static let scopesEnvironmentKey = "CODEXBAR_CLAUDE_OAUTH_SCOPES"

    /// Shown when no Claude source works; CodexBar's own message is kept in `errorDetail`.
    public static let friendlyError =
        "没有找到可用的 Claude 登录。在浏览器登录 claude.ai 后点下方「从浏览器导入登录」，或在终端运行 `claude` 并输入 /login 登录 Claude 账号（任选其一）。"

    /// The failed row is one our fallback gave up on, so offering the browser import makes sense.
    public static func offersBrowserImport(_ usage: ProviderUsage) -> Bool {
        isClaude(usage.id) && usage.error == friendlyError
    }

    /// Reads `codexbar cookie refresh --format json`: `[{"provider","status","message"}]`,
    /// status one of refreshed / skipped / blocked / failed.
    static func cookieRefreshOutcome(_ data: Data) -> (refreshed: Bool, message: String?) {
        struct Row: Decodable {
            let status: String?
            let message: String?
        }
        guard let rows = try? JSONDecoder().decode([Row].self, from: data), let row = rows.first else {
            return (false, nil)
        }
        return (row.status == "refreshed", row.message)
    }

    /// After every source failed, wait this long before spawning them again; the `cli` source
    /// drives an interactive `claude` session for up to a minute.
    static let failureCooldown: TimeInterval = 10 * 60

    static let memory = Memory()

    static func isClaude(_ id: String) -> Bool {
        id == "claude" || id.hasPrefix("claude:")
    }

    static func isFailedClaudeRow(_ usage: ProviderUsage) -> Bool {
        isClaude(usage.id) && usage.error != nil
    }

    /// The user chose a Claude source (anything but `auto`) in the CodexBar config; respect it.
    static func isSourcePinned(configData: Data?) -> Bool {
        struct Config: Decodable {
            struct Provider: Decodable {
                let id: String
                let source: String?
            }
            let providers: [Provider]?
        }
        guard let configData, let config = try? JSONDecoder().decode(Config.self, from: configData) else {
            return false
        }
        guard let source = config.providers?.first(where: { $0.id == "claude" })?.source else { return false }
        return !source.isEmpty && source != "auto"
    }

    /// OAuth only with a usable Claude Code token; the `claude` PTY unless the failed row came from
    /// an explicit `cli` run (it also renews that token itself). `auto` does not count: the main
    /// call runs without the tool PATH, so its PTY step usually could not even start `claude`. The source that worked last time goes first.
    static func sources(hasToken: Bool, preferred: String?, alreadyTried: Set<String> = []) -> [String] {
        var sources = (hasToken ? ["oauth", "cli"] : ["cli"]).filter { !alreadyTried.contains($0) }
        if let preferred, let index = sources.firstIndex(of: preferred) {
            sources.insert(sources.remove(at: index), at: 0)
        }
        return sources
    }

    /// Swaps the failed Claude rows for the retry's rows, in place of the first failed row.
    /// Nil when the retry produced no Claude row without an error.
    static func replacingFailedClaudeRows(in providers: [ProviderUsage], with retry: [ProviderUsage]) -> [ProviderUsage]? {
        let good = retry.filter { isClaude($0.id) && $0.error == nil }
        guard !good.isEmpty, let position = providers.firstIndex(where: isFailedClaudeRow) else { return nil }
        let goodIDs = Set(good.map(\.id))
        var result = providers
        result.removeAll { isFailedClaudeRow($0) || goodIDs.contains($0.id) }
        let insertAt = providers[..<position].filter { !isFailedClaudeRow($0) && !goodIDs.contains($0.id) }.count
        result.insert(contentsOf: good, at: insertAt)
        return result
    }

    /// Replaces CodexBar's English error on failed Claude rows with one actionable sentence.
    static func explainingFailure(_ providers: [ProviderUsage]) -> [ProviderUsage] {
        providers.map { usage in
            guard isFailedClaudeRow(usage), usage.error != friendlyError else { return usage }
            var usage = usage
            usage.errorDetail = usage.error
            usage.error = friendlyError
            return usage
        }
    }

    /// Which Claude source last worked, and when every source last failed. In memory only.
    final class Memory: @unchecked Sendable {
        private let lock = NSLock()
        private var source: String?
        private var failedAt: Date?

        var workingSource: String? {
            lock.lock(); defer { lock.unlock() }
            return source
        }

        func recordSuccess(_ source: String) {
            lock.lock(); defer { lock.unlock() }
            self.source = source
            failedAt = nil
        }

        func reset() {
            lock.lock(); defer { lock.unlock() }
            failedAt = nil
        }

        func recordFailure(now: Date = Date()) {
            lock.lock(); defer { lock.unlock() }
            failedAt = now
        }

        func isCoolingDown(now: Date = Date()) -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard let failedAt else { return false }
            return now.timeIntervalSince(failedAt) < ClaudeFallback.failureCooldown
        }
    }
}

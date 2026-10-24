import Foundation

/// Which AI the user is working with right now, from the frontmost app or, when that is a
/// terminal/editor (or anything else), from the newest local CLI session log.
public enum ActiveAgent {
    /// How long after its last write a CLI session log still counts as "in use".
    public static let recentLogWindow: TimeInterval = 10 * 60

    /// Desktop apps that are one provider. ChatGPT.app ships as `com.openai.codex` (the merged
    /// ChatGPT/Codex app); `com.openai.chat` is the older ChatGPT build.
    private static let apps: [String: String] = [
        "com.anthropic.claudefordesktop": "claude",
        "com.openai.chat": "codex",
        "com.openai.codex": "codex",
    ]

    /// The provider an app belongs to, nil for terminals, editors and everything else.
    public static func providerID(forBundleID bundleID: String) -> String? {
        apps[bundleID]
    }

    /// The provider a CLI session log belongs to: Claude Code writes `~/.claude/projects/**.jsonl`,
    /// Codex CLI writes `~/.codex/sessions/**.jsonl`.
    public static func providerID(forSessionLog path: String) -> String? {
        guard path.hasSuffix(".jsonl") else { return nil }
        if path.contains("/.claude/projects/") { return "claude" }
        if path.contains("/.codex/sessions/") { return "codex" }
        return nil
    }

    public struct SessionLog: Equatable, Sendable {
        public let path: String
        public let modified: Date

        public init(path: String, modified: Date) {
            self.path = path
            self.modified = modified
        }
    }

    /// The frontmost app wins when it is an AI app; otherwise the most recently written CLI
    /// session log, if written within `recentLogWindow`. Nil when nothing points anywhere.
    public static func resolve(frontmostBundleID: String?, logs: [SessionLog], now: Date) -> String? {
        if let id = frontmostBundleID.flatMap(providerID(forBundleID:)) { return id }
        return logs
            .filter { now.timeIntervalSince($0.modified) <= recentLogWindow }
            .compactMap { log in providerID(forSessionLog: log.path).map { (id: $0, at: log.modified) } }
            .max { $0.at < $1.at }?
            .id
    }
}

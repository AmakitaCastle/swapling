import AppKit
import IslandCore

/// Watches which app is in front and which local CLI session logs were written lately, so the
/// panel's character can follow the AI the user is working with (`ActiveAgent` decides).
@MainActor
final class ActiveAgentMonitor {
    /// The last frontmost app other than Swapling itself, so opening the panel doesn't count.
    private(set) var lastFrontmostBundleID: String?
    private var observer: NSObjectProtocol?

    init(onChange: @escaping @MainActor () -> Void) {
        lastFrontmostBundleID = Self.foreignBundleID(NSWorkspace.shared.frontmostApplication)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                guard let self, let id = Self.foreignBundleID(app), id != self.lastFrontmostBundleID else { return }
                self.lastFrontmostBundleID = id
                onChange()
            }
        }
    }

    /// The provider in use now, or nil when nothing points at one.
    func detect(now: Date = Date()) -> String? {
        ActiveAgent.resolve(frontmostBundleID: lastFrontmostBundleID, logs: Self.recentLogs(now: now), now: now)
    }

    private static func foreignBundleID(_ app: NSRunningApplication?) -> String? {
        guard let id = app?.bundleIdentifier, id != Bundle.main.bundleIdentifier else { return nil }
        return id
    }

    // MARK: Session logs (modification times only; contents are never read)

    /// Upper bound on files looked at per scan, so a huge history stays cheap.
    private static let scanLimit = 2000

    static func recentLogs(now: Date) -> [ActiveAgent.SessionLog] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        // Claude Code: ~/.claude/projects/<project>/<session>.jsonl.
        let claudeDirs = subdirectories(of: home.appendingPathComponent(".claude/projects"))
        // Codex CLI: ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl; today and yesterday cover the window.
        let calendar = Calendar.current
        let codexDirs = [now, now.addingTimeInterval(-86400)].map { day in
            let parts = calendar.dateComponents([.year, .month, .day], from: day)
            return home.appendingPathComponent(String(
                format: ".codex/sessions/%04d/%02d/%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0
            ))
        }
        var logs: [ActiveAgent.SessionLog] = []
        var seen = 0
        for dir in claudeDirs + codexDirs {
            for file in files(in: dir) where file.pathExtension == "jsonl" {
                seen += 1
                if seen > scanLimit { return logs }
                guard let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                      now.timeIntervalSince(modified) <= ActiveAgent.recentLogWindow else { continue }
                logs.append(ActiveAgent.SessionLog(path: file.path, modified: modified))
            }
        }
        return logs
    }

    private static func subdirectories(of url: URL) -> [URL] {
        files(in: url).filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }

    private static func files(in url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
    }
}

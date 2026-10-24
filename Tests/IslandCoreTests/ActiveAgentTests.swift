import XCTest
@testable import IslandCore

final class ActiveAgentTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000)
    private let home = "/Users/me"

    private func log(_ path: String, minutesAgo: Double) -> ActiveAgent.SessionLog {
        ActiveAgent.SessionLog(path: home + path, modified: now.addingTimeInterval(-minutesAgo * 60))
    }

    func testDesktopAppsMapToTheirProvider() {
        XCTAssertEqual(ActiveAgent.providerID(forBundleID: "com.anthropic.claudefordesktop"), "claude")
        XCTAssertEqual(ActiveAgent.providerID(forBundleID: "com.openai.codex"), "codex")
        XCTAssertEqual(ActiveAgent.providerID(forBundleID: "com.openai.chat"), "codex")
        XCTAssertNil(ActiveAgent.providerID(forBundleID: "com.apple.Terminal"))
        XCTAssertNil(ActiveAgent.providerID(forBundleID: "com.microsoft.VSCode"))
    }

    func testSessionLogsMapToTheirCLI() {
        XCTAssertEqual(ActiveAgent.providerID(forSessionLog: home + "/.claude/projects/-Users-me-app/abc.jsonl"), "claude")
        XCTAssertEqual(ActiveAgent.providerID(forSessionLog: home + "/.codex/sessions/2026/10/24/rollout-1.jsonl"), "codex")
        XCTAssertNil(ActiveAgent.providerID(forSessionLog: home + "/.claude/projects/x/notes.md"))
        XCTAssertNil(ActiveAgent.providerID(forSessionLog: home + "/Documents/log.jsonl"))
    }

    func testFrontmostAIAppWinsOverLogs() {
        let logs = [log("/.codex/sessions/2026/10/24/r.jsonl", minutesAgo: 0)]
        XCTAssertEqual(ActiveAgent.resolve(frontmostBundleID: "com.anthropic.claudefordesktop", logs: logs, now: now), "claude")
    }

    func testTerminalFallsBackToTheNewestRecentLog() {
        let logs = [
            log("/.claude/projects/a/1.jsonl", minutesAgo: 6),
            log("/.codex/sessions/2026/10/24/r.jsonl", minutesAgo: 2),
        ]
        XCTAssertEqual(ActiveAgent.resolve(frontmostBundleID: "com.apple.Terminal", logs: logs, now: now), "codex")
        XCTAssertEqual(ActiveAgent.resolve(frontmostBundleID: nil, logs: logs, now: now), "codex")
    }

    func testOldLogsMeanNothingIsActive() {
        let logs = [log("/.claude/projects/a/1.jsonl", minutesAgo: 11)]
        XCTAssertNil(ActiveAgent.resolve(frontmostBundleID: "com.apple.Terminal", logs: logs, now: now))
    }
}

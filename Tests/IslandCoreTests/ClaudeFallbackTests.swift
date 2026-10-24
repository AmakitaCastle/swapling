import XCTest
@testable import IslandCore

final class ClaudeCodeCredentialsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func json(expiresIn seconds: Double?, scopes: [String]?) -> Data {
        var oauth: [String: Any] = ["accessToken": "test-token", "refreshToken": "test-refresh"]
        if let seconds { oauth["expiresAt"] = (now.timeIntervalSince1970 + seconds) * 1000 }
        if let scopes { oauth["scopes"] = scopes }
        return try! JSONSerialization.data(withJSONObject: ["claudeAiOauth": oauth])
    }

    func testValidCredentials() {
        let credentials = ClaudeCodeCredentials.parse(
            json(expiresIn: 3600, scopes: ["user:inference", "user:profile"]), now: now
        )
        XCTAssertEqual(credentials?.accessToken, "test-token")
        XCTAssertEqual(credentials?.scopes, ["user:inference", "user:profile"])
    }

    func testExpiredOrAboutToExpireIsRejected() {
        XCTAssertNil(ClaudeCodeCredentials.parse(json(expiresIn: -10, scopes: ["user:profile"]), now: now))
        XCTAssertNil(ClaudeCodeCredentials.parse(json(expiresIn: 30, scopes: ["user:profile"]), now: now))
    }

    func testMissingProfileScopeIsRejected() {
        XCTAssertNil(ClaudeCodeCredentials.parse(json(expiresIn: 3600, scopes: ["user:inference"]), now: now))
    }

    func testUnlistedScopesAndExpiryAreAccepted() {
        XCTAssertNotNil(ClaudeCodeCredentials.parse(json(expiresIn: nil, scopes: nil), now: now))
    }

    func testMCPOnlyItemIsRejected() {
        let data = Data(#"{"mcpOAuth":{"server|abc":{"accessToken":"x","expiresAt":0}}}"#.utf8)
        XCTAssertNil(ClaudeCodeCredentials.parse(data, now: now))
        XCTAssertNil(ClaudeCodeCredentials.parse(Data("not json".utf8), now: now))
    }

    func testCredentialFilesHonorClaudeConfigDir() {
        let home = URL(fileURLWithPath: "/Users/me")
        XCTAssertEqual(
            ClaudeCodeCredentials.credentialFileURLs(environment: ["CLAUDE_CONFIG_DIR": "/tmp/cc"], home: home).map(\.path),
            ["/tmp/cc/.credentials.json", "/Users/me/.claude/.credentials.json"]
        )
        XCTAssertEqual(
            ClaudeCodeCredentials.credentialFileURLs(environment: [:], home: home).map(\.path),
            ["/Users/me/.claude/.credentials.json"]
        )
    }
}

final class ClaudeFallbackTests: XCTestCase {
    private func row(_ id: String, error: String? = nil, used: Double? = nil) -> ProviderUsage {
        ProviderUsage(
            id: id,
            windows: used.map { [QuotaWindow(id: "primary", title: "5 小时", usedPercent: $0)] } ?? [],
            error: error
        )
    }

    func testSourcesOrder() {
        XCTAssertEqual(ClaudeFallback.sources(hasToken: true, preferred: nil), ["oauth", "cli"])
        XCTAssertEqual(ClaudeFallback.sources(hasToken: true, preferred: "cli"), ["cli", "oauth"])
        XCTAssertEqual(ClaudeFallback.sources(hasToken: false, preferred: "oauth"), ["cli"])
        XCTAssertEqual(ClaudeFallback.sources(hasToken: true, preferred: nil, alreadyTried: ["cli"]), ["oauth"])
        XCTAssertEqual(ClaudeFallback.sources(hasToken: false, preferred: nil, alreadyTried: ["cli"]), [])
    }

    func testPinnedSourceDetection() {
        func config(_ source: String?) -> Data {
            var claude: [String: Any] = ["id": "claude", "enabled": true]
            if let source { claude["source"] = source }
            return try! JSONSerialization.data(withJSONObject: ["version": 1, "providers": [claude]])
        }
        XCTAssertFalse(ClaudeFallback.isSourcePinned(configData: nil))
        XCTAssertFalse(ClaudeFallback.isSourcePinned(configData: config(nil)))
        XCTAssertFalse(ClaudeFallback.isSourcePinned(configData: config("auto")))
        XCTAssertTrue(ClaudeFallback.isSourcePinned(configData: config("web")))
    }

    func testReplacesFailedClaudeRowInPlace() {
        let providers = [row("codex", used: 10), row("claude", error: "No Claude session key"), row("gemini", used: 5)]
        let merged = ClaudeFallback.replacingFailedClaudeRows(in: providers, with: [row("claude", used: 42)])
        XCTAssertEqual(merged?.map(\.id), ["codex", "claude", "gemini"])
        XCTAssertNil(merged?[1].error)
        XCTAssertEqual(merged?[1].windows.first?.usedPercent, 42)
    }

    func testFailedRetryLeavesRowsAlone() {
        let providers = [row("claude", error: "a")]
        XCTAssertNil(ClaudeFallback.replacingFailedClaudeRows(in: providers, with: [row("claude", error: "b")]))
        XCTAssertNil(ClaudeFallback.replacingFailedClaudeRows(in: providers, with: []))
        XCTAssertNil(ClaudeFallback.replacingFailedClaudeRows(in: [row("claude", used: 1)], with: [row("claude", used: 2)]))
    }

    func testExplainingFailureKeepsOriginalError() {
        let explained = ClaudeFallback.explainingFailure([row("codex", error: "codex down"), row("claude:work", error: "raw")])
        XCTAssertEqual(explained[0].error, "codex down")
        XCTAssertNil(explained[0].errorDetail)
        XCTAssertEqual(explained[1].error, ClaudeFallback.friendlyError)
        XCTAssertEqual(explained[1].errorDetail, "raw")
    }

    func testCookieRefreshOutcome() {
        let blocked = Data(#"[{"message":"Retry with --allow-keychain-prompt","provider":"claude","status":"blocked"}]"#.utf8)
        XCTAssertFalse(ClaudeFallback.cookieRefreshOutcome(blocked).refreshed)
        XCTAssertEqual(ClaudeFallback.cookieRefreshOutcome(blocked).message, "Retry with --allow-keychain-prompt")
        let ok = Data(#"[{"provider":"claude","status":"refreshed"}]"#.utf8)
        XCTAssertTrue(ClaudeFallback.cookieRefreshOutcome(ok).refreshed)
        XCTAssertFalse(ClaudeFallback.cookieRefreshOutcome(Data()).refreshed)
    }

    func testBrowserImportOfferedOnlyForExplainedClaudeFailure() {
        let explained = ClaudeFallback.explainingFailure([row("claude", error: "raw"), row("codex", error: "raw")])
        XCTAssertTrue(ClaudeFallback.offersBrowserImport(explained[0]))
        XCTAssertFalse(ClaudeFallback.offersBrowserImport(explained[1]))
        XCTAssertFalse(ClaudeFallback.offersBrowserImport(row("claude", error: "raw")))
    }

    func testMemoryCooldown() {
        let memory = ClaudeFallback.Memory()
        let start = Date()
        XCTAssertFalse(memory.isCoolingDown(now: start))
        memory.recordFailure(now: start)
        XCTAssertTrue(memory.isCoolingDown(now: start.addingTimeInterval(60)))
        XCTAssertFalse(memory.isCoolingDown(now: start.addingTimeInterval(ClaudeFallback.failureCooldown + 1)))
        memory.recordSuccess("cli")
        XCTAssertEqual(memory.workingSource, "cli")
        XCTAssertFalse(memory.isCoolingDown(now: start))
    }

    func testChildEnvironmentAppendsToolDirectories() {
        let env = CodexBarClient.childEnvironment(["PATH": "/usr/bin:/bin:/opt/homebrew/bin"], home: "/Users/me")
        let path = env["PATH"]!.split(separator: ":").map(String.init)
        XCTAssertEqual(Array(path.prefix(3)), ["/usr/bin", "/bin", "/opt/homebrew/bin"])
        XCTAssertTrue(path.contains("/Users/me/.local/bin"))
        XCTAssertEqual(path.filter { $0 == "/opt/homebrew/bin" }.count, 1)
    }
}

import XCTest
@testable import IslandCore

final class DataIssueTests: XCTestCase {
    func testClientErrorsMapToStates() {
        XCTAssertEqual(DataIssue.classify(CodexBarClientError.cliNotFound), .cliMissing)
        XCTAssertEqual(DataIssue.classify(CodexBarClientError.timedOut), .timeout)
        XCTAssertEqual(DataIssue.classify(CodexBarClientError.emptyOutput(stderr: "")), .notConfigured)
        XCTAssertEqual(DataIssue.classify(CodexBarClientError.emptyOutput(stderr: "Could not connect to the server")), .network)
        XCTAssertEqual(DataIssue.classify(CodexBarClientError.commandFailed("HTTP 401 Unauthorized")), .auth)
    }

    func testProviderMessages() {
        XCTAssertEqual(DataIssue.classify("No Claude session key found in browser cookies."), .auth)
        XCTAssertEqual(DataIssue.classify("Missing API key for openrouter"), .apiKey)
        XCTAssertEqual(DataIssue.classify("Google no longer supports Gemini CLI OAuth"), .unsupported)
        XCTAssertEqual(DataIssue.classify("The request timed out."), .timeout)
        XCTAssertEqual(DataIssue.classify("The Internet connection appears to be offline."), .network)
        XCTAssertEqual(DataIssue.classify("HTTP 503"), .server)
        XCTAssertEqual(DataIssue.classify("weird"), .other)
        XCTAssertEqual(DataIssue.classify("没有找到可用的 Claude 登录。在浏览器登录…"), .auth)
    }

    func testEveryStateHasANextStep() {
        let all: [DataIssue] = [
            .notConfigured, .cliMissing, .auth, .apiKey, .unsupported,
            .network, .timeout, .rateLimited, .server, .toolMissing, .other,
        ]
        for issue in all {
            XCTAssertFalse(issue.actions.isEmpty, "\(issue)")
            XCTAssertFalse(issue.hint.isEmpty, "\(issue)")
        }
        XCTAssertEqual(DataIssue.notConfigured.actions, [.openSettings])
        XCTAssertEqual(DataIssue.auth.actions.first, .signIn)
        XCTAssertEqual(DataIssue.network.actions, [.retry])
    }

    func testUnknownIsNeverNormal() {
        let thresholds = QuotaThresholds.standard
        // No window at all (error rows, balance-only rows) has no level but unknown.
        XCTAssertEqual(thresholds.level(for: ProviderUsage(id: "claude", error: "x").tightestWindow), .unknown)
        XCTAssertEqual(QuotaLevel.unknown.label, "未知")
        XCTAssertNotEqual(QuotaLevel.unknown, .normal)
    }
}

final class DataIssueSettingsPageTests: XCTestCase {
    func testSettingsButtonOpensThePageThatFixesIt() {
        // Open issue 3 / CU-07: the button used to land on 显示 for provider problems.
        XCTAssertEqual(DataIssue.notConfigured.settingsPage, .providers)
        XCTAssertEqual(DataIssue.apiKey.settingsPage, .providers)
        XCTAssertEqual(DataIssue.unsupported.settingsPage, .providers)
        // The fallback CLI path lives under 显示 → 数据.
        XCTAssertEqual(DataIssue.cliMissing.settingsPage, .display)
    }
}

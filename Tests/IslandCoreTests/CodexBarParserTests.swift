import XCTest
@testable import IslandCore

final class CodexBarParserTests: XCTestCase {
    // Shape copied from CodexBar's docs/cli.md sample, trimmed, plus a failing provider.
    private let usageJSON = """
    [
      {
        "provider": "codex",
        "version": "0.6.0",
        "source": "openai-web",
        "usage": {
          "primary": { "usedPercent": 28, "windowMinutes": 300, "resetsAt": "2025-12-04T19:15:00Z" },
          "secondary": { "usedPercent": 59, "windowMinutes": 10080, "resetsAt": "2025-12-05T17:00:00Z" },
          "tertiary": null,
          "updatedAt": "2025-12-04T18:10:22Z",
          "identity": { "providerID": "codex", "loginMethod": "plus" },
          "details": [{ "title": "x", "rows": [] }]
        },
        "credits": { "remaining": 112.4, "updatedAt": "2025-12-04T18:10:21Z" }
      },
      {
        "provider": "claude",
        "source": "oauth",
        "usage": {
          "primary": { "usedPercent": 0, "windowMinutes": 300, "isSyntheticPlaceholder": true },
          "secondary": { "usedPercent": 100, "windowMinutes": 10080, "resetsAt": "2025-12-06T00:00:00.500Z" },
          "extraRateWindows": [
            { "id": "opus", "title": "Opus", "window": { "usedPercent": 40 }, "usageKnown": true },
            { "id": "unknown", "title": "Hidden", "window": { "usedPercent": 0 }, "usageKnown": false }
          ]
        },
        "rateWindowLabels": { "secondary": "Weekly" }
      },
      { "provider": "cursor", "source": "web", "error": { "code": 1, "message": "No session" } },
      { "this": "row is garbage" }
    ]
    """

    func testParsesUsageRows() throws {
        let providers = CodexBarParser.parseUsage(Data(usageJSON.utf8))
        XCTAssertEqual(providers.map(\.id), ["codex", "claude", "cursor"])

        let codex = providers[0]
        XCTAssertEqual(codex.windows.map(\.title), ["5 小时", "每周"])
        XCTAssertEqual(codex.windows.first?.usedPercent, 28)
        XCTAssertEqual(codex.plan, "plus")
        XCTAssertEqual(codex.balance, Balance(amount: 112.4, currencyCode: "credits"))
        XCTAssertEqual(codex.tightestWindow?.id, "secondary")

        let claude = providers[1]
        // Synthetic placeholder and unknown extra windows are dropped.
        XCTAssertEqual(claude.windows.map(\.id), ["secondary", "extra-opus"])
        XCTAssertEqual(claude.windows.first?.title, "Weekly")
        XCTAssertNotNil(claude.windows.first?.resetsAt, "fractional-second dates decode")
        XCTAssertEqual(claude.nextResetOfExhausted?.id, "secondary")

        XCTAssertEqual(providers[2].error, "No session")
    }

    func testParsesCost() {
        let json = """
        [
          { "provider": "claude", "source": "local", "sessionCostUSD": 3.5,
            "daily": [ { "date": "2025-12-04", "totalCost": 2 }, { "date": "2025-12-03", "totalCost": 1 } ] },
          { "provider": "cursor", "source": "web", "daily": [], "error": { "message": "off" } }
        ]
        """
        let costs = CodexBarParser.parseCost(Data(json.utf8))
        XCTAssertEqual(costs["claude"]?.cost(on: "2025-12-04"), 2)
        XCTAssertNil(costs["claude"]?.cost(on: "2025-12-05"), "no entry for a day means unknown, not 0")
        XCTAssertEqual(costs["claude"]?.daily.map(\.date), ["2025-12-03", "2025-12-04"])
        XCTAssertEqual(costs["claude"]?.isEstimate, true)
        XCTAssertNil(costs["cursor"])
    }

    func testCostProvenance() {
        let json = """
        [
          { "provider": "codex", "provenance": "listPriceEstimate", "daily": [] },
          { "provider": "cursor", "provenance": "billed", "daily": [] }
        ]
        """
        let costs = CodexBarParser.parseCost(Data(json.utf8))
        XCTAssertEqual(costs["codex"]?.isEstimate, true)
        XCTAssertEqual(costs["cursor"]?.isEstimate, false)
    }

    func testCostAttachesOnlyToAnUnambiguousRow() {
        let costs = [
            "claude": CostSummary(daily: [DailyCost(date: "2026-10-19", cost: 2.5)], isEstimate: true),
            "codex": CostSummary(daily: [DailyCost(date: "2026-10-19", cost: 1.5)], isEstimate: true),
        ]
        let rows = [ProviderUsage(id: "claude:work"), ProviderUsage(id: "claude:home"), ProviderUsage(id: "codex")]
        let attached = CodexBarParser.attachCosts(costs, to: rows, today: "2026-10-19")
        // Two Claude accounts: local logs can't say which one spent it.
        XCTAssertNil(attached[0].todayCost)
        XCTAssertTrue(attached[1].dailyCosts.isEmpty)
        XCTAssertEqual(attached[2].todayCost, 1.5)
        XCTAssertTrue(attached[2].costIsEstimate)
    }

    func testAccountRowsKeepSeparateIDs() {
        let json = """
        [{ "provider": "claude", "account": "work", "usage": { "primary": { "usedPercent": 10 } } }]
        """
        let providers = CodexBarParser.parseUsage(Data(json.utf8))
        XCTAssertEqual(providers.first?.id, "claude:work")
        XCTAssertEqual(providers.first?.displayName, "Claude (work)")
    }

    func testGarbageReturnsEmpty() {
        XCTAssertTrue(CodexBarParser.parseUsage(Data("not json".utf8)).isEmpty)
    }
}

final class ProviderBadgeTests: XCTestCase {
    func testCodexAndClaudeGetDistinctBadges() {
        let badges = ProviderCatalog.badges(for: ["codex", "claude"])
        XCTAssertEqual(badges["codex"], "Co")
        XCTAssertEqual(badges["claude"], "Cl")
        XCTAssertNotEqual(badges["codex"], badges["claude"])
    }

    func testUniqueInitialStaysOneLetter() {
        let badges = ProviderCatalog.badges(for: ["codex", "antigravity", "gemini"])
        XCTAssertEqual(badges, ["codex": "C", "antigravity": "A", "gemini": "G"])
    }

    func testBadgesCapAtThreeLetters() {
        let badges = ProviderCatalog.badges(for: ["claude:work", "claude:home"])
        XCTAssertEqual(badges["claude:work"], "Cla")
        XCTAssertEqual(badges["claude:home"], "Cla")
    }
}

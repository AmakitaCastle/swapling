import XCTest
@testable import IslandCore

final class MascotPickerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000)

    private func row(_ id: String, _ used: Double, reset hours: Double? = 2, error: String? = nil) -> ProviderUsage {
        ProviderUsage(id: id, windows: [
            QuotaWindow(id: "primary", title: "Session", usedPercent: used, windowMinutes: 300,
                        resetsAt: hours.map { now.addingTimeInterval($0 * 3600) }),
        ], error: error, fetchedAt: now)
    }

    private func status(_ provider: ProviderUsage) -> ProviderStatus {
        QuotaOverview.status(of: provider, thresholds: .standard, refreshInterval: 120, now: now)
    }

    private func pick(_ providers: [ProviderUsage]) -> MascotChoice? {
        MascotPicker.pick(providers, thresholds: .standard, now: now, status: status)
    }

    private func say(_ providers: [ProviderUsage]) -> String {
        guard let choice = pick(providers) else { return "" }
        return MascotPicker.sentence(for: choice, providers: providers, thresholds: .standard, now: now, status: status)
    }

    func testNothingToShowWithoutProviders() {
        XCTAssertNil(pick([]))
    }

    func testMostUrgentWhenNothingIsUsedUp() {
        let choice = pick([row("claude", 42), row("codex", 86), row("gemini", 63)])
        XCTAssertEqual(choice, MascotChoice(providerID: "codex", mood: .worried, reason: .mostUrgent))
    }

    func testMostUrgentTiesGoToPanelOrder() {
        XCTAssertEqual(pick([row("claude", 40), row("codex", 40)])?.providerID, "claude")
    }

    func testUnconfirmedNeverOutranksRealNumbers() {
        let choice = pick([row("openai", 0, error: "401 Unauthorized"), row("claude", 10)])
        XCTAssertEqual(choice?.providerID, "claude")
    }

    func testUsedUpHandsOverToTheLeastUsedUsableProvider() {
        let choice = pick([row("codex", 100), row("claude", 63), row("gemini", 20)])
        XCTAssertEqual(choice, MascotChoice(providerID: "gemini", mood: .normal, reason: .standIn(exhaustedIDs: ["codex"])))
    }

    func testStandInKeepsItsOwnMood() {
        let choice = pick([row("claude", 100), row("codex", 86)])
        XCTAssertEqual(choice?.providerID, "codex")
        XCTAssertEqual(choice?.mood, .worried)
    }

    func testStandInTiesGoToPanelOrder() {
        XCTAssertEqual(pick([row("claude", 100), row("codex", 30), row("gemini", 30)])?.providerID, "codex")
    }

    func testQuotaProvidersBeatPayAsYouGo() {
        let balance = ProviderUsage(id: "openrouter", balance: Balance(amount: 12, currencyCode: "USD"), fetchedAt: now)
        XCTAssertEqual(pick([row("claude", 100), balance, row("codex", 70)])?.providerID, "codex")
        XCTAssertEqual(pick([row("claude", 100), balance])?.providerID, "openrouter")
    }

    func testEmptyBalanceCountsAsUsedUp() {
        let broke = ProviderUsage(id: "openrouter", balance: Balance(amount: 0, currencyCode: "USD"), fetchedAt: now)
        let choice = pick([broke, row("claude", 50)])
        XCTAssertEqual(choice?.reason, .standIn(exhaustedIDs: ["openrouter"]))
    }

    func testPartlyLimitedProviderIsNotAStandIn() {
        var opus = row("claude", 20)
        opus.windows.append(QuotaWindow(id: "extra-opus", title: "Opus", usedPercent: 100))
        XCTAssertEqual(pick([opus, row("codex", 50)])?.providerID, "codex")
    }

    func testAllUsedUpSleepsOnTheOneBackFirst() {
        let choice = pick([row("claude", 100, reset: 2), row("codex", 100, reset: 0.75), row("gemini", 100, reset: nil)])
        XCTAssertEqual(choice, MascotChoice(
            providerID: "codex", mood: .exhausted, reason: .allExhausted(returnsAt: now.addingTimeInterval(0.75 * 3600))
        ))
    }

    func testAllUsedUpWithUnknownResets() {
        let choice = pick([row("claude", 100, reset: nil), row("codex", 100, reset: nil)])
        XCTAssertEqual(choice, MascotChoice(providerID: "claude", mood: .exhausted, reason: .allExhausted(returnsAt: nil)))
    }

    func testUsedUpWithOnlyUnconfirmedOthersStillSleeps() {
        let choice = pick([row("openai", 0, error: "401"), row("claude", 100, reset: 1)])
        XCTAssertEqual(choice?.providerID, "claude")
        XCTAssertEqual(choice?.mood, .exhausted)
    }

    // MARK: Sentences

    func testNearLimitSuggestsACalmerProvider() {
        XCTAssertEqual(
            say([row("claude", 42), row("codex", 86, reset: 4.0 / 3)]),
            "Codex 已经用了 86%，1小时20分后重置，先换 Claude 吧！"
        )
    }

    func testNearLimitWithNothingCalmer() {
        XCTAssertEqual(say([row("codex", 86, reset: 1)]), "Codex 已经用了 86%，1小时后重置，省着点用哦～")
    }

    func testAllFine() {
        XCTAssertEqual(say([row("claude", 42), row("codex", 18)]), "额度都很充足，放心用吧～")
        XCTAssertEqual(say([row("claude", 42)]), "Claude 额度很充足，放心用吧～")
    }

    func testStandInSaysWhoRanOutAndWhenItReturns() {
        XCTAssertEqual(
            say([row("claude", 100, reset: 2 + 5.0 / 60), row("codex", 63)]),
            "Claude 用完了……2小时5分后恢复。先去用 Codex 吧！"
        )
        XCTAssertEqual(
            say([row("claude", 100, reset: nil), row("codex", 63)]),
            "Claude 用完了，恢复时间未知。先去用 Codex 吧！"
        )
        XCTAssertEqual(
            say([row("claude", 100), row("gemini", 100), row("codex", 63)]),
            "Claude、Gemini 都用完了……先去用 Codex 吧！"
        )
    }

    func testAllUsedUpSaysWhenTheFirstComesBack() {
        XCTAssertEqual(
            say([row("claude", 100, reset: 2), row("codex", 100, reset: 0.75)]),
            "大家都用完了，Codex 45分钟后最先恢复，先休息一下吧 zzz"
        )
        XCTAssertEqual(
            say([row("claude", 100, reset: nil)]),
            "大家都用完了，恢复时间还不知道……先休息一下吧 zzz"
        )
    }

    func testCharacterDemoWalksThroughTheHandOver() {
        let scenes = DemoScenarios.characterScenes(now: now).map { pick($0.providers) }
        XCTAssertEqual(scenes.map { $0?.providerID }, ["claude", "codex", "codex", "codex"])
        XCTAssertEqual(scenes.map { $0?.mood }, [.normal, .worried, .normal, .exhausted])
        XCTAssertEqual(scenes[2]?.reason, .standIn(exhaustedIDs: ["claude"]))
    }

    // MARK: Active agent

    private func pick(_ providers: [ProviderUsage], active: String?) -> MascotChoice? {
        MascotPicker.pick(providers, thresholds: .standard, now: now, activeProviderID: active, status: status)
    }

    private func say(_ providers: [ProviderUsage], active: String?) -> String {
        guard let choice = pick(providers, active: active) else { return "" }
        return MascotPicker.sentence(for: choice, providers: providers, thresholds: .standard, now: now, status: status)
    }

    func testActiveAgentIsShownWithItsOwnMood() {
        let providers = [row("claude", 42), row("codex", 86)]
        XCTAssertEqual(pick(providers, active: "claude"), MascotChoice(providerID: "claude", mood: .normal, reason: .active))
        XCTAssertEqual(pick(providers, active: "codex"), MascotChoice(providerID: "codex", mood: .worried, reason: .active))
        XCTAssertEqual(say(providers, active: "claude"), "正在用 Claude，额度还剩 58%，放心用～")
        XCTAssertEqual(say(providers, active: "codex"), "正在用 Codex，已经用了 86%，2小时后重置，快不够的话换 Claude 吧！")
    }

    func testActiveAgentMatchesAccountRows() {
        let choice = pick([row("codex", 10), row("claude:work", 30)], active: "claude")
        XCTAssertEqual(choice?.providerID, "claude:work")
    }

    func testUsedUpActiveAgentHandsOver() {
        let providers = [row("codex", 100, reset: 2 + 5.0 / 60), row("claude", 100), row("gemini", 40)]
        XCTAssertEqual(pick(providers, active: "codex")?.reason, .standIn(exhaustedIDs: ["codex", "claude"]))
        let single = [row("claude", 100, reset: 2 + 5.0 / 60), row("codex", 63)]
        XCTAssertEqual(pick(single, active: "claude")?.providerID, "codex")
        XCTAssertEqual(say(single, active: "claude"), "Claude 用完了……2小时5分后恢复。先去用 Codex 吧！")
    }

    func testActiveAgentNotInThePanelIsIgnored() {
        XCTAssertEqual(pick([row("claude", 40), row("codex", 86)], active: "gemini")?.reason, .mostUrgent)
        XCTAssertEqual(pick([row("claude", 40)], active: nil)?.reason, .mostUrgent)
    }
}

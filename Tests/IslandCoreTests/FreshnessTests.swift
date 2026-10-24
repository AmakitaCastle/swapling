import XCTest
@testable import IslandCore

final class FreshnessTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 100_000)

    private func row(_ id: String, used: Double = 40, updatedAt: Date? = nil, fetchedAt: Date? = nil, error: String? = nil) -> ProviderUsage {
        ProviderUsage(
            id: id,
            windows: [QuotaWindow(id: "primary", title: "5 小时", usedPercent: used)],
            error: error,
            updatedAt: updatedAt,
            fetchedAt: fetchedAt
        )
    }

    func testSourceTimeWinsAndIsLabelledUpdated() {
        let freshness = Freshness.of(
            row("codex", updatedAt: now.addingTimeInterval(-180), fetchedAt: now),
            refreshInterval: 120, now: now
        )
        XCTAssertEqual(freshness?.kind, .source)
        XCTAssertEqual(freshness?.label(now: now), "更新于 3 分钟前")
        XCTAssertEqual(freshness?.isStale, false)
    }

    func testCollectionTimeIsLabelledCollected() {
        let freshness = Freshness.of(row("claude", fetchedAt: now.addingTimeInterval(-60)), refreshInterval: 120, now: now)
        XCTAssertEqual(freshness?.kind, .collected)
        XCTAssertEqual(freshness?.label(now: now), "采集于 1 分钟前")
    }

    func testOldSourceDataIsStaleEvenIfTheRefreshJustSucceeded() {
        // Read a moment ago, but the source says the numbers are an hour old.
        let provider = row("codex", updatedAt: now.addingTimeInterval(-3600), fetchedAt: now)
        let freshness = Freshness.of(provider, refreshInterval: 120, now: now)
        XCTAssertEqual(freshness?.isStale, true)
        XCTAssertEqual(freshness?.warning, "数据已过期")
        XCTAssertFalse(Freshness.isCurrent(provider, refreshInterval: 120, now: now))
    }

    func testStaleBoundary() {
        // 2 × 120 s + 30 s slack.
        XCTAssertEqual(Freshness.staleAfter(refreshInterval: 120), 270)
        XCTAssertFalse(Freshness.of(row("a", fetchedAt: now.addingTimeInterval(-270)), refreshInterval: 120, now: now)!.isStale)
        XCTAssertTrue(Freshness.of(row("a", fetchedAt: now.addingTimeInterval(-271)), refreshInterval: 120, now: now)!.isStale)
    }

    func testFutureTimestampsDoNotLookNewerThanNow() {
        let freshness = Freshness.of(row("a", updatedAt: now.addingTimeInterval(600)), refreshInterval: 120, now: now)
        XCTAssertEqual(freshness?.date, now)
    }

    func testErrorWithoutNumbersHasNoFreshness() {
        let failed = ProviderUsage(id: "claude", error: "No session key")
        XCTAssertNil(Freshness.of(failed, refreshInterval: 120, now: now))
        XCTAssertFalse(Freshness.isCurrent(failed, refreshInterval: 120, now: now))
    }

    func testMergeStampsFreshRowsAndKeepsFailedRowsMarked() {
        let earlier = now.addingTimeInterval(-600)
        let previous = [row("codex", used: 30, fetchedAt: earlier), row("claude", used: 70, fetchedAt: earlier)]
        let fetched = [row("codex", used: 35), ProviderUsage(id: "claude", error: "timed out")]

        let merged = Freshness.merge(previous: previous, fetched: fetched, now: now)

        XCTAssertEqual(merged[0].fetchedAt, now)
        XCTAssertFalse(merged[0].isCarriedOver)
        XCTAssertEqual(merged[0].windows.first?.usedPercent, 35)

        // The failed provider keeps its old numbers and old time, flagged and in error.
        XCTAssertEqual(merged[1].windows.first?.usedPercent, 70)
        XCTAssertEqual(merged[1].fetchedAt, earlier)
        XCTAssertTrue(merged[1].isCarriedOver)
        XCTAssertEqual(merged[1].error, "timed out")
        let freshness = Freshness.of(merged[1], refreshInterval: 120, now: now)
        XCTAssertEqual(freshness?.isStale, true)
        XCTAssertEqual(freshness?.warning, "本次读取失败，显示的是上次的数据")
        XCTAssertEqual(freshness?.label(now: now), "采集于 10 分钟前")
    }

    func testMergeDropsTurnedOffProvidersAndRecoversCarriedRows() {
        let carried: ProviderUsage = {
            var r = row("claude", fetchedAt: now.addingTimeInterval(-600), error: "timed out")
            r.isCarriedOver = true
            return r
        }()
        let merged = Freshness.merge(previous: [carried, row("gemini")], fetched: [row("claude", used: 10)], now: now)
        XCTAssertEqual(merged.map(\.id), ["claude"])
        XCTAssertFalse(merged[0].isCarriedOver)
        XCTAssertNil(merged[0].error)
        XCTAssertEqual(merged[0].fetchedAt, now)
    }

    func testFailureWithNoEarlierNumbersStaysAnError() {
        let merged = Freshness.merge(previous: [], fetched: [ProviderUsage(id: "claude", error: "x")], now: now)
        XCTAssertFalse(merged[0].hasData)
        XCTAssertFalse(merged[0].isCarriedOver)
    }

    func testTurningEveryProviderOffClearsOldCards() {
        // CU-B01: after switching off every provider, the closed Claude card stayed as 正常.
        let previous = [row("claude", fetchedAt: now)]
        XCTAssertTrue(Freshness.afterFailedRefresh(previous, issue: .notConfigured).isEmpty)
    }

    func testOtherWholeRefreshFailuresKeepNumbersMarkedOld() {
        let previous = [row("claude", fetchedAt: now), ProviderUsage(id: "openai", error: "x")]
        let kept = Freshness.afterFailedRefresh(previous, issue: .timeout)
        XCTAssertEqual(kept.map(\.id), ["claude", "openai"])
        XCTAssertTrue(kept[0].isCarriedOver)
        XCTAssertFalse(kept[1].isCarriedOver, "nothing to carry over on a row without numbers")
        // Kept numbers are never current, so the card shows 未知 rather than 正常.
        XCTAssertFalse(Freshness.isCurrent(kept[0], refreshInterval: 120, now: now))
        XCTAssertEqual(Freshness.of(kept[0], refreshInterval: 120, now: now)?.warning, "本次读取失败，显示的是上次的数据")
    }
}
